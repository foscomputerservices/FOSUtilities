// ValidationsTests.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Testing

private struct TestValidatedFields {
    let failing: String
    let passing: String
}

@Suite("Validations")
struct ValidationsTests {
    private static let failing = #fieldId(\TestValidatedFields.failing)
    private static let passing = #fieldId(\TestValidatedFields.passing)

    @Test("A field named by a failing result has an error")
    func failingFieldHasError() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large"))
        ])

        #expect(validations.hasError(for: Self.failing))
    }

    @Test("A field no failing result names does not have an error")
    func unnamedFieldHasNoError() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large"))
        ])

        #expect(!validations.hasError(for: Self.passing))
    }

    @Test("A warning is not an error, even for the field it names")
    func warningIsNotAnError() {
        let validations = Validations([
            .init(status: .warning, fieldId: Self.failing, message: .constant("unusual"))
        ])

        #expect(!validations.hasError(for: Self.failing))
    }

    @Test("An empty set has no error for any field")
    func emptyHasNoError() {
        #expect(!Validations().hasError(for: Self.failing))
    }

    @Test("append accumulates results in the order added")
    func appendAccumulates() {
        let validations = Validations()

        validations.append(.init(status: .info, fieldId: Self.passing, message: .constant("first")))
        validations.append(contentsOf: [
            .init(status: .warning, fieldId: Self.failing, message: .constant("second")),
            .init(status: .error, message: .constant("third"))
        ])

        #expect(validations.validations.count == 3)
        #expect(validations.validations.map(\.status) == [.info, .warning, .error])
        #expect(validations.status == .error)
    }

    @Test("removeAll clears every result")
    func removeAllClears() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large")),
            .init(status: .error, message: .constant("the model is full"))
        ])

        validations.removeAll()

        #expect(validations.validations.isEmpty)
        #expect(validations.modelMessages.isEmpty)
    }

    @Test("modelMessages reports only the messages that name no field")
    func modelMessagesNameNoField() throws {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large")),
            .init(status: .error, message: .constant("the model is full"))
        ])

        let modelMessages = validations.modelMessages
        #expect(modelMessages.count == 1)
        let message = try #require(modelMessages.first)
        #expect(try message.message.localizedString == "the model is full")
    }

    @Test("modelMessages is empty when every message names a field")
    func modelMessagesEmptyWhenAllFielded() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.failing, message: .constant("too large"))
        ])

        #expect(validations.modelMessages.isEmpty)
    }

    @Test("replace(with:) replaces the model-level messages when the answer carries any")
    func replaceReplacesModelLevelMessages() throws {
        let validations = Validations([
            .init(status: .error, message: .constant("stale model refusal"))
        ])

        validations.replace(with: [
            .init(status: .error, message: .constant("fresh model refusal"))
        ])

        let modelMessages = validations.modelMessages
        #expect(modelMessages.count == 1)
        let message = try #require(modelMessages.first)
        #expect(try message.message.localizedString == "fresh model refusal")
    }

    @Test("replace(with:) leaves the model-level messages when the answer is field-only")
    func replaceFieldOnlyLeavesModelLevel() throws {
        let validations = Validations([
            .init(status: .error, message: .constant("the model is full")),
            .init(status: .error, fieldId: Self.failing, message: .constant("too large"))
        ])

        validations.replace(with: [
            .init(status: .warning, fieldId: Self.failing, message: .constant("unusual"))
        ])

        let modelMessages = validations.modelMessages
        #expect(modelMessages.count == 1)
        let message = try #require(modelMessages.first)
        #expect(try message.message.localizedString == "the model is full")
        #expect(!validations.hasError(for: Self.failing))
    }

    @Test("A Fields validate run twice on one Validations answers once per field")
    func fieldsValidateTwiceDoesNotDuplicate() throws {
        let fields = TestValidatedFields(failing: "", passing: "ok")
        let validations = Validations()

        _ = fields.validate(fields: nil, validations: validations)
        _ = fields.validate(fields: nil, validations: validations)

        #expect(validations.validations.count == 1)
        let messages = try #require(validations.validations.first?.messages(for: Self.failing))
        #expect(messages.count == 1)
        #expect(try messages.first?.message.localizedString == "required")
    }
}

/// The shape the fields generator scaffolds: the per-field rules are gathered, then handed to
/// `replace(with:)` — the Fields rules own exactly the fields they name.
extension TestValidatedFields: ValidatableModel {
    func validate(fields _: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
        var results = [ValidationResult]()
        if failing.isEmpty {
            results.append(
                .init(
                    status: .error,
                    fieldId: #fieldId(\TestValidatedFields.failing),
                    message: .constant("required")
                )
            )
        }
        validations.replace(with: results)
        return validations.status
    }
}
