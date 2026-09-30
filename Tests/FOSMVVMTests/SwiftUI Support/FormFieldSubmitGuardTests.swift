// FormFieldSubmitGuardTests.swift
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

#if canImport(SwiftUI)
import FOSFoundation
@testable import FOSMVVM
import Foundation
import SwiftUI
import Testing

private struct TestSubmitGuardFields {
    let title: String
}

/// `FormFieldView.onSubmit` proceeds only when `validateIt` answers **true**; the field's
/// validator decides, and only an error stops the submission.
@Suite("FormFieldView submit guard")
@MainActor
struct FormFieldSubmitGuardTests {
    private static let titleId = #fieldId(\TestSubmitGuardFields.title)

    private static func fieldModel() -> FormFieldModel<String> {
        .init(.init(
            fieldId: titleId,
            title: .constant("Title"),
            type: .text(inputType: .text)
        ))
    }

    private static func submits(_ status: ValidationResult.Status?) -> Bool {
        FormFieldView<String>.validateIt(
            fieldModel: fieldModel(),
            fieldValidator: { _ in
                guard let status else { return nil }
                return [.init(status: status, fieldId: titleId, message: .constant("a message"))]
            },
            validations: Validations()
        )
    }

    @Test("An error stops the submission")
    func errorStopsSubmit() {
        #expect(!Self.submits(.error))
    }

    @Test("A warning does not stop the submission")
    func warningProceeds() {
        #expect(Self.submits(.warning))
    }

    @Test("Information does not stop the submission")
    func infoProceeds() {
        #expect(Self.submits(.info))
    }

    @Test("A validator that produces nothing does not stop the submission")
    func noResultsProceeds() {
        #expect(Self.submits(nil))
    }

    @Test("A field without a validator does not stop the submission")
    func noValidatorProceeds() {
        #expect(FormFieldView<String>.validateIt(
            fieldModel: Self.fieldModel(),
            fieldValidator: nil,
            validations: Validations()
        ))
    }

    @Test("The validator's results reach the Validations the form shows")
    func resultsReachValidations() {
        let validations = Validations()

        FormFieldView<String>.validateIt(
            fieldModel: Self.fieldModel(),
            fieldValidator: { _ in
                [.init(status: .error, fieldId: Self.titleId, message: .constant("title is required"))]
            },
            validations: validations
        )

        #expect(validations.hasError(for: Self.titleId))
    }
}
#endif
