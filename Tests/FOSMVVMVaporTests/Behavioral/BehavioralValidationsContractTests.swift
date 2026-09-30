// BehavioralValidationsContractTests.swift
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

/// The client-side accumulator, OQ21a and OQ21c (3c-3): append-only, `replace(with:)` as the
/// sanctioned reset, and model-level messages that only a new server answer replaces.
private struct BehavioralFormFields {
    let title: String
    let detail: String
}

@Suite("Behavioral: the Validations client contract")
struct BehavioralValidationsContractTests {
    private static let title = #fieldId(\BehavioralFormFields.title)
    private static let detail = #fieldId(\BehavioralFormFields.detail)

    @Test("append adds one result, in the order added")
    func appendAddsInOrder() {
        let validations = Validations()

        validations.append(.init(status: .error, fieldId: Self.title, message: .constant("first")))
        validations.append(.init(status: .warning, fieldId: Self.detail, message: .constant("second")))

        #expect(validations.validations.count == 2)
        #expect(validations.hasError(for: Self.title))
    }

    @Test("append(contentsOf:) adds every result")
    func appendContentsOfAddsEveryResult() {
        let validations = Validations()

        validations.append(contentsOf: [
            .init(status: .error, fieldId: Self.title, message: .constant("first")),
            .init(status: .error, fieldId: Self.detail, message: .constant("second"))
        ])

        #expect(validations.validations.count == 2)
    }

    @Test("removeAll clears every result")
    func removeAllClearsEverything() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.title, message: .constant("first")),
            .init(status: .error, message: .constant("the model is full"))
        ])

        validations.removeAll()

        #expect(validations.validations.isEmpty)
        #expect(validations.modelMessages.isEmpty)
    }

    @Test("removeAll(fieldIds:) removes only the named field's results")
    func removeAllForOneFieldLeavesTheOthers() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.title, message: .constant("first")),
            .init(status: .error, fieldId: Self.detail, message: .constant("second"))
        ])

        validations.removeAll(fieldIds: [Self.title])

        #expect(!validations.hasError(for: Self.title))
        #expect(validations.hasError(for: Self.detail))
    }

    /// negative space: 3c, app side — "Model-level messages are untouched by editing; they are
    /// about the model and only a new server answer replaces them". Editing one field clears that
    /// field, never the model's refusal.
    @Test("removeAll(fieldIds:) leaves the model-level messages alone")
    func removeAllForOneFieldLeavesModelMessages() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.title, message: .constant("first")),
            .init(status: .error, message: .constant("the model is full"))
        ])

        validations.removeAll(fieldIds: [Self.title])

        #expect(validations.modelMessages.count == 1)
    }

    @Test("replace(with:) replaces the incoming fields' results")
    func replaceReplacesPerField() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.title, message: .constant("stale")),
            .init(status: .error, fieldId: Self.detail, message: .constant("detail stays"))
        ])

        validations.replace(with: [
            .init(status: .warning, fieldId: Self.title, message: .constant("fresh"))
        ])

        #expect(!validations.hasError(for: Self.title))
        #expect(validations.hasError(for: Self.detail))
    }

    @Test("replace(with:) replaces the model-level messages when the incoming results carry any")
    func replaceReplacesModelMessagesWhenIncomingHasThem() throws {
        let validations = Validations([
            .init(status: .error, message: .constant("the model is full"))
        ])

        validations.replace(with: [
            .init(status: .error, message: .constant("the model is closed"))
        ])

        #expect(validations.modelMessages.count == 1)
        let message = try #require(validations.modelMessages.first)
        #expect(try message.message.localizedString == "the model is closed")
    }

    /// negative space: 3c-3 — "a per-field client validation must not clear a server-side model
    /// refusal", so a field-only replacement leaves the model-level messages standing.
    @Test("A field-only replace(with:) leaves the model-level messages standing")
    func fieldOnlyReplaceLeavesModelMessages() throws {
        let validations = Validations([
            .init(status: .error, message: .constant("the model is full")),
            .init(status: .error, fieldId: Self.title, message: .constant("stale"))
        ])

        validations.replace(with: [
            .init(status: .warning, fieldId: Self.title, message: .constant("fresh"))
        ])

        #expect(validations.modelMessages.count == 1)
        let message = try #require(validations.modelMessages.first)
        #expect(try message.message.localizedString == "the model is full")
    }

    @Test("modelMessages is empty when every message names a field")
    func modelMessagesEmptyWhenEveryMessageNamesAField() {
        let validations = Validations([
            .init(status: .error, fieldId: Self.title, message: .constant("first")),
            .init(status: .error, fieldId: Self.detail, message: .constant("second"))
        ])

        #expect(validations.modelMessages.isEmpty)
    }

    @Test("modelMessages collects the model-level messages across every result")
    func modelMessagesCollectsAcrossResults() {
        let validations = Validations([
            .init(status: .error, message: .constant("the model is full")),
            .init(status: .error, fieldId: Self.title, message: .constant("first")),
            .init(status: .warning, message: .constant("the model is unusual"))
        ])

        #expect(validations.modelMessages.count == 2)
    }
}
