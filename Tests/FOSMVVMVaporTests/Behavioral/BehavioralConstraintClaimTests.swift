// BehavioralConstraintClaimTests.swift
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

/// Design 1.7 ("Constraint violations") and OQ7: the middleware offers the failure to the model;
/// a claim becomes a `ValidationError`, a declined one stays the error it was.
///
/// The claim hook receives no context, so each fixture is handed the application's own claim
/// counter at construction and the suite keeps its counts to itself.
@Suite("Behavioral: constraint claim")
struct BehavioralConstraintClaimTests: LocalizableTestCase {
    @Test("A claimed violation becomes a ValidationError carrying the model's message")
    func claimedViolationBecomesAValidationError() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralClaimant.self, migration: CreateBehavioralClaimant())
        } _: { app, db in
            let claims = app.behavioralClaims
            try await BehavioralClaimant(title: "Fred", claims: claims).save(on: db)

            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralClaimant(title: "Fred", claims: claims).save(on: db)
            })

            let messages = try texts(of: error)
            #expect(messages == ["That title is already claimed"])
            #expect(claims.count("claimant") == 1)
            let written = try await BehavioralClaimant.query(on: db).count()
            #expect(written == 1)
        }
    }

    @Test("A declined violation stays the original error, not a ValidationError")
    func declinedViolationStaysTheOriginalError() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralDecliner.self, migration: CreateBehavioralDecliner())
        } _: { app, db in
            let claims = app.behavioralClaims
            try await BehavioralDecliner(title: "Fred", claims: claims).save(on: db)

            var thrown: (any Error)?
            do {
                try await BehavioralDecliner(title: "Fred", claims: claims).save(on: db)
            } catch {
                thrown = error
            }

            let error = try #require(thrown)
            #expect(!(error is ValidationError))
            #expect(claims.count("decliner") == 1)
        }
    }

    /// negative space: "It asks the model … for a ValidationResult describing it" — the hook is
    /// offered a violation ONLY when the driver refused the write.
    @Test("The claim hook is not offered anything when the write succeeds")
    func claimIsNotOfferedWhenTheWriteSucceeds() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralClaimant.self, migration: CreateBehavioralClaimant())
        } _: { app, db in
            let claims = app.behavioralClaims
            try await BehavioralClaimant(title: "Fred", claims: claims).save(on: db)
            try await BehavioralClaimant(title: "Wilma", claims: claims).save(on: db)

            #expect(claims.count("claimant") == 0)
        }
    }

    /// negative space: a claim answered with a WARNING result. The write already failed at the
    /// driver, so there is nothing for the advisory policy to let through — the refusal stands.
    @Test("A warning-status claim still stops the write")
    func warningClaimStillStopsTheWrite() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralWarningClaimant.self, migration: CreateBehavioralWarningClaimant())
        } _: { _, db in
            try await BehavioralWarningClaimant(title: "Fred").save(on: db)

            await #expect(throws: ValidationError.self) {
                try await BehavioralWarningClaimant(title: "Fred").save(on: db)
            }

            let written = try await BehavioralWarningClaimant.query(on: db).count()
            #expect(written == 1)
        }
    }

    @Test("A model with both a unique index and a foreign key claims only the one it recognises")
    func dualConstraintModelClaimsOnlyTheUniqueIndex() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralBox.self, migration: CreateBehavioralBox())
            app.migrations.add(CreateBehavioralItem())
            app.migrations.add(CreateBehavioralTag())
            app.migrations.add(CreateBehavioralBoxTag())
            try app.register(BehavioralDualConstraint.self, migration: CreateBehavioralDualConstraint())
        } _: { app, db in
            let claims = app.behavioralClaims
            let container = BehavioralBox(name: "Bedrock")
            try await container.save(on: db)
            try await BehavioralDualConstraint(title: "Fred", boxId: container.requireID(), claims: claims).save(on: db)

            // The unique index: claimed, so the client sees a message.
            let claimed = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralDualConstraint(title: "Fred", boxId: container.requireID(), claims: claims).save(on: db)
            })
            let messages = try texts(of: claimed)
            #expect(messages == ["That title is already claimed"])

            // The foreign key: the same hook is offered the violation and declines it, so the
            // original error survives.
            var thrown: (any Error)?
            do {
                try await BehavioralDualConstraint(title: "Barney", boxId: ModelIdType(), claims: claims).save(on: db)
            } catch {
                thrown = error
            }
            let fkError = try #require(thrown)
            #expect(!(fkError is ValidationError))
            #expect(claims.count("dual") == 2)
        }
    }

    // MARK: - Reading a refusal's text

    private func texts(of error: any Error) throws -> [String] {
        let validationError = try #require(error as? ValidationError)
        let decoded: ValidationError = try validationError
            .toJSON(encoder: encoder(locale: Self.en))
            .fromJSON()
        return try decoded.validations
            .flatMap(\.messages)
            .map { try $0.message.localizedString }
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(bundle: .module, resourceDirectoryName: "TestYAML")
    }
}
