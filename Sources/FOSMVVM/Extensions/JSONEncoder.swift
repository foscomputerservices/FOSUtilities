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
        encoder.userInfo[.currentModelKey] = model
        encoder.userInfo[.propertyNamesKey] = model.allPropertyNames()

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
        encoder.userInfo[.currentModelKey] = model
        encoder.userInfo[.propertyNamesKey] = model.allPropertyNames()

        do {
            return try propertyWrapper
                .toJSON(encoder: encoder)
                .fromJSON()
        } catch let e {
            throw LocalizerError.processUnknown(error: e)
        }
    }
}

private final class LocalizingEncoder: JSONEncoder {
    override func encode(_ value: some Encodable) throws -> Data {
        let parentModel = userInfo[.currentModelKey]
        let parentPropertyNames = userInfo[.propertyNamesKey]

        let newPropertyNames: [LocalizableId: String]
        if let model = value as? (any RetrievablePropertyNames) {
            newPropertyNames = model.allPropertyNames()
            userInfo[.currentModelKey] = model
        } else {
            newPropertyNames = value.allPropertyNames()
        }
        var propertyNames = (userInfo[.propertyNamesKey] as? [LocalizableId: String]) ?? [:]
        for (key, value) in newPropertyNames {
            propertyNames[key] = value
        }
        userInfo[.propertyNamesKey] = propertyNames

        let result = try super.encode(value)
        userInfo[.currentModelKey] = parentModel
        userInfo[.propertyNamesKey] = parentPropertyNames

        return result
    }
}

private extension Encodable {
    /// Returns the property names for the RetrievablePropertyNames and all embedded RetrievablePropertyNames
    func allPropertyNames() -> [LocalizableId: String] {
        var result = (self as? RetrievablePropertyNames)?.propertyNames() ?? [:]

        let mirror = Mirror(reflecting: self)

        for child in mirror.children {
            if let model = child.value as? RetrievablePropertyNames {
                for (key, value) in model.allPropertyNames() {
                    result[key] = value
                }
            } else if let collection = child.value as? (any Collection) {
                for child in collection {
                    if let model = child as? RetrievablePropertyNames {
                        for (key, value) in model.allPropertyNames() {
                            result[key] = value
                        }
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
    // NOTE: Passing the model through the encoder has been known to cause problems
    //    in client UnitTests.  The exact cause is T.B.D.  However, with more work
    //    in the macros, it might be possible to completely eliminate this need.
    //    Right now, the model is only used by the substitution localizers
    //    (e.g., LocalizedCompoundString, LocalizeSubs).

    func currentModel<T>(for type: T.Type) -> T? {
        userInfo[.currentModelKey] as? T
    }

    func propertyNameBindings() -> [LocalizableId: String]? {
        userInfo[.propertyNamesKey] as? [LocalizableId: String]
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

extension CodingUserInfoKey { // Internal for testing
    static var localeKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCaLe*_")!
    }

    static var localizationStoreKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_sTore*_")!
    }

    static var propertyNamesKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_pRoPerTy_NamEs*_")!
    }

    static var currentModelKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_curRenT_MOdel*_")!
    }
}

private struct ___Model: RetrievablePropertyNames {
    func propertyNames() -> [LocalizableId: String] { [:] }
}

