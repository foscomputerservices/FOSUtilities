// FormFieldView.swift
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

#if canImport(SwiftUI)
import Combine
import Foundation
import SwiftUI

/// A SwiftUI View to display ``FormFieldModel``s
///
/// The ``FormFieldView`` maps all of the aspects of the ``FormFieldModel``'s ``FormField``
/// description to the target platform's capabilities.
///
/// ## Example
///
/// > The example shown here just shows the ``FormFieldView`` portion of the example.  See also:
/// > ``ValidatableModel``, ``FormField`` and ``FormFieldModel``
///
/// ```swift
/// public struct UserFormView: ViewModelView {
///     let viewModel: UserFormModel
///
///     var body: some View {
///         Form {
///           FormFieldView(fieldModel: viewModel.$email)
///           FormFieldView(fieldModel: viewModel.$firstName)
///           FormFieldView(fieldModel: viewModel.$lastName)
///         }
///     }
/// }
/// ```
public struct FormFieldView<Value>: View where Value: Codable & Hashable {
    @State private var fieldModel: FormFieldModel<Value>
    @State private var hasChanged = false
    @FocusState private var hasFocus: Bool

    let fieldValidator: (([FormFieldBase]?) -> [ValidationResult]?)?
    let validations: Validations?
    let onNewValue: ((Value) -> Void)?
    let onSubmit: ((Value) -> Void)?

    private let newValueSubject: PassthroughSubject<Value, Never>
    private let newValueCancelable: AnyCancellable?

    public var body: some View {
        fieldView
            .focused($hasFocus)
            .withValidations(for: fieldModel)
            .onChange(of: hasFocus) {
                guard hasChanged, Self.validateIt(
                    fieldModel: fieldModel,
                    fieldValidator: fieldValidator,
                    validations: validations
                ) == true else {
                    return
                }
            }
    }

