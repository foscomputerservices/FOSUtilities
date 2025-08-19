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

/// Defines a model that contains data and the validations that ensure the integrity of the data
///
/// The suggested way to implement validation, is to implement functions for each property that
/// validate that property's data.  Then implement ``validate(fields:validations:)``
/// combining each property's results.
///
/// ## Example
///
/// ```swift
/// protocol UserFields: AnyObject, Codable, Sendable, ValidatableModel {
///     var email: String? { get set }
///     var firstName: String? { get set }
///     var lastName: String { get set }
///
///     var validationMessages: UserFieldsMessages { get }
/// }
///
/// @ValidationModel public struct UserFieldsMessages: FieldValidationModel {
///     @LocalizedString(parentKey: "email", propertyName: "required") public var emailRequired
///     @LocalizedString(parentKey: "firstName", propertyName: "required") public var firstNameRequired
///     @LocalizedString(parentKey: "firstName", propertyName: "required") public var firstNameTooLong
/// }
///
/// extension UserFields {
///     func validateEmail(_ fields: [FormFieldBase]?) -> [ValidationResult]? {
///         guard fields == nil || fields!.map(\.fieldId).contains(.init(id: "email")) else {
///             return nil
///         }
///
///         var result = [ValidationResult]()
///
///         if email?.isEmpty == true {
///             result.append(.init(status: .error, field: Self.emailField, message: validationMessages.emailRequired))
///         }
///
///         return result.isEmpty ? nil : result
///     }
///
///     func validateFirstName(_ fields: [FormFieldBase]?) -> [ValidationResult]? {
///         guard fields == nil || fields!.map(\.fieldId).contains(.init(id: "firstName")) else {
///             return nil
///         }
///
///         var result = [ValidationResult]()
///
///         if firstName?.isEmpty == true {
///             firstName = nil
///                 result.append(.init(
///                     status: .error,
///                     field: Self.firstNameField,
///                     message: validationMessages.firstNameRequired
///                 ))
///         }
///
///         if let firstName, NSString(string: firstName).length > Self.firstNameMaxLength {
///             result.append(.init(
///                 status: .error,
///                 field: Self.firstNameField,
///                 message: validationMessages.firstNameTooLong
///             ))
///         }
///
///         return result.isEmpty ? nil : result
///     }
///
///     func validateLastName(_ fields: [FormFieldBase]?) -> [ValidationResult]? { /* ... */ }
///
///     // MARK: ValidatableModel
///
///     func validate(fields: [FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
///         var result = [ValidationResult]()
///
///         result += validateEmail(fields)
///         result += validateFirstName(fields)
///         result += validateLastName(fields)
///
///         // If there are cross-field constraints, verify them here
///
///         if !result.isEmpty {
///             validations.elements = result
///         }
///
///         return .init(for: result)
///     }
/// }
/// ```
public protocol ValidatableModel {
    /// Performs all validation checks on the ``ViewModel``
    ///
    /// Each field in the ``ViewModel`` is validated and any ``ValidationResult`` models that are
    /// generated are added to validations.  The result of the function is a call to validations.status.
    ///
    /// - Parameters:
    ///   - fields: If specified, restricts the fields to be checked; nil checks all fields
    ///   - validations: An instance of ``Validations`` that will be added to if the validation checks
    /// - Returns: The status of **validations** (e.g., validations.status)
    func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status?
}

public extension ValidationResult.Status {
    init?(for validationResults: (any Collection<ValidationResult>)?) {
        guard let validations = validationResults, !validations.isEmpty else { return nil }

        var status: Self = .info

        forLoop: for valResponse in validations {
            switch valResponse.status {
            case .info: if status < .info { status = .info }
            case .warning: if status < .warning { status = .warning }
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
