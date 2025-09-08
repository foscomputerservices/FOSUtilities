// FormField.swift
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

/// An abstract description of a field to present on a SwiftUI Form
///
/// > Typically ``FormField`` is used as the implementation of ``FormFieldBase``
public protocol FormFieldBase: Codable {
    // MARK: Properties

    /// A unique (in the scope of the form) identity for the field
    var fieldId: FormFieldIdentifier { get }

    /// Describes the type of control to allow the user to interact with the data
    var type: FormFieldType { get }

    /// A title describing the field
    var title: LocalizableString { get }

    /// Optional text that can be shown to the user when the user
    /// has not yet entered a value; often an example of a valid value.
    var placeholder: LocalizableString? { get }
}

public extension Collection<FormFieldBase> {
    func contains(_ field: FormField<some Any>) -> Bool {
        map(\.fieldId).contains(field)
    }
}

/// A rich description of a field to be presented in a form
///
/// ``FormField`` describes how to present and manipulate data in a way that is understandable
/// to the user.  When combined with a ``FormFieldView``, all of the heavy (and often tedious and repetitive)
/// code is automatically taken care of (e.g., proper keyboard layouts, when to allow auto-correct, tagging
/// the data type so that the OS can suggest data, etc.)
///
/// Typically ``FormField`` specifications are co-located with ``ValidatableModel`` descriptions
/// as static fields.  These fields are the bound to ``ViewModel`` data via ``FormFieldModel`` and then
/// presented as views via ``FormFieldView``.  This meta-data includes all aspects of the user experience:
///
///    - Selecting the proper control to present the data to the user in a platform-consistent manner
///    - For platforms that have customizable keyboards, the correct keyboard layout is presented to be
///         consistent with the data type (e.g., numeric, email)
///    - For platforms that have auto-complete, the correct auto-complete mode is chosen that is consistent with the data
///    - Binding value to/from the data model to the field
///    - Validating the user's input
///
/// > The example shown here shows just the ``FormField`` portion of the example.  See also:
/// > ``FormFieldModel`` and ``ValidatableModel``
///
/// ## Example
///
/// ```swift
/// protocol UserFields: Codable, Sendable, ValidatableModel {
///     var email: String? { get set }
///     var firstName: String? { get set }
///     var lastName: String { get set }
/// }
///
/// extension UserFields {
///     // MARK: Email
///
///     static var emailRange: ClosedRange<Int> { 4...254 }
///
///     static var emailField: FormField<String?> { .init(
///         fieldId: .init(id: "email"),
///         title: .localized(for: Self.self, parentKeys: "email", propertyName: "title"),
///         placeholder: .localized(for: Self.self, parentKeys: "email", propertyName: "placeholder"),
///         type: .text(inputType: .emailAddress),
///         options: [
///             .minLength(value: emailRange.lowerBound),
///             .maxLength(value: emailRange.upperBound),
///             .required(value: true),
///             .autocomplete(value: .email),
///             .autocapitalize(value: .never)
///         ]
///     )}
///
///     // MARK: firstName
///
///     static var firstNameMaxLength: Int { 191 }
///
///     static var firstNameField: FormField<String?> { .init(
///         fieldId: .init(id: "firstName"),
///         title: .localized(for: Self.self, parentKeys: "firstName", propertyName: "title"),
///         placeholder: .localized(for: Self.self, parentKeys: "firstName", propertyName: "placeholder"),
///         type: .text(inputType: .givenName),
///         options: [
///             .maxLength(value: firstNameMaxLength),
///             .required(value: true),
///             .autocomplete(value: .givenName),
///             .autocapitalize(value: .words)
///         ]
///     )}
///
///     // MARK: lastName
///
///     static var lastNameMaxLength: Int { 191 }
///
///     static var lastNameField: FormField<String?> { .init(
///         fieldId: .init(id: "lastName"),
///         title: .localized(for: Self.self, parentKeys: "lastName", propertyName: "title"),
///         placeholder: .localized(for: Self.self, parentKeys: "lastName", propertyName: "placeholder"),
///         type: .text(inputType: .givenName),
///         options: [
///             .maxLength(value: lastNameMaxLength),
///             .required(value: true),
///             .autocomplete(value: .familyName),
///             .autocapitalize(value: .words)
///         ]
///     )}
/// }
/// ```
public struct FormField<Value>: FormFieldBase, Sendable where Value: Codable & Hashable {
    // MARK: FormFieldBase Protocol