    /// Initializes the ``FieldView`` with the provided parameters
    ///
    /// # Delayed New Value
    ///
    /// The callback to the ``onNewValue:`` function will be delayed by ``newValueDelay:``
    /// seconds after the user ceases typing.  This can be used to initiate an activity after the
    /// user has entered some (presumably complete) data (e.g., initiate  a search).
    ///
    /// - Parameters:
    ///   - fieldModel: The ``FormFieldModel`` of the ``FieldView`` to present to the user
    ///   - onNewValue: Called when a new value is received from the user (whitespace is automatically trimmed)
    ///   - newValueDelay: An amount of time to wait after the user's last key is typed before
    ///      calling ``onNewValue:`` (default: 0.75)
    ///   - onSubmit: Called when the user "performs the action (typically, hit the return key)"
    public init(
        fieldModel: FormFieldModel<Value>,
        fieldValidator: (([FormFieldBase]?) -> [ValidationResult]?)? = nil,
        validations: Validations? = nil,
        onNewValue: ((Value) -> Void)? = nil,
        newValueDelay: TimeInterval = 0.75,
        onSubmit: ((Value) -> Void)? = nil
    ) {
        self._fieldModel = .init(wrappedValue: fieldModel)
        self.fieldValidator = fieldValidator
        self.validations = validations
        self.onNewValue = onNewValue
        self.onSubmit = { newValue in
            fieldModel.wrappedValue = newValue

            guard Self.validateIt(
                fieldModel: fieldModel,
                fieldValidator: fieldValidator,
                validations: validations
            ) == true else {
                return
            }

            onSubmit?(newValue)
        }

        // This allows onNewValue to be called after the user stops typing
        self.newValueSubject = PassthroughSubject<Value, Never>()
        self.newValueCancelable = newValueSubject
            .debounce(for: .seconds(newValueDelay), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { newValue in
                fieldModel.wrappedValue = newValue
                onNewValue?(newValue)
            }
    }

    private static func validateIt(
        fieldModel: FormFieldModel<Value>,
        fieldValidator: (([FormFieldBase]?) -> [ValidationResult]?)?,
        validations: Validations?
    ) -> Bool {
        let validations = validations ?? Validations()
        if let fieldValidator {
            validations.removeAll(fieldIds: [fieldModel.formField.fieldId])
            if let result = fieldValidator([fieldModel.formField]),
               !result.isEmpty {
                validations.replace(with: result)
                return validations.status == .error
            }
        }

        return true
    }

    /// A factory to create a `Binding` that forwards updates to the *newValueSubject*
    private func wrappedValueBinding() -> Binding<Value> {
        .init(
            get: { fieldModel.wrappedValue },
            set: { newValue in
                if !hasChanged, fieldModel.wrappedValue == newValue {
                    return
                }

                if fieldModel.wrappedValue != newValue {
                    fieldModel.wrappedValue = newValue
                    hasChanged = true

                    if let str = newValue as? String {
                        newValueSubject
                            // swiftlint:disable:next force_cast
                            .send(str.trimmingCharacters(in: .whitespaces) as! Value)
                    } else {
                        newValueSubject.send(newValue)
                    }
                }
            }
        )
    }
}

private extension FormFieldView where Value == String? {
    func wrappedValueBinding() -> Binding<String> {
        .init(
            get: { fieldModel.wrappedValue ?? "" },
            set: { newValue in
                if !hasChanged, fieldModel.wrappedValue == newValue {
                    return
                }

                if fieldModel.wrappedValue != newValue {
                    fieldModel.wrappedValue = newValue
                    hasChanged = true

                    fieldModel.wrappedValue = newValue
                    newValueSubject
                        .send(newValue.trimmingCharacters(in: .whitespaces))
                }
            }
        )
    }
}

private extension FormFieldView {
    @ViewBuilder var fieldView: some View {
        // swiftlint:disable force_cast
        if Value.self is String.Type {
            (self as! FormFieldView<String>).stringFieldView(
                onSubmit: onSubmit as! ((String) -> Void)?
            )
        } else if Value.self is String?.Type {
            (self as! FormFieldView<String?>).stringFieldView(
                onSubmit: onSubmit as! ((String?) -> Void)?
            )
        } else if Value.self is Date.Type {
            (self as! FormFieldView<Date>).dateFieldView(
                onNewValue: onNewValue as! ((Date) -> Void)?,
                onSubmit: onSubmit as! ((Date) -> Void)?
            )
        } else if Value.self is Int.Type {
            (self as! FormFieldView<Int>).intFieldView(
                onSubmit: onSubmit as! ((Int) -> Void)?
            )
        } else if Value.self is Double.Type {
            (self as! FormFieldView<Double>).doubleFieldView(
                onSubmit: onSubmit as! ((Double) -> Void)?
            )
        } else if Value.self is Bool.Type {
            (self as! FormFieldView<Bool>).boolFieldView(
                onSubmit: onSubmit as! ((Bool) -> Void)?
            )
        } else if Value.self is Int?.Type {
            (self as! FormFieldView<Int?>).intFieldView(
                onSubmit: onSubmit as! ((Int?) -> Void)?
            )
        } else {
            fatalError("FormFieldView for type \(String(describing: Value.self)) is not implemented.")
        }
        // swiftlint:enable force_cast
    }
}

private extension FormFieldView where Value == Bool {
    @ViewBuilder func boolFieldView(onSubmit: ((Value) -> Void)?) -> some View {
        switch fieldModel.formField.type {
        case .checkbox:
            Toggle(
                (try? fieldModel.formField.title.localizedString) ?? "",
                isOn: wrappedValueBinding()
            )
        default:
            fatalError("\(fieldModel.formField.type) not valid for Bool fields")
        }
    }
}

private extension FormFieldView where Value == String {
    @ViewBuilder func stringFieldView(onSubmit: ((Value) -> Void)?) -> some View {
        switch fieldModel.formField.type {
        case .text(let inputType), .textArea(let inputType):
            switch inputType {
            case .password, .newPassword:
                SecureField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .textContentType(.password)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(.never)
                #endif

            case .text, .location, .fullStreetAddress, .streetAddressLine1, .streetAddressLine2:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(
                        fieldModel.formField.autocapitalize?.textAutocapitalizationType ?? .sentences
                    )
                    .textContentType(fieldModel.formField.textContentType)
                #endif

            case .name, .namePrefix, .givenName, .middleName, .familyName, .nameSuffix, .nickname,
                 .addressCity, .addressCityAndState, .subLocality, .countryName:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(
                        fieldModel.formField.autocapitalize?.textAutocapitalizationType ?? .words
                    )
                    .textContentType(fieldModel.formField.textContentType)
                #endif

            case .postalCode, .creditCardNumber, .oneTimeCode:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(fieldModel.formField.autocapitalize?.textAutocapitalizationType ?? .never)
                    .textContentType(fieldModel.formField.textContentType)
                #endif

            case .telephoneNumber:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
                    .keyboardType(.phonePad)
                #endif
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                .textContentType(fieldModel.formField.textContentType)
                #endif

            case .emailAddress, .userName: // Our user names are always email addresses
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(true)
                #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
                    .keyboardType(.emailAddress)
                #endif
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                .textContentType(fieldModel.formField.textContentType)
                .textInputAutocapitalization(.never)
                #endif

            default:
                Text("The FormInputType \(inputType.rawValue) is NYI!")
            }

        default:
            fatalError("\(fieldModel.formField.type) not valid for String fields")
        }
    }
}

private extension FormFieldView where Value == String? {
    @ViewBuilder func stringFieldView(onSubmit: ((Value) -> Void)?) -> some View {
        switch fieldModel.formField.type {
        case .text(let inputType), .textArea(let inputType):
            switch inputType {
            case .text, .location, .fullStreetAddress, .streetAddressLine1, .streetAddressLine2:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(fieldModel.formField.autocapitalize?.textAutocapitalizationType ?? .sentences)
                    .textContentType(fieldModel.formField.textContentType)
                #endif

            case .name, .namePrefix, .givenName, .middleName, .familyName, .nameSuffix, .nickname,
                 .addressCity, .addressCityAndState, .subLocality, .countryName:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(fieldModel.formField.autocapitalize?.textAutocapitalizationType ?? .words)
                    .textContentType(fieldModel.formField.textContentType)
                #endif

            case .postalCode, .creditCardNumber, .oneTimeCode:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                    .textInputAutocapitalization(
                        fieldModel.formField.autocapitalize?.textAutocapitalizationType ?? .never
                    )
                    .textContentType(fieldModel.formField.textContentType)
                #endif

            case .telephoneNumber:
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(fieldModel.formField.autocomplete == .off)
                #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
                    .keyboardType(.phonePad)
                #endif
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                .textContentType(fieldModel.formField.textContentType)
                #endif

            case .emailAddress, .userName: // Our user names are always email addresses
                TextField(
                    text: wrappedValueBinding(),
                    prompt: Text(fieldModel.formField.placeholder ?? .empty)
                ) {
                    if !fieldModel.formField.title.isEmpty {
                        Text(fieldModel.formField.title)
                    }
                }
                .onSubmit {
                    onSubmit?(fieldModel.wrappedValueRemovingWhitespace)
                }
                .disableAutocorrection(true)
                #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
                    .keyboardType(.emailAddress)
                #endif
                #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
                .textContentType(fieldModel.formField.textContentType)
                .textInputAutocapitalization(.never)
                #endif

            default:
                Text("The FormInputType \(inputType.rawValue) is NYI!")
            }

        default:
            fatalError("\(fieldModel.formField.type) not valid for String fields")
        }
    }
}

private extension FormFieldView where Value == Date {
    func dateFieldView(onNewValue: ((Value) -> Void)?, onSubmit: ((Value) -> Void)?) -> some View {
        DatePicker(
            selection: .init(
                get: { fieldModel.wrappedValue },
                set: { newDate in
                    fieldModel.wrappedValue = newDate
                    onNewValue?(fieldModel.wrappedValue)
                    onSubmit?(fieldModel.wrappedValue)
                }
            ),
            in: fieldModel.formField.dateRange,
            displayedComponents: .date,
            label: { Text(fieldModel.formField.title) }
        )
        .datePickerStyle(DefaultDatePickerStyle())
    }
}

private extension FormFieldView where Value == Int {
    @ViewBuilder func intFieldView(onSubmit: ((Value) -> Void)?) -> some View {
        switch fieldModel.formField.type {
        case .text:
            TextField(
                value: wrappedValueBinding(),
                formatter: NumberFormatter(),
                prompt: Text(fieldModel.formField.placeholder ?? .empty)
            ) {
                if !fieldModel.formField.title.isEmpty {
                    Text(fieldModel.formField.title)
                }
            }
            .onSubmit {
                onSubmit?(fieldModel.wrappedValue)
            }
            #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
            .keyboardType(.numberPad)
            #endif
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
            .textContentType(fieldModel.formField.textContentType)
            #endif

        default:
            fatalError("\(fieldModel.formField.type) not valid for Int? fields")
        }
    }
}

private extension FormFieldView where Value == Int? {
    @ViewBuilder func intFieldView(onSubmit: ((Value) -> Void)?) -> some View {
        switch fieldModel.formField.type {
        case .text:
            TextField(
                value: wrappedValueBinding(),
                formatter: NumberFormatter(),
                prompt: Text(fieldModel.formField.placeholder ?? .empty)
            ) {
                if !fieldModel.formField.title.isEmpty {
                    Text(fieldModel.formField.title)
                }
            }
            .onSubmit {
                onSubmit?(fieldModel.wrappedValue)
            }
            #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
            .keyboardType(.numberPad)
            #endif
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
            .textContentType(fieldModel.formField.textContentType)
            #endif

        default:
            fatalError("\(fieldModel.formField.type) not valid for Int? fields")
        }
    }
}

private extension FormFieldView where Value == Double {
    func doubleFieldView(onSubmit: ((Value) -> Void)?) -> some View {
        TextField(
            value: wrappedValueBinding(),
            formatter: NumberFormatter(),
            prompt: Text(fieldModel.formField.placeholder ?? .empty)
        ) {
            if !fieldModel.formField.title.isEmpty {
                Text(fieldModel.formField.title)
            }
        }
        .onSubmit {
            onSubmit?(fieldModel.wrappedValue)
        }
        #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
        .keyboardType(.decimalPad)
        #endif
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || targetEnvironment(macCatalyst)
        .textContentType(fieldModel.formField.textContentType)
        #endif
    }
}

// #Preview {
//    Form {
//        FormFieldView<String>(fieldModel: .init(FormField(field: "string", title: .invariant(string: "A String"), placeholder: .invariant(string: "string"), type: .text(inputType: .text))))
//
//        FormFieldView<Int>(fieldModel: .init(FormField(field: "int", title: .invariant(string: "An Int"), placeholder: .invariant(string: "int"), type: .text(inputType: .number))))
//
//        FormFieldView<Date>(fieldModel: .init(FormField(field: "date", title: .invariant(string: "An Date"), placeholder: .invariant(string: "date"), type: .text(inputType: .date))))
//
//        FormFieldView<String>(fieldModel: .init(FormField(field: "picker", title: .invariant(string: "An Int"), placeholder: .invariant(string: "picker"), type: .select, options: [.selectOptions(options: [
//            .init(title: .invariant(string: "Picker"), value: "")
//        ])])))
//    }
// }
#endif
