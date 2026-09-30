// ModelLevelValidationTests.swift
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

private struct TestModelLevelFields {
    let title: String
}

@Suite("Model-level validation results")
struct ModelLevelValidationTests {
    @Test("A result built without a field addresses the model")
    func resultWithoutFieldAddressesModel() throws {
        let result = ValidationResult(status: .error, message: .constant("the model is full"))

        let message = try #require(result.messages.first)
        #expect(message.addressesModel)
        #expect(result.messages(for: #fieldId(\TestModelLevelFields.title)) == nil)
    }

    @Test("A result built for a field does not address the model")
    func resultForFieldDoesNotAddressModel() throws {
        let result = ValidationResult(
            status: .error,
            fieldId: #fieldId(\TestModelLevelFields.title),
            message: .constant("title is required")
        )

        let message = try #require(result.messages.first)
        #expect(!message.addressesModel)
    }

    @Test("A model-level result survives a Codable round trip")
    func modelLevelResultRoundTrips() throws {
        let result = ValidationResult(status: .error, message: .constant("the model is full"))

        let roundTripped: ValidationResult = try result.toJSON().fromJSON()

        #expect(roundTripped == result)
        let message = try #require(roundTripped.messages.first)
        #expect(message.addressesModel)
        #expect(try message.message.localizedString == "the model is full")
    }

    @Test("A ValidationError carrying a model-level message survives a Codable round trip")
    func validationErrorWithModelMessageRoundTrips() throws {
        let error = ValidationError(validation: .init(status: .error, message: .constant("the model is full")))

        let roundTripped: ValidationError = try error.toJSON().fromJSON()

        let message = try #require(roundTripped.validations.first?.messages.first)
        #expect(message.addressesModel)
        #expect(try message.message.localizedString == "the model is full")
    }
}
