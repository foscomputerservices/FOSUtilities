// LocalizedProperty.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Computer Services, LLC
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
import Foundation

public enum LocalizedPropertyError: Error, CustomDebugStringConvertible {
    case internalError(_ message: String)

    public var debugDescription: String {
        switch self {
        case .internalError(let message):
            "LocalizedPropertyError: \(message)"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}

/// # View-Model Property Binding
///
/// ``LocalizableRef`` has direct support for binding between a View-Model's property and its localized value
///
/// To use this mechanism, the top key under the Locale key must correspond exactly to the Swift type of the View-Model.
///
/// For the following examples, we will use the following YAML:
///
/// ```yaml
/// en:
///   MyViewModel:
///     property: "This is the localized string!"
/// ```
///
/// Each of the following examples accomplishes the same task, just with different supported mechanisms.
///
/// # Preferred Example: ViewModel and Property Wrapper
///
/// ```swift
/// struct MyViewModel: ViewModel {
///    @LocalizedString("property") var property
///
///    init() { }
/// }
/// ```
///
/// ## Alternative Example: Manual Binding
///
/// ``` swift
/// struct MyViewModel {
///    let property: LocalizableString
///
///    init() {
///      self.property = .localized(.init(for: Self.self, propertyName: "property"))
///    }
/// }
/// ```
///
/// ## Alternative Example: Property Field Wrapper
///
/// ```swift
/// struct MyViewModel {
///    @LocalizedPropertyField<MyType, LocalizableString>("property") var property: LocalizableString
///
///    init() { }
/// }
/// ```
///
/// - NOTE: If the View-Model is a generic type, the final type will be stripped of its
///          generic substitution and only the base type name will
///          be used as the key name.  (i.e., `MyGenericViewModel<T>` will become `MyGenericViewModel`).
///          Please note that this means that localization using @LocalizedString **cannot** be bound based
///          on the Generic type substitution ('T').  If that is required, one of the other mechanisms must
///          be used.
///
/// ## Nested Type Support
///
/// In some situations View-Models contain nested types that need their properties bound.  The *parentType* parameter
/// provides support for these situations.  Consider the following View-Model:
///
/// ```swift
/// struct ParentViewModel: ViewModel {
///   enum NestedEnum: String {
///      case option1
///      case option2
///
///      var display: LocalizableString {
///          .localized(.init(for: Self.self, parentType: ParentViewModel.self, propertyName: rawValue))
///      }
///   }
/// }
/// ```
///
/// ```yaml
///   en:
///     ParentViewModel:
///       NestedEnum:
///         option1: "Option #1"
///         option2: "Option #2"
/// ```
///
/// ## Multiple Value support
///
/// At times there are situations where having multiple values associated with a property can be handy.  For these cases,
/// there are two ways to identify such values: **Key Discriminator**s and **Index Discriminator**s.
///
/// ### Key Discriminator
///
/// A key discriminator expects a dictionary under the property name key in the YAML.
///
/// #### Example
///
/// ```swift
/// struct UserViewModel: ViewModel {
///      @LocalizedString(parentKeys: "property") var shortTitle
///      @LocalizedString(parentKeys: "property") var longTitle
/// }
/// ```
///
/// ```yaml
///   en:
///     UserViewModel:
///       property:
///         shortTitle: "Short"
///         longTitle: "A Very Long Title"
/// ```
///
/// ### Index Discriminator
///
/// An index discriminator expects an array under the property name key in the YAML.
///
/// #### Example
///
/// ```swift
/// struct UserViewModel: ViewModel {
///      @LocalizedString(propertyName: "titles", index: 0) var firstTitle
///      @LocalizedString(propertyName: "titles", index: 1) var secondTitle
/// }
/// ```
///
/// ```yaml
///   en:
///     UserViewModel:
///       titles:
///         - "First Title"
///         - "Second Title"
/// ```
///

public extension ViewModel {
    // NOTE: If something new is added here, ViewModelImplMacro.knownLocalizedPropertyNames must be updated
    typealias LocalizedString = _LocalizedProperty<Self, LocalizableString>
    typealias LocalizedInt = _LocalizedProperty<Self, LocalizableInt>
    typealias LocalizedCompoundString = _LocalizedProperty<Self, LocalizableCompoundValue<LocalizableString>>
    typealias LocalizedSubs = _LocalizedProperty<Self, LocalizableSubstitutions>
}

@propertyWrapper public struct _LocalizedProperty<Model, Value>: Codable, Sendable, Stubbable, Versionable where Model: ViewModel, Value: Localizable {
    private typealias WrappedValueBinder = @Sendable (Model, String, Encoder) throws -> Value

    public var wrappedValue: Value
    public var projectedValue: Value { wrappedValue }

    // MARK: Versionable Protocol

    public var vFirst: SystemVersion
    public var vLast: SystemVersion?

    // Identifies this property for property name binding through
    // ViewModel.propertyNames()
    public let localizationId: LocalizableId
    private let bindWrappedValue: WrappedValueBinder?

    /// Initializes the ``LocalizedString`` property wrapper
    ///
    /// - Parameters:
    ///   - parentKey: If provided, a key that is appended to *propertyName*
    ///   - propertyName: The name of the key to look up in the ``LocalizationStore``
    ///    under the ``ViewModel`` name.  If no value (default: nil) is provided, the name of the property
    ///    that the *PropertyWrapper* is attached to is used.
    ///   - index: An optional index into an arrayValue that is appended to *propertyName*  (0...n-1)
    ///
    /// - See also: ``LocalizableRef``*.init()*
    public init(parentKey: String? = nil, propertyName: String? = nil, index: Int? = nil, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableString {
        self.init(
            parentKeys: parentKey == nil ? [] : [parentKey!],
            propertyName: propertyName,
            index: index,
            vFirst: vFirst,
            vLast: vLast
        )
    }

    /// Initializes the ``LocalizedString`` property wrapper
    ///
    /// - Parameters:
    ///   - parentKeys: If provided, a set of keys that are appended to *propertyName*
    ///   - propertyName: The name of the key to look up in the ``LocalizationStore``
    ///      under the ``ViewModel`` name.  If no value (default: nil) is provided, the name of the property
    ///      that the *PropertyWrapper* is attached to is used.
    ///   - index: An optional index into an arrayValue that is appended to *propertyName*  (0...n-1)
    ///
    /// - See also: ``LocalizableRef``*.init()*
    public init(parentKeys: String..., propertyName: String? = nil, index: Int? = nil, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableString {
        self.init(
            parentKeys: Array(parentKeys),
            propertyName: propertyName,
            index: index,
            vFirst: vFirst,
            vLast: vLast
        )
    }

    /// Initializes the ``LocalizedString`` property wrapper
    ///
    /// # Example
    ///
    /// ```swift
    /// struct MyViewModel: ViewModel {
    ///     @LocalizedString var aLocalizedSting
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - parentKeys: If provided, a set of keys that are appended to *propertyName*
    ///   - propertyName: The name of the key to look up in the ``LocalizationStore``
    ///      under the ``ViewModel`` name.  If no value (default: nil) is provided, the name of the property
    ///      that the *PropertyWrapper* is attached to is used.
    ///   - index: An optional index into an arrayValue that is appended to *propertyName*  (0...n-1)
    ///
    /// - See also: ``LocalizableRef``*.init()*
    public init(parentKeys: [String], propertyName: String? = nil, index: Int? = nil, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableString {
        self.wrappedValue = .empty // Bound later when propertyName is set
        self.localizationId = .random(length: 10)
        self.bindWrappedValue = { _, autoPropName, _ in
            let finalPropName: String = if let propertyName, !propertyName.isEmpty {
                propertyName
            } else {
                autoPropName
            }
            return .localized(.init(
                for: Model.self,
                parentKeys: parentKeys,
                propertyName: finalPropName,
                index: index
            ))
        }
        self.vFirst = vFirst ?? SystemVersion.vInitial
        self.vLast = vLast
    }

    /// Initializes the ``LocalizedInt`` property wrapper
    ///
    /// # Example
    ///
    /// ```swift
    /// struct MyViewModel: ViewModel {
    ///     @LocalizeInt(value: 42) var aLocalizedInt
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - value: If provided, a default value for the property (default: 0)
    ///   - showGroupingSeparator: When the value is displayed, whether to display digits
    ///      separated with the grouping separator (default: true)
    ///   - groupingSize: The number of digits in the group, if showing a grouping
    ///      separator (default: 3)
    public init(value: Int? = nil, showGroupingSeparator: Bool = true, groupingSize: Int = 3, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableInt {
        self.localizationId = .random(length: 10)
        self.wrappedValue = .init(
            value: value ?? 0,
            showGroupingSeparator: showGroupingSeparator,
            groupingSize: groupingSize
        )
        self.bindWrappedValue = nil
        self.vFirst = vFirst ?? .vInitial
        self.vLast = vLast
    }

    /// Initializes the ``LocalizedCompoundString`` property wrapper
    ///
    /// # Example
    ///
    /// ``` swift
    ///  struct MyViewModel: ViewModel {
    ///    @LocalizedStrings var pieces
    ///    @LocalizedString var separator
    ///    @LocalizedCompoundString(pieces: \._pieces, separator: \._separator) var combined
    ///  }
    /// ```
    ///
    /// - Parameters:
    ///   - piecesKeyPath: A ``KeyPath`` to a property of type ``LocalizedStrings``
    ///       that contains the **String** pieces to combine into a single **String**
    ///   - separatorKeyPath:  An optional ``KeyPath`` to a property of type ``LocalizedString``
    ///       that contains the **String** to place between each **String** in the
    ///       pieces array
    public init(pieces piecesKeyPath: KeyPath<Model, _LocalizedArrayProperty<Model, LocalizableString>> & Sendable, separator separatorKeyPath: (KeyPath<Model, _LocalizedProperty<Model, LocalizableString>> & Sendable)? = nil, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableCompoundValue<LocalizableString> {
        self.wrappedValue = Value.stub() // Bound later when propertyName is set
        self.localizationId = .random(length: 10)
        self.bindWrappedValue = { model, _, encoder throws in
            // We cannot expect that the property referenced by the keyPath
            // has already been localized as the order in which the encoder
            // encodes the properties on an instance is undefined.  Thus,
            // we must manually localize the referenced property here and
            // then use the localized value.
            //
            // An alternative mechanism would be to encode the KeyPath,
            // but KeyPath doesn't support Codable. 😡

            let piecesWrapper = model[keyPath: piecesKeyPath]
            let piecesValues: _LocalizedArrayProperty<Model, LocalizableString> = try encoder.localizeArrayPropertyWrapper(
                model: model,
                propertyWrapper: piecesWrapper
            )

            let localizedSeparator: LocalizableString?
            if let separatorKeyPath {
                let separatorWrapper = model[keyPath: separatorKeyPath]
                let localizedSeparatorWrapper: _LocalizedProperty<Model, LocalizableString> = try
                    encoder.localizePropertyWrapper(
                        model: model,
                        propertyWrapper: separatorWrapper
                    )
                localizedSeparator = localizedSeparatorWrapper.wrappedValue
            } else {
                localizedSeparator = nil
            }

            return LocalizableCompoundValue<LocalizableString>(
                pieces: piecesValues.wrappedValue,
                separator: localizedSeparator
            )
        }
        self.vFirst = vFirst ?? .vInitial
        self.vLast = vLast
    }

    /// Initializes the ``LocalizeSubs`` property wrapper
    ///
    ///
    ///
    /// # Example
    ///
    /// ``` swift
    ///  struct MyViewModel: ViewModel {
    ///    @LocalizeSubs(substitutions: \.substitutions) var aLocalizedSubstitution
    ///    private let substitutions: [String: LocalizableString]
    ///
    ///    init() {
    ///      self.substitutions = [
    ///        "aSub": .constant("42")
    ///      ]
    ///    }
    ///  }
    /// ```
    ///
    /// - Parameters:
    ///   - substitutions: A ``KeyPath`` to a property of type ``LocalizedStrings``
    ///       that contains the **String** pieces to combine into a single **String**
    public init(substitutions: KeyPath<Model, [String: some Localizable]> & Sendable, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableSubstitutions {
        self.wrappedValue = Value.stub() // Bound later when propertyName is set
        self.localizationId = .random(length: 10)
        self.bindWrappedValue = { model, propertyName, _ in
            .init(
                baseString: .localized(.init(
                    for: Model.self,
                    parentType: nil,
                    parentKeys: "",
                    propertyName: propertyName,
                    index: nil
                )),
                substitutions: model[keyPath: substitutions]
            )
        }
        self.vFirst = vFirst ?? .vInitial
        self.vLast = vLast
    }

    public init(_ propertyName: String? = nil, substitutions: KeyPath<Model, [String: some Localizable]> & Sendable, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableSubstitutions {
        self.wrappedValue = Value.stub() // Bound later when propertyName is set
        self.localizationId = .random(length: 10)
        self.bindWrappedValue = { model, propertyName, _ in
            .init(
                baseString: .localized(.init(
                    for: Model.self,
                    parentType: nil,
                    parentKeys: "",
                    propertyName: propertyName,
                    index: nil
                )),
                substitutions: model[keyPath: substitutions]
            )
        }
        self.vFirst = vFirst ?? .vInitial
        self.vLast = vLast
    }
}

public extension _LocalizedProperty {
    // MARK: Codable

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        self.localizationId = .random(length: 10)
        self.wrappedValue = try container.decode(Value.self)
        self.bindWrappedValue = nil
        self.vFirst = .current
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bindWrappedValue {
            guard let viewModel = encoder.currentViewModel(for: Model.self) else {
                throw LocalizedPropertyError.internalError(
                    "\(Self.self): Unable to retrieve the current ViewModel for property name lookup"
                )
            }

            guard
                let propertyNames = encoder.propertyNameBindings(),
                let propertyName = propertyNames[localizationId]
            else {
                throw LocalizedPropertyError.internalError("\(Self.self): Unable to resolve the property name")
            }

            let wrappedValue = try bindWrappedValue(
                viewModel,
                propertyName,
                encoder
            )
            try container.encode(wrappedValue)
        } else {
            try container.encode(wrappedValue)
        }
    }
}

public extension _LocalizedProperty {
    // MARK: Stubbable Protocol

    static func stub() -> Self {
        fatalError()
    }
}
