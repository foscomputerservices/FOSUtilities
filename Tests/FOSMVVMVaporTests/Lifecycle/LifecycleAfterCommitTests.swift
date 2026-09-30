// LifecycleAfterCommitTests.swift
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

// The three after-commit routes, each observed through the hook log. Live invalidation is never
// enabled here: the after-commit hook does not depend on it.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("didCommit routing (plan 1.3 step 8, OQ3, OQ14)")
struct LifecycleAfterCommitTests {
    /// An auto-commit save has already committed by the time the middleware returns, so the hook
    /// runs there and then — with no live invalidation anywhere in the application.
    @Test func didCommitRunsOnAnAutoCommitSave() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)
            try await Entry(label: "auto", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                .save(on: db)

            #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 1)
        }
    }

    /// Inside `liveTransaction` the hook waits for the commit: nothing has run while the closure is
    /// still open, and it has run once the call returns.
    @Test func didCommitWaitsForTheTransactionToCommit() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)

            try await app.liveTransaction { tx in
                try await Entry(label: "deferred", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                    .save(on: tx)
                #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 0)
            }

            #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 1)
        }
    }

    /// A `liveTransaction` owns only the writes made on its own handle: a save issued on the
    /// application's auto-commit handle while the transaction is open is already durable, so its
    /// hook runs there and then rather than riding the unrelated commit.
    @Test func didCommitRunsAtOnceForAnAutoCommitSaveInsideALiveTransaction() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let req = Vapor.Request(application: app, on: app.eventLoopGroup.next())

            try await req.liveTransaction { tx in
                try await Entry(label: "auto-commit", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                    .save(on: app.db)
                #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 1)

                try await Entry(label: "deferred", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                    .save(on: tx)
                #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 1)
            }

            #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 2)
        }
    }

    /// A rolled-back transaction commits nothing, so the hook never runs.
    @Test func didCommitNeverRunsWhenTheTransactionRollsBack() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)

            await #expect(throws: LifecycleFailure.didWrite) {
                try await app.liveTransaction { tx in
                    try await Entry(label: "kept", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                        .save(on: tx)
                    try await Entry(label: "rollback", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                        .save(on: tx)
                }
            }

            #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 0)
            let count = try await Entry.query(on: db).count()
            #expect(count == 0)
        }
    }

    /// A bare `database.transaction` exposes no commit to wait for, so the hook is suppressed
    /// rather than run early.
    @Test func didCommitIsSuppressedInsideABareTransaction() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)

            try await db.transaction { tx in
                try await Entry(label: "bare", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                    .save(on: tx)
            }

            #expect(app.lifecycleEvents.count(of: "Entry.didCommit:create") == 0)
            let count = try await Entry.query(on: db).count()
            #expect(count == 1) // the write itself committed; only the hook was suppressed
        }
    }
}
