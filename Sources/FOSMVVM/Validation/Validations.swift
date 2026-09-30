// Validations.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

import Foundation
import Observation

/// The validation results a form shows, kept in the SwiftUI environment
///
/// Add results with `append`, swap a field's results with `replace(with:)`, clear with
/// `removeAll`; read `validations` to inspect them:
///
/// ```swift
/// validations.append(.init(status: .error, fieldId: #fieldId(\CardFields.title), message: messages.titleRequired))
/// validations.replace(with: responseError.validations)
/// validations.removeAll()
/// ```
@Observable public final class Validations {
    /// Every result, in the order added. Change it through `append`, `replace(with:)` and `removeAll`.
    public private(set) var validations: [ValidationResult] = []

    /// Adds one result
    public func append(_ result: ValidationResult) {
        validations.append(result)
    }

    /// Adds results
    public func append(contentsOf results: some Sequence<ValidationResult>) {
        validations.append(contentsOf: results)
    }

    /// The messages that are about the model as a whole, across every result
    ///
    /// ```swift
    /// ForEach(validations.modelMessages, id: \.self) { Text($0.message) }
    /// ```
    ///
    /// Empty when every message names a field.
    public var modelMessages: [ValidationResult.Message] {
        validations.flatMap(\.messages).filter(\.addressesModel)
    }

    public var status: ValidationResult.Status? {
        validations.aggregate
    }

    public var isValid: Bool {
        !hasError
    }

    public var hasError: Bool {
        status == .error
    }

    /// Whether one field failed validation
    ///
    /// ```swift
    /// if viewModel.validations.hasError(for: fieldId) {
    ///     proxy.scrollTo(fieldId)
    /// }
    /// ```
    ///
    /// ``hasError`` answers for the form as a whole; this answers for one field, which is what
    /// a view showing that field needs — to mark it, to focus it, or to bring it on screen.
    ///
    /// A field carrying only warnings or information does not have an error.
    public func hasError(for fieldId: FormFieldIdentifier) -> Bool {
        validations.contains { validation in
            validation.hasError && validation.messages(for: fieldId) != nil
        }
    }

    public var validationError: ValidationError? {
        guard status == .error else { return nil }

        return .init(validations: validations)
    }

    /// Swaps in a new answer for the fields it names
    ///
    /// ```swift
    /// validations.replace(with: responseError.validations)
    /// ```
    ///
    /// Field messages are replaced per field. Model-level messages are replaced whenever the
    /// incoming results carry any; a field-only replacement leaves them.
    public func replace(with newValidations: [ValidationResult]) {
        let replacingFieldIds = Set(
            newValidations.flatMap { val in
                val.messages.map(
                    \.fieldIds
                )
            }.flatMap(\.self)
        )
        let replacesModelMessages = newValidations.contains { validation in
            validation.messages.contains(where: \.addressesModel)
        }
        let trimmedValidations = validations.compactMap { validation in
            var validation = validation
            for removeFieldId in replacingFieldIds {
                validation.removeMessages(for: removeFieldId)
            }
            if replacesModelMessages {
                validation.removeModelMessages()
            }

            return validation.messages.isEmpty ? nil : validation
        }
        validations = trimmedValidations + newValidations
    }

    public func replace(with validations: Validations) {
        self.validations = validations.validations
    }

    public func removeAll(fieldIds: [FormFieldIdentifier]? = nil) {
        guard !validations.isEmpty else { return }

        if let fieldIds, !fieldIds.isEmpty {
            let trimmedValidations = validations.compactMap { validation in
                var validation = validation
                for removeFieldId in fieldIds {
                    validation.removeMessages(for: removeFieldId)
                }

                return validation.messages.isEmpty ? nil : validation
            }

            if validations.count != trimmedValidations.count {
                validations = trimmedValidations
            }
        } else if !validations.isEmpty {
            validations = []
        }
    }

    public init(_ elements: [ValidationResult] = []) {
        self.validations = elements
    }
}
