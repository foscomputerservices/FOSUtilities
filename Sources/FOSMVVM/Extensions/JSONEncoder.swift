// JSONEncoder.swift
//
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

public extension JSONEncoder {
    /// A ``JSONEncoder`` that encodes ``Localizable`` values
    ///
    /// - Parameters:
    ///   - locale: The **Locale** to use to encode ``Localizable`` values
    ///   - localizationStore: The ``LocalizationStore`` to use to resolve localization
    ///     lookups during encoding
    /// - Returns: A ``JSONEncoder`` that encodes ``Localizable`` values
    static func localizingEncoder(locale: Locale, localizationStore: LocalizationStore) -> JSONEncoder {
        let encoder = LocalizingEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.JSONDateTimeFormatter)
        encoder.userInfo[.localeKey] = locale
        encoder.userInfo[.localizationStoreKey] = localizationStore
        return encoder
    }
}

extension Encoder {
    /// Converts the ``Localizable`` into a **String**
    ///
    /// Even though the ``Localizable`` might be a value type (e.g., int, double, date, etc.)
    /// most often, the localized result should be a **String**.  This is because the
    /// localized version of the *value* contains more than just the value.  It often contains
    /// localized formatting of the value as well to be displayed to the user.
    ///
    /// For example, ``LocalizableInt`` can contain groupings and grouping separators
    /// (e.g., 42,495.00; 42.495,00), or ``LocalizableDate`` might contain localized month names
    /// and localized day/month/year arrangements (e.g., 1-Jul-2024, 7/1/24, 1/7/24), etc.
    ///
    /// If the concrete value of the ``Localizable`` is needed (e.g., int, Date, etc.), typically the
    /// concrete value is available via a property on the ``Localizable``.
    ///
    /// > Typically this form is used for single *value* ``Localizable``s.  Even though it is possible
    /// > to localize a collection through this method, typically the result is not what is desired
    /// > (e.g., a concatenated array of strings, ints or dates).  Usually the *localizeArray* method
    /// > is preferable in these cases.
    ///
    /// - Parameter localizable: The ``Localizable`` to be localized into a **String**
    /// - Returns: The properly localized and formatted version of *localizable* ready to be
    ///   shown to the user.
    func localizeString(_ localizable: some Localizable) throws -> String? {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        return try locale.localize(
            localizable,
            localizationStore: localizationStore
        )
    }

    /// Converts the ``Localizable`` into an **Array** of *Element*s
    ///
    /// - Parameter localizable: The ``Localizable`` to be localized into an **Array**
    /// - Returns: The properly localized and formatted version of *localizable* ready to be
    ///   shown to the user.
    func localizeArray<Element: Localizable>(_ localizable: LocalizableArray<Element>) throws -> [Element]? {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        return locale.array(
            localizable,
            localizationStore: localizationStore
        )
    }

    func localizePropertyWrapper<Model: RetrievablePropertyNames>(model: Model, propertyWrapper: _LocalizedProperty<Model, LocalizableString>) throws -> _LocalizedProperty<Model, LocalizableString> {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        let encoder = JSONEncoder.localizingEncoder(
            locale: locale,
            localizationStore: localizationStore
        )
        encoder.registerModel(model, at: "")
        encoder.propertyNameBindings = model.allPropertyNames()

        do {
            return try propertyWrapper
                .toJSON(encoder: encoder)
                .fromJSON()
        } catch let e {
            throw LocalizerError.processUnknown(error: e)
        }
    }

    func localizeArrayPropertyWrapper<Model: RetrievablePropertyNames>(model: Model, propertyWrapper: _LocalizedArrayProperty<Model, LocalizableString>) throws -> _LocalizedArrayProperty<Model, LocalizableString> {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        let encoder = JSONEncoder.localizingEncoder(locale: locale, localizationStore: localizationStore)
        encoder.registerModel(model, at: "")
        encoder.propertyNameBindings = model.allPropertyNames()

        do {
            return try propertyWrapper
                .toJSON(encoder: encoder)
                .fromJSON()
        } catch let e {
            throw LocalizerError.processUnknown(error: e)
        }
    }
}

/// Unwraps Optional values using Mirror reflection
private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }
    return mirror.children.first?.value
}

/// Registry of models keyed by their coding path for lookup during encoding
private final class ModelRegistry: @unchecked Sendable {
    private var models: [String: Any] = [:]

