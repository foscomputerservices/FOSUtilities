// FormFieldModel.swift
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

/// A property wrapper to host ``FormField``s in a ``ViewModel``
///
/// ``FormField``s enable bringing together ``FormField`` descriptions and ``ValidatableModel``
/// descriptions, which enables rich field specifications with simple, easy to understand syntax.
///
/// > The example shown here shows just the ``FormFieldModel`` portion of the example.  See also:
/// > ``FormField``, ``ValidatableModel`` and ``FormFieldView``
///
/// ## Example
///
/// ```swift
/// @ViewModel final class UserFormModel: UserFields {
///
///     @FormFieldModel(UserFormModel.emailField) public var email: String?
///     @FormFieldModel(UserFormModel.firstNameField) public var firstName: String?
///     @FormFieldModel(UserFormModel.lastNameField) public var lastName: String?
///
///     public let validationMessages: UserFieldsMessages
///
///     public init(email: String?, firstName: String?, lastName: String?) {
///         self.validationMessages = .init()
///
///         self.$email.initialValue = email
///         self.$firstName.initialValue = firstName
///         self.$lastName.initialValue = lastName
///     }
/// }
/// ```
@propertyWrapper @Observable
public final class FormFieldModel<Value>: Codable, ResettableModel, @unchecked Sendable where Value: Codable & Hashable {
    public private(set) var vmId: ViewModelId = .init()

    public var formField: FormField<Value>
    public var projectedValue: FormFieldModel { self }
    public let saveButtonTitle: LocalizableString
    public let cancelButtonTitle: LocalizableString
    public var hasValue: Bool { _value != nil }

    private var _initialValue: Value?
    private var _value: Value?
    public var wrappedValue: Value {
        get {
            let value = _value ?? _initialValue
            let result: Value

            // Apple says "Only the Optional type conforms to ExpressibleByNilLiteral"
            if let value = value as? ExpressibleByNilLiteral.Type {
                result = (value as! Value) // swiftlint:disable:this force_cast
            }

            // Optional, but no default: specified
            else if value == nil, Value.self is ExpressibleByNilLiteral.Type {
                // The compiler is lost and has no idea what the type is.
                // We've established the type at runtime and can ignore the compiler error
                // here (there's no way to tell the compiler to be quiet).
                result = (value as! Value) // swiftlint:disable:this force_cast
            } else {
                guard value != nil else {
                    fatalError("You must provide a default value to the @FormFieldModel(..., default: <default value>).")
                }

                result = value!
            }

            return result
        }

        set {
            _value = newValue
        }
    }

    // MARK: ResettableModel

    public func resetModel() {
        _value = nil
    }

    /// Sets the initial value of the field
    ///
    /// The value that the field will be reset to when the ``ResettableModel`` protocol
    /// is invoked
    ///
    /// > ``ViewModels`` that want to initialize their ``FormFieldModel`` values should call
    /// > this property as opposed to setting the value directly.
    ///
    /// ## Example
    ///
    ///  ``` swift
    ///     struct MyModel: ViewModel {
    ///       @FormFieldModel(UserFormModel.firstNameField) public var firstName: String?
    ///
    ///       init(firstName: String?) {
    ///         self.$firstName.initialValue = firstName // <-- Correct way
    ///         self.firstName = firstName // *** Incorrect way ***
    ///       }
    ///     }
    ///  ```
    public var initialValue: Value? {
        get { _initialValue }
        set {
            _initialValue = newValue
            resetModel()
        }
    }

    /// Initializes a new `FormFieldModel`
    ///
    /// > If *formField* is not provided during initialization, it **must** be provided
    /// > before use.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyModel: ViewModel {
    ///   @FormFieldModel public var myDelayedField: Int?
    ///
    ///   init(aParam: AType) {
    ///     self.$myDelayedField.formField = /* ... call that uses aParam ... */
    ///   }
    /// }
    /// ```
    public required init(_ formField: FormField<Value> = .dummy, default initialValue: Value? = nil, saveButtonTitle: LocalizableString? = nil) {
        self.formField = formField
        self.saveButtonTitle = saveButtonTitle ?? .defaultSaveTitle
        self.cancelButtonTitle = .defaultCancelTitle

        let def = initialValue ?? Self.defaultValue

        self._value = def
        self._initialValue = def
    }

    // MARK: Codable Protocol

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.formField = try container.decode(FormField.self, forKey: .formField)
        self._value = try container.decode(Value.self, forKey: .value)
        self._initialValue = try container.decodeIfPresent(Value.self, forKey: .initialValue) ?? Self.defaultValue
        self.saveButtonTitle = try container.decode(LocalizableString.self, forKey: .saveButtonTitle)
        self.cancelButtonTitle = try container.decode(LocalizableString.self, forKey: .cancelButtonTitle)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(wrappedValue, forKey: .value)
        try container.encode(_initialValue, forKey: .initialValue)
        try container.encode(formField, forKey: .formField)
        try container.encode(saveButtonTitle, forKey: .saveButtonTitle)
        try container.encode(cancelButtonTitle, forKey: .cancelButtonTitle)
    }

    private enum CodingKeys: String, CodingKey {
        case formField
        case value
        case initialValue
        case saveButtonTitle
        case cancelButtonTitle
    }

    private static var defaultValue: Value? {
        let any: Any? = switch Value.self {
        case is Int.Type: Int(0)
        case is UInt.Type: UInt(0)
        case is Double.Type: Double(0.0)
        case is Date.Type: Date()
        case is String.Type: ""
        case is Bool.Type: false
        default: nil
        }

        return any as! Value? // swiftlint:disable:this force_cast
    }
}

public extension FormFieldModel where Value == String {
    var wrappedValueRemovingWhitespace: String {
        wrappedValue.trimmingCharacters(in: .whitespaces)
    }
}

public extension FormFieldModel where Value == String? {
    var wrappedValueRemovingWhitespace: String? {
        wrappedValue?.trimmingCharacters(in: .whitespaces)
    }
}

public extension FormField {
    /// Returns a dummy `FormField` that can be substituted later on
    static var dummy: FormField {
        .init(fieldId: .init(id: "dummy"), title: .empty, type: .text(inputType: .text))
    }
}
