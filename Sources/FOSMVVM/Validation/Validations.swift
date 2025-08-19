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

@Observable public final class Validations {
    public var validations: [ValidationResult] = []

    public var status: ValidationResult.Status? {
        validations.aggregate
    }

    public var validationError: ValidationError? {
        guard status == .error else { return nil }

        return .init(validations: validations)
    }

    public func replace(with newValidations: [ValidationResult]) {
        let replacingFieldIds = Set(
            newValidations.flatMap { val in
                val.messages.map(
                    \.fieldIds
                )
            }.flatMap(\.self))
        let trimmedValidations = validations.compactMap { validation in
            var validation = validation
            for removeFieldId in replacingFieldIds {
                validation.removeMessages(for: removeFieldId)
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

            validations = trimmedValidations
        } else {
            validations = []
        }
    }

    public init(_ elements: [ValidationResult] = []) {
        self.validations = elements
    }
}
