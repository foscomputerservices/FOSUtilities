// JSONEncoder.swift
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

public extension JSONEncoder {
    /// A ``JSONEncoder`` that encodes ``Localizable`` values
    ///
    /// - Parameters:
    ///   - locale: The **Locale** to use to encode ``Localizable`` values
    ///   - localizationStore: The ``LocalizationStore`` to use to resolve localization
    ///     lookups during encoding
    /// - Returns: A ``JSONEncoder`` that encodes ``Localizable`` values
    static func localizingEncoder(locale: Locale, localizationStore: LocalizationStore) -> JSONEncoder {
        let encoder = ViewModelEncoder()
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
    /// formatting of the value as well to be displayed to the user.
    ///
    /// For example, ``LocalizableInt`` can contain groupings and grouping separators
    /// (e.g., 42,495.00), or ``LocalizableDate`` might contain localized month names
    /// (e.g., 1-Jul-2024), etc.
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

    func localizeArray<Element: Localizable>(_ localizable: LocalizableArray<Element>) throws -> [Element]? {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        return locale.array(
            localizable,
            localizationStore: localizationStore
        )
    }

    func localizePropertyWrapper<Model: ViewModel>(model: Model, propertyWrapper: _LocalizedProperty<Model, LocalizableString>) throws -> _LocalizedProperty<Model, LocalizableString> {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        let encoder = JSONEncoder.localizingEncoder(locale: locale, localizationStore: localizationStore)
        encoder.userInfo[.currentViewModelKey] = model
        encoder.userInfo[.propertyNamesKey] = model.propertyNames()

        do {
            return try propertyWrapper
                .toJSON(encoder: encoder)
                .fromJSON()
        } catch let e {
            throw LocalizerError.processUnknown(error: e)
        }
    }

    func localizeArrayPropertyWrapper<Model: ViewModel>(model: Model, propertyWrapper: _LocalizedArrayProperty<Model, LocalizableString>) throws -> _LocalizedArrayProperty<Model, LocalizableString> {
        guard let locale, let localizationStore else {
            throw LocalizerError.localizationStoreMissing
        }

        let encoder = JSONEncoder.localizingEncoder(locale: locale, localizationStore: localizationStore)
        encoder.userInfo[.currentViewModelKey] = model
        encoder.userInfo[.propertyNamesKey] = model.propertyNames()

        do {
            return try propertyWrapper
                .toJSON(encoder: encoder)
                .fromJSON()
        } catch let e {
            throw LocalizerError.processUnknown(error: e)
        }
    }
}

private final class ViewModelEncoder: JSONEncoder {
    override func encode(_ value: some Encodable) throws -> Data {
        let parentViewModel = userInfo[.currentViewModelKey]
        let parentPropertyNames = userInfo[.propertyNamesKey]

        if let viewModel = value as? (any ViewModel) {
            userInfo[.propertyNamesKey] = viewModel.propertyNames()
            userInfo[.currentViewModelKey] = viewModel
        }

        let result = try super.encode(value)
        userInfo[.currentViewModelKey] = parentViewModel
        userInfo[.propertyNamesKey] = parentPropertyNames

        return result
    }
}

// Restating from JSONEncoder
extension ViewModelEncoder: @unchecked Sendable {}

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
    func currentViewModel<T: ViewModel>(for type: T.Type) -> T? {
        userInfo[.currentViewModelKey] as? T
    }

    func propertyNameBindings() -> [LocalizableId: String]? {
        userInfo[.propertyNamesKey] as? [LocalizableId: String]
    }
}

extension ViewModel { // Internal for testing
    /// - Returns: [<LocalizableId> : <ViewModel property name>]
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
                    } else if let locProp = child.value as? LocalizeInt {
                        localizableId = locProp.localizationId
                    } else if let locProp = child.value as? LocalizeCompoundString {
                        localizableId = locProp.localizationId
                    } else if let locProp = child.value as? LocalizeSubs {
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

extension KeyPath {
    func propertyName(on instance: Any) -> String? {
        let instance = Mirror(reflecting: instance)
        for child in instance.children {
            if let label = child.label, let value = child.value as? KeyPath<Root, Value>, value == self {
                return label
            }
        }
        return nil
    }
}

#if canImport(Vapor)
import Vapor

public extension Request {
    var viewModelEncoder: JSONEncoder {
        get throws {
            try JSONEncoder.localizingEncoder(
                locale: requireLocale(),
                localizationStore: application.requireLocalizationStore()
            )
        }
    }
}
#endif

private extension CodingUserInfoKey {
    static var localeKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCaLe*_")!
    }

    static var localizationStoreKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_sTore*_")!
    }

    static var propertyNamesKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_pRoPerTy_NamEs*_")!
    }

    static var currentViewModelKey: CodingUserInfoKey {
        CodingUserInfoKey(rawValue: "_*LoCalIzAtIon_curRenT_vIew_MOdel*_")!
    }
}

private struct ___Model: ViewModel {
    var vmId: ViewModelId = .init()

    static func stub() -> ___Model {
        .init()
    }
}