    func register(_ model: Any, at path: String) {
        models[path] = model
    }

    func model<T>(for type: T.Type, at codingPath: [CodingKey]) -> T? {
        // Convert codingPath to path parts, using intValue for array indices
        var pathParts = codingPath.map { key -> String in
            if let intValue = key.intValue {
                return String(intValue)
            }
            return key.stringValue
        }
        while !pathParts.isEmpty {
            pathParts.removeLast()
            let pathKey = pathParts.joined(separator: ".")
            if let model = models[pathKey] as? T {
                return model
            }
        }
        return models[""] as? T
    }
}

/// Extracts elements from a collection using Mirror (works for any collection type)
private func extractCollectionElements(from value: Any) -> [Any]? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .collection else {
        return nil
    }
    return mirror.children.map(\.value)
}

/// Pre-registers all RetrievablePropertyNames in the object graph
private func registerModels(from value: Any, path: String, into registry: ModelRegistry) {
    if value is (any RetrievablePropertyNames) {
        registry.register(value, at: path)
    }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        guard let label = child.label else { continue }
        let cleanLabel = String(label.trimmingPrefix("_"))
        let childPath = path.isEmpty ? cleanLabel : "\(path).\(cleanLabel)"

        let unwrappedValue = unwrapOptional(child.value)
        let valueToCheck = unwrappedValue ?? child.value

        // Check if it's a collection (array) - use Mirror-based extraction
        if let elements = extractCollectionElements(from: valueToCheck) {
            for (index, element) in elements.enumerated() {
                let elementPath = "\(childPath).\(index)"
                if let unwrappedElement = unwrapOptional(element) {
                    registerModels(from: unwrappedElement, path: elementPath, into: registry)
                } else {
                    registerModels(from: element, path: elementPath, into: registry)
                }
            }
        } else if let unwrapped = unwrappedValue {
            // Not a collection, recurse for nested models
            registerModels(from: unwrapped, path: childPath, into: registry)
        }
    }
}

private final class LocalizingEncoder: JSONEncoder {
    override func encode(_ value: some Encodable) throws -> Data {
        // Save parent state for nested encoding
        let parentPropertyNames = propertyNameBindings

        // Build model registry (only at top level)
        if userInfo[.modelRegistryKey] == nil {
            let registry = ModelRegistry()
            registerModels(from: value, path: "", into: registry)
            userInfo[.modelRegistryKey] = registry
        }

        // Merge property names with existing bindings
        let newPropertyNames = value.allPropertyNames()
        var mergedPropertyNames = propertyNameBindings ?? [:]
        for (key, propValue) in newPropertyNames {
            mergedPropertyNames[key] = propValue
        }
        propertyNameBindings = mergedPropertyNames

        // Encode
        let result: Data = if let viewModel = value as? any ViewModel {
            try encodeViewModel(viewModel)
        } else {
            try super.encode(value)
        }

        // Restore parent state
        propertyNameBindings = parentPropertyNames

        return result
    }

    private func encodeViewModel(_ value: some ViewModel) throws -> Data {
        let config = ViewModelConfiguration()
        return try encode(value, configuration: config)
    }
}

private extension Encodable {
    /// Returns the property names for the RetrievablePropertyNames and all embedded RetrievablePropertyNames
    func allPropertyNames() -> [LocalizableId: String] {
        var result = (self as? RetrievablePropertyNames)?.propertyNames() ?? [:]
        let mirror = Mirror(reflecting: self)

        for child in mirror.children {
            let unwrappedValue = unwrapOptional(child.value)

            if let model = (unwrappedValue ?? child.value) as? RetrievablePropertyNames {
                result.merge(model.allPropertyNames()) { _, new in new }
            } else if let collection = (unwrappedValue ?? child.value) as? (any Collection) {
                for element in collection {
                    let unwrappedElement = unwrapOptional(element)
                    if let model = (unwrappedElement ?? element) as? RetrievablePropertyNames {
                        result.merge(model.allPropertyNames()) { _, new in new }
                    }
                }
            }
        }

        return result
    }
}

// Restating from JSONEncoder
extension LocalizingEncoder: @unchecked Sendable {}

