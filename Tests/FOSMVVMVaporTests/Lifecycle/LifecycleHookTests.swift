// LifecycleHookTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Every assertion goes through public API: a save, and the hook log the fixture model keeps.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("DataModel lifecycle hooks (plan 1.3, task group G5)")
struct LifecycleHookTests {
    /// The pinned order for one create: the model may change itself, then the form rules run, then
    /// the model is judged against the database, then the write, then the same-transaction work,
    /// then the durable side effect.
    @Test func hooksRunInThePinnedOrder() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "first", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            try await entry.save(on: db)

            #expect(entry.trace == [
                "willWrite", "fieldValidation", "validateModel", "didWrite", "didCommit"
            ])
        }
    }

    /// `willWrite` may change the model, and what it changed is what lands in the row.
    @Test func willWriteChangesWhatIsWritten() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "  padded  ", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            try await entry.save(on: db)

            let stored = try #require(await Entry.find(entry.requireId(), on: db))
            #expect(stored.label == "padded")
        }
    }

    /// A throw from `willWrite` is an error, never a validation refusal — and nothing is written.
    @Test func willWriteThrowIsNotAValidationRefusal() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "unwritable", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            await #expect(throws: LifecycleFailure.willWrite) {
                try await entry.save(on: db)
            }
            #expect(try await Entry.query(on: db).count() == 0)
        }
    }

    /// Field validation answers for the model's own columns, so only create and update run it;
    /// every action runs model validation.
    @Test func fieldValidationRunsOnCreateAndUpdateOnly() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "kept", ledgerId: ledger.requireId(), vaultId: vault.requireId())
            try await entry.save(on: db)
            #expect(entry.trace.count { $0 == "fieldValidation" } == 1)

            entry.label = "renamed"
            try await entry.save(on: db)
            #expect(entry.trace.count { $0 == "fieldValidation" } == 2)

            try await entry.delete(on: db) // soft — the model carries a delete timestamp
            try await entry.restore(on: db)
            try await entry.delete(force: true, on: db)

            #expect(entry.trace.count { $0 == "fieldValidation" } == 2)
            #expect(entry.trace.count { $0 == "validateModel" } == 5)
        }
    }

    /// Each action reaches the hooks as what Fluent is about to do to the row.
    @Test func everyActionReachesTheHooks() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "cycled", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            try await entry.save(on: db)
            entry.label = "cycled again"
            try await entry.save(on: db)
            try await entry.delete(on: db)
            try await entry.restore(on: db)
            try await entry.delete(force: true, on: db)

            let willWrites = app.lifecycleEvents.all.filter { $0.hasPrefix("Entry.willWrite:") }
            #expect(willWrites == [
                "Entry.willWrite:create",
                "Entry.willWrite:update",
                "Entry.willWrite:archive",
                "Entry.willWrite:restore",
                "Entry.willWrite:destroy"
            ])
        }
    }

    /// A model with no delete timestamp is destroyed by either delete call.
    @Test func deleteOfAModelWithNoTimestampIsDestroy() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let beacon = Beacon(note: "transient")
            try await beacon.save(on: db)
            try await beacon.delete(on: db)

            #expect(app.lifecycleEvents.all.contains("Beacon.willWrite:destroy"))
            #expect(app.lifecycleEvents.all.contains("Beacon.willWrite:archive") == false)
        }
    }

    /// `didWrite` runs in the write's own transaction, so its throw takes the row with it.
    @Test func didWriteThrowRollsBackTheRow() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "rollback", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            await #expect(throws: LifecycleFailure.didWrite) {
                try await app.liveTransaction { tx in
                    try await entry.save(on: tx)
                }
            }

            #expect(try await Entry.query(on: db).count() == 0)
        }
    }

    /// A batch write issues its one statement only after every model has been through the
    /// middleware, so the hooks that guard the write run and the two that need a row do not — and
    /// the statement still lands.
    @Test func aBatchWriteRunsTheGuardingHooksOnly() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entries = try (1...3).map {
                try Entry(label: "batch\($0)", ledgerId: ledger.requireId(), vaultId: vault.requireId())
            }

            try await entries.create(on: db)

            for entry in entries {
                #expect(entry.trace == ["willWrite", "fieldValidation", "validateModel"])
            }
            #expect(try await Entry.query(on: db).count() == 3)

            try await entries.delete(on: db)

            for entry in entries {
                #expect(entry.trace == [
                    "willWrite", "fieldValidation", "validateModel", "willWrite", "validateModel"
                ])
            }
            #expect(try await Entry.query(on: db).count() == 0)
            #expect(try await Entry.query(on: db).withDeleted().count() == 3)
        }
    }
}
