// BehavioralWarningPolicyTests.swift
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

/// Design 1.8 ("Warning policy") and OQ28 ("the `ValidationError` carries every result collected").
@Suite("Behavioral: warning policy")
struct BehavioralWarningPolicyTests: LocalizableTestCase {
    @Test("Under the default policy a model-validation warning lets the write proceed")
    func advisoryWarningProceeds() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            try await BehavioralProbe(title: BehavioralTitle.modelWarning).save(on: db)

            let written = try await BehavioralProbe.query(on: db).count()
            #expect(written == 1)
        }
    }

    /// negative space: the gate reads "Errors, or warnings under a blocking policy, stop here" —
    /// a FIELD-level warning under the default policy must not stop the write either.
    @Test("Under the default policy a field-validation warning lets the write proceed")
    func advisoryFieldWarningProceeds() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            try await BehavioralProbe(title: BehavioralTitle.fieldWarning).save(on: db)

            let written = try await BehavioralProbe.query(on: db).count()
            #expect(written == 1)
        }
    }

    @Test("Under .blocking a model-validation warning stops the write and reaches the client")
    func blockingWarningStopsTheWrite() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralBlocker.self, migration: CreateBehavioralBlocker())
        } _: { _, db in
            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralBlocker(title: BehavioralTitle.modelWarning).save(on: db)
            })

            let messages = try texts(of: error)
            #expect(messages == ["This model looks odd"])
            let written = try await BehavioralBlocker.query(on: db).count()
            #expect(written == 0)
        }
    }

    /// negative space: the first gate (step 3) runs under the same policy as the second, so a
    /// blocking model stops on a FIELD warning before model validation is reached.
    @Test("Under .blocking a field-validation warning stops the write before model validation runs")
    func blockingFieldWarningStopsAtTheFirstGate() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralBlocker.self, migration: CreateBehavioralBlocker())
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralBlocker(title: BehavioralTitle.fieldWarning).save(on: db)
            })

            let messages = try texts(of: error)
            #expect(messages == ["That title is unusual"])
            #expect(box.events(of: BehavioralBlocker.self).isEmpty)
        }
    }

    @Test("An advisory warning collected alongside an error rides with it")
    func advisoryWarningRidesWithAnError() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralProbe(title: BehavioralTitle.modelMixed).save(on: db)
            })

            let messages = try texts(of: error)
            #expect(messages == ["This model looks odd", "The box is full"])
            let written = try await BehavioralProbe.query(on: db).count()
            #expect(written == 0)
        }
    }

    /// negative space: a validateModel that returns a warning AND an error under .blocking — one
    /// refusal, both results, no double-reporting of the warning.
    @Test("Under .blocking a warning and an error arrive together, once each")
    func blockingWarningAndErrorArriveTogether() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralBlocker.self, migration: CreateBehavioralBlocker())
        } _: { _, db in
            let error = try #require(await #expect(throws: ValidationError.self) {
                try await BehavioralBlocker(title: BehavioralTitle.modelMixed).save(on: db)
            })

            let messages = try texts(of: error)
            #expect(messages == ["This model looks odd", "The box is full"])
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