private extension Encoder {
    /// Returns the **Locale** that is to be used during the encoding phase
    ///
    /// This is provided by requesting  a ``JSONEncoder`` using *localizingEncoder()* on ``JSONEncoder``
    var locale: Locale? {
        userInfo[.localeKey] as? Locale
    }

    /// Returns the ``LocalizationStore`` that is to be used during the encoding phase
    ///
    /// This is provided by requesting  a ``JSONEncoder`` using *localizingEncoder()* on ``JSONEncoder``
    var localizationStore: LocalizationStore? {
        userInfo[.localizationStoreKey] as? LocalizationStore
    }
}

extension Encoder {
    // NOTE: The model is used by the substitution localizers
    //    (e.g., LocalizedCompoundString, LocalizeSubs) to access substitution values.
    //    The ModelRegistry approach uses codingPath to find the correct model instance
    //    when there are multiple ViewModels of the same type.

    func currentModel<T>(for type: T.Type) -> T? {
        guard let registry = userInfo[.modelRegistryKey] as? ModelRegistry else {
            return nil
        }
        return registry.model(for: type, at: codingPath)
    }

    var propertyNameBindings: [LocalizableId: String]? { userInfo[.propertyNamesKey] as? [LocalizableId: String] }
}

extension JSONEncoder {
    /// Registers a model at a given path for lookup during encoding
    func registerModel(_ model: Any, at path: String) {
        let registry: ModelRegistry
        if let existing = userInfo[.modelRegistryKey] as? ModelRegistry {
            registry = existing
        } else {
            registry = ModelRegistry()
            userInfo[.modelRegistryKey] = registry
        }
        registry.register(model, at: path)
    }

    var propertyNameBindings: [LocalizableId: String]? {
        get { userInfo[.propertyNamesKey] as? [LocalizableId: String] }
        set { userInfo[.propertyNamesKey] = newValue }
    }
}

extension RetrievablePropertyNames { // Internal for testing
    /// - Returns: [<LocalizableId> : <RetrievablePropertyNames property name>]
    func propertyNames() -> [LocalizableId: String] {
        let mirror = Mirror(reflecting: self)
        let trimChars = CharacterSet(charactersIn: "_")
        var result = [String: String]()

        // Reviewed - dgh - throw should not occur as we are parsing
        //      a constant string.  If the string is not parsable, it
        //      will be caught through testing.
        // swiftlint:disable force_try
        let localizedPropertyTypeName =
            try! String(describing: type(of: _LocalizedProperty<___Model, LocalizableString>.self))
                .replacing(pattern: "___Model.*$", with: "")

        let localizedArrayPropertyTypeName =
            try! String(describing: type(of: _LocalizedArrayProperty<___Model, LocalizableString>.self))
                .replacing(pattern: "___Model.*$", with: "")
        // swiftlint:enable force_try

        for child in mirror.children {
            if let propertyWrapperName = child.label {
                var localizableId: LocalizableId?

                if String(describing: type(of: child.value)).starts(with: localizedPropertyTypeName) {
                    // _LocalizedProperty support
                    if let locProp = child.value as? LocalizedString {
                        localizableId = locProp.localizationId
                    } else if let locProp = child.value as? LocalizedInt {
                        localizableId = locProp.localizationId
                    } else if let locProp = child.value as? LocalizedCompoundString {
                        localizableId = locProp.localizationId
                    } else if let locProp = child.value as? LocalizedSubs {
                        localizableId = locProp.localizationId
                    }
                } else if String(describing: type(of: child.value)).starts(with: localizedArrayPropertyTypeName) {
                    // _LocalizedArrayProperty support
                    if let locArrayProp = child.value as? LocalizedStrings {
                        localizableId = locArrayProp.localizationId
                    }
                }

                if let localizableId {
                    result[localizableId] = propertyWrapperName.trimmingCharacters(in: trimChars)
                }
            }
        }

        return result
    }
}

private extension CodingUserInfoKey {
    static var localeKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCaLe*_")!
    }

    static var localizationStoreKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_sTore*_")!
    }

    /// The properties of the model currently being processed
    static var propertyNamesKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_pRoPerTy_NamEs*_")!
    }

    /// Registry of models by path for looking up the correct model during nested encoding
    static var modelRegistryKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*MoDeL_ReGiStRy*_")!
    }
}

private struct ___Model: RetrievablePropertyNames {
    func propertyNames() -> [LocalizableId: String] { [:] }
}
