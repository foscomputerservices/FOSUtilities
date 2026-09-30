// BehavioralValidationTests.swift
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

/// Design 1.3 steps 2–5 (field validation, the gate, model validation) and 1.6 (model-level
/// messages). The localized text of a refusal is read by encoding the thrown error.
@Suite("Behavioral: field validation and model validation")
struct BehavioralValidationTests: LocalizableTestCase {
    @Test("Model validation never runs when field validation failed")
    func modelValidationIsSkippedWhenFieldValidationFailed() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            let error = await #expect(throws: ValidationError.self) {
                try await BehavioralProbe(title: BehavioralTitle.fieldInvalid).save(on: db)
            }

            let messages = try texts(of: #require(error))
            #expect(messages == ["That title is not allowed"])
            #expect(box.events(of: BehavioralProbe.self) == ["willWrite(create)"])
        }
    }

    @Test("Model validation returns every failure and the refusal carries all of them")
    func modelValidationCollectsEveryFailure() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let error = await #expect(throws: ValidationError.self) {
                try await BehavioralProbe(title: BehavioralTitle.modelMany).save(on: db)
            }

            let messages = try texts(of: #require(error))
            #expect(messages == [
                "The box is full",
                "The second failure",
                "The third failure"
            ])
        }
    }

    @Test("Model validation runs on an archive, where field validation does not")
    func modelValidationRunsOnArchive() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            probe.title = BehavioralTitle.modelError
            let error = await #expect(throws: ValidationError.self) {
                try await probe.delete(on: db)
            }

            let messages = try texts(of: #require(error))
            #expect(messages == ["The box is full"])
            let live = try await BehavioralProbe.query(on: db).count()
            #expect(live == 1)
        }
    }

    @Test("Model validation runs on a destroy")
    func modelValidationRunsOnDestroy() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            probe.title = BehavioralTitle.modelError
            await #expect(throws: ValidationError.self) {
                try await probe.delete(force: true, on: db)
            }

            let live = try await BehavioralProbe.query(on: db).count()
            #expect(live == 1)
        }
    }

    @Test("Model validation runs on a restore")
    func modelValidationRunsOnRestore() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)
            try await probe.delete(on: db)

            let archived = try #require(await BehavioralProbe.query(on: db).withDeleted().first())
            archived.title = BehavioralTitle.modelError
            await #expect(throws: ValidationError.self) {
                try await archived.restore(on: db)
            }

            let live = try await BehavioralProbe.query(on: db).count()
            #expect(live == 0)
        }
    }

    @Test("A message with no field addresses the model")
    func modelValidationFailureAddressesTheModel() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralProbe(title: BehavioralTitle.modelError).save(on: db)
            })

            let message = try #require(error.validations.first?.messages.first)
            #expect(message.addressesModel)
        }
    }

    @Test("A field failure does not address the model")
    func fieldFailureDoesNotAddressTheModel() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralProbe(title: BehavioralTitle.fieldInvalid).save(on: db)
            })

            let message = try #require(error.validations.first?.messages.first)
            #expect(!message.addressesModel)
        }
    }

    /// negative space: "Throw only for a failure of the query itself" (DocC 4.4) — a throw from
    /// model validation is an error, never a validation, so it must not arrive as a ValidationError.
    @Test("A throw from model validation is an error, not a validation")
    func modelValidationThrowIsAnErrorNotAValidation() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            await #expect(throws: BehavioralHookFailure(hook: "validateModel")) {
                try await BehavioralProbe(title: BehavioralTitle.modelThrow).save(on: db)
            }
        }
    }

    @Test("A model does not collide with itself on an update")
    func updateOfSelfPasses() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralContainment(app)
        } _: { _, db in
            let container = BehavioralBox(name: "Bedrock")
            try await container.save(on: db)
            let item = try BehavioralItem(title: "Fred", boxId: container.requireID())
            try await item.save(on: db)

            // Saving the same model again re-runs every rule; the uniqueness rule excludes itself.
            try await item.save(on: db)

            let count = try await BehavioralItem.query(on: db).count()
            #expect(count == 1)
        }
    }

    @Test("The same value in two containers is allowed")
    func sameValueInTwoContainersIsAllowed() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralContainment(app)
        } _: { _, db in
            let first = BehavioralBox(name: "Bedrock")
            let second = BehavioralBox(name: "Granite City")
            try await first.save(on: db)
            try await second.save(on: db)

            try await BehavioralItem(title: "Fred", boxId: first.requireID()).save(on: db)
            try await BehavioralItem(title: "Fred", boxId: second.requireID()).save(on: db)

            let count = try await BehavioralItem.query(on: db).count()
            #expect(count == 2)
        }
    }

    @Test("The same value twice in one container is refused, with the model's message")
    func sameValueInOneContainerIsRefused() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralContainment(app)
        } _: { _, db in
            let container = BehavioralBox(name: "Bedrock")
            try await container.save(on: db)
            try await BehavioralItem(title: "Fred", boxId: container.requireID()).save(on: db)

            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralItem(title: "Fred", boxId: container.requireID()).save(on: db)
            })

            let messages = try texts(of: error)
            #expect(messages == ["That title is already used in this box"])
            let count = try await BehavioralItem.query(on: db).count()
            #expect(count == 1)
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