    public let fieldId: FormFieldIdentifier
    public let title: LocalizableString
    public let type: FormFieldType
    public let placeholder: LocalizableString?

    /// A set of `FormInputOption`s that modify the presentation of the `FormField`
    ///
    /// - Note: These options are updatable so that localized data can be substituted
    ///   for validation at points after the creation of the field.  This is because
    ///   ``FormField``s are generally specified as static members of a ``ViewModel``.
    ///   Just before the ``FormField`` is applied to a ``FormFieldView``, the options
    ///   can be tailored to data in the ``ViewModel``.  For example:
    ///
    ///   ``` swift
    ///      let fieldModel = bodyViewModel.$date
    ///      fieldModel.formField.options += [
    ///          .minDate(date: bodyViewModel.userDateOfBirth)
    ///      ]
    ///
    ///      return FormFieldView(
    ///            fieldModel: fieldModel, // ...
    ///   ```
    public var options: [FormInputOption<Value>]

    // MARK: Initializers

    /// Initializes the `FormField`
    ///
    /// - Parameters:
    ///     - fieldId: A ``FormFieldIdentifier`` used to key any data sent back to the server for this field
    ///     - title: A title to display to the user for this field
    ///     - placeholder: Displayed as placeholder text when the control supports placeholder text
    ///     - type: The `FormFieldType` to use to display the field's data in the form
    ///     - options: Any options to configure the form field
    public init(fieldId: FormFieldIdentifier, title: LocalizableString, placeholder: LocalizableString? = nil, type: FormFieldType, options: [FormInputOption<Value>] = []) {
        self.fieldId = fieldId
        self.title = title
        self.placeholder = placeholder
        self.type = type
        self.options = Self.adjustedOptions(type: type, options: options)
    }
}

public extension FormField {
    var autocomplete: FormInputOption<Value>.Autocomplete? {
        for opt in options {
            if case FormInputOption.autocomplete(let value) = opt {
                return value
            }
        }

        return nil
    }

    var autocapitalize: FormInputOption<Value>.Autocapitalize? {
        for opt in options {
            if case FormInputOption.autocapitalize(let value) = opt {
                return value
            }
        }

        return nil
    }

    var disabled: Bool? {
        for opt in options {
            if case FormInputOption.disabled(let value) = opt {
                return value
            }
        }

        return nil
    }

    var required: Bool? {
        for opt in options {
            if case FormInputOption.required(let value) = opt {
                return value
            }
        }

        return nil
    }

    var dateRange: ClosedRange<Date> {
        var minDate: Date?
        var maxDate: Date?

        for option in options {
            if case FormInputOption.minDate(let date) = option {
                minDate = date
            } else if case FormInputOption.maxDate(let date) = option {
                maxDate = date
            }
        }

        return (minDate ?? Date.distantPast)...(maxDate ?? Date.distantFuture)
    }
}

private extension FormField {
    static func adjustedOptions(type: FormFieldType, options: [FormInputOption<Value>]) -> [FormInputOption<Value>] {
        // If they didn't specify a size for the date field, add one automatically
        var options = options
        if case FormFieldType.text(let inputType) = type,
           inputType == .date || inputType == .datetimeLocal,
           options.count(where: {
               if case FormInputOption.size = $0 { return true }
               return false
           }) == 0 {
            options.append(FormInputOption<Value>.size(value: inputType == .date
                    ? FormInputOption<Value>.defaultDateSize
                    : FormInputOption<Value>.defaultDateTimeSize
            ))
        }

        return options
    }
}

#if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
import UIKit

public extension FormField {
    // Maps the `FormInputType` to the `UITextConteType` for the field, if one is available
    var textContentType: UITextContentType? {
        switch type {
        case .text(let inputType): inputType.textContentType
        case .textArea(let inputType): inputType.textContentType
        case .checkbox, .colorPicker, .select: nil
        }
    }
}
#endif

#if os(watchOS)
import WatchKit

public extension FormField {
    // Maps the `FormInputType` to the `WKTextContentType` for the field, if one is available
    var textContentType: WKTextContentType? {
        switch type {
        case .text(let inputType): inputType.textContentType
        case .textArea(let inputType): inputType.textContentType
        case .checkbox, .colorPicker, .select: nil
        }
    }
}
#endif
