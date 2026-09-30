// ValidatableModel.swift
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

/// Defines the validation rules for a set of fields, shared by every type that adopts them
///
/// Put the rules on a `Fields` protocol so the request body, the form ViewModel and the
/// `DataModel` run the same checks:
///
/// ```swift
/// public protocol CardFields: ValidatableModel {
///     var title: String { get set }
///     var validationMessages: CardFieldsMessages { get }
/// }
///
/// public extension CardFields {
///     static var titleField: FormField<String> { .init(fieldId: #fieldId(\Self.title), …) }
///
///     func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
///         var results = [ValidationResult]()
///         if fields?.contains(Self.titleField) ?? true, title.isEmpty {
///             results.append(.init(status: .error, fieldId: #fieldId(\Self.title), message: validationMessages.titleRequired))
///         }
///         validations.replace(with: results)
///         return validations.status
///     }
/// }
/// ```
///
/// Hand your results to `validations.replace(with:)`: your rules own the fields they name, so a
/// form that validates on every edit re-answers for those fields instead of stacking a second copy
/// of the same message, and what a `DataModel` added after yours still stands. Pass `fields` to
/// check only the fields a form is editing; `nil` checks every field.
public protocol ValidatableModel {
    /// Answers for this model's fields, writing the results into `validations`
    ///
    /// - Parameters:
    ///   - fields: The fields to check; `nil` checks all of them
    ///   - validations: The form's accumulator, which your results replace field by field
    /// - Returns: `validations.status` once your results are in
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status?
}

public extension ValidationResult.Status {
    init?(for validationResults: (any Collection<ValidationResult>)?) {
        guard let validations = validationResults, !validations.isEmpty else { return nil }

        var status: Self = .info

        forLoop: for valResponse in validations {
            switch valResponse.status {
            case .info: if status < .info {
                    status = .info
                }
            case .warning: if status < .warning {
                    status = .warning
                }
            case .error: status = .error; break forLoop
            }
        }

        self = status
    }
}

public extension ValidatableModel {
    func validate(validations: Validations) -> ValidationResult.Status? {
        validate(fields: nil, validations: validations)
    }

    func validate(field: any FormFieldBase, validations: Validations) -> ValidationResult.Status? {
        validate(fields: [field], validations: validations)
    }

    func validate() -> ValidationError? {
        let validations = Validations()
        _ = validate(validations: validations)
        return validations.validationError
    }
}
