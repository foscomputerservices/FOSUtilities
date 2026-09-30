// LifecycleValidationTests.swift
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

// A thrown message is a LocalizableString until it is encoded, so the refusals are asserted by
// encoding the ValidationError through the suite's localizing encoder and reading the text back.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTesting
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("DataModel lifecycle validation (plan 1.3, 1.5, 1.7)")
struct LifecycleValidationTests: LocalizableTestCase {
    /// A failed form rule stops the write and answers with that rule's localized message.
    @Test func fieldValidationFailureRefusesTheWrite() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            let messages = try await refusalMessages(saving: entry, on: db)
            #expect(messages == ["A label is required"])

            let count = try await Entry.query(on: db).count()
            #expect(count == 0)
        }
    }

    /// Model validation never runs behind a failed form rule — there is nothing consistent to judge.
    @Test func fieldValidationFailureStopsModelValidation() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            await #expect(throws: ValidationError.self) {
                try await entry.save(on: db)
            }
            #expect(entry.trace == ["willWrite", "fieldValidation"])
        }
    }

    /// A model-level refusal from `validateModel` reaches the client as a validation failure.
    @Test func modelValidationRefusalCarriesItsModelLevelMessage() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let first = try Entry(label: "unique", ledgerId: ledger.requireId(), vaultId: vault.requireId())
            try await first.save(on: db)

            let second = try Entry(label: "unique", ledgerId: ledger.requireId(), vaultId: vault.requireId())
            let error = try await refusal(saving: second, on: db)

            let addressesModel = error.validations.flatMap(\.messages).allSatisfy(\.addressesModel)
            #expect(addressesModel)
            let messages = try messageText(of: error)
            #expect(messages == ["That label is already in use in this ledger"])
        }
    }

    /// Saving a row again judges it against the others, never against itself.
    @Test func updateOfAnUnchangedRowIsNotRefused() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "stable", ledgerId: ledger.requireId(), vaultId: vault.requireId())
            try await entry.save(on: db)

            try await entry.save(on: db)

            let count = try await Entry.query(on: db).count()
            #expect(count == 1)
        }
    }

    /// The rule is scoped to the container, so the same label in another ledger is fine.
    @Test func theSameLabelInAnotherLedgerIsAllowed() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let first = try await seedLedger(on: db, name: "First")
            let second = try await seedLedger(on: db, name: "Second")

            try await Entry(label: "shared", ledgerId: first.ledger.requireId(), vaultId: first.vault.requireId())
                .save(on: db)
            try await Entry(label: "shared", ledgerId: second.ledger.requireId(), vaultId: second.vault.requireId())
                .save(on: db)

            let count = try await Entry.query(on: db).count()
            #expect(count == 2)
        }
    }

    /// Model validation reads through the write's own database, so it sees a sibling written
    /// earlier in the same transaction.
    @Test func modelValidationSeesWhatTheTransactionHasWritten() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)

            await #expect(throws: ValidationError.self) {
                try await app.liveTransaction { tx in
                    try await Entry(label: "twin", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                        .save(on: tx)
                    try await Entry(label: "twin", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                        .save(on: tx)
                }
            }

            let count = try await Entry.query(on: db).count()
            #expect(count == 0) // the refusal rolled the first one back with it
        }
    }

    /// A constraint the model claims becomes a validation refusal the user can act on.
    @Test func aClaimedConstraintViolationBecomesAValidationRefusal() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            try await Stamp(code: "SAME").save(on: db)

            let error = try await refusal(saving: Stamp(code: "SAME"), on: db)
            let messages = try messageText(of: error)
            #expect(messages == ["that code is already claimed"])
        }
    }

    /// A model that declines leaves the driver's error exactly as it was.
    @Test func aDeclinedConstraintViolationStaysTheErrorItWas() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            try await Coupon(code: "SAME").save(on: db)

            var thrown: (any Error)?
            do {
                try await Coupon(code: "SAME").save(on: db)
            } catch {
                thrown = error
            }

            let error = try #require(thrown)
            #expect(!(error is ValidationError))
            #expect((error as? any DatabaseError)?.isConstraintFailure == true)
        }
    }

    // MARK: Helpers

    private func refusal(saving model: some DataModel, on db: any Database) async throws -> ValidationError {
        var thrown: (any Error)?
        do {
            try await model.save(on: db)
        } catch {
            thrown = error
        }
        return try #require(thrown as? ValidationError)
    }

    private func refusalMessages(saving model: some DataModel, on db: any Database) async throws -> [String] {
        let error = try await refusal(saving: model, on: db)
        return try messageText(of: error)
    }

    /// Resolves the refusal's messages the way the server answers a client: encode, then read.
    private func messageText(of error: ValidationError) throws -> [String] {
        let resolved: ValidationError = try error.toJSON(encoder: encoder()).fromJSON()
        return try resolved.validations.flatMap(\.messages).map { try $0.message.localizedString }
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
