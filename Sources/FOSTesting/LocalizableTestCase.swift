// LocalizableTestCase.swift
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
import FOSMVVM
import Foundation

/// Extensions to test **Localizable** resources
///
/// # Usage
///
/// Test suites that want to use the **Localizable** infrastructure can
/// inherit from this protocol and localization will be available.
///
///  ## Example
///
///  ```swift
///  @Suite("My Test Suite", .serialized)
///  struct MyTestSuite: LocalizableTestCase {
///
///      let locStore: LocalizationStore
///      var locales: Set<Locale> {[Self.en, Self.es]}
///      init() async throws {
///          self.locStore = try await Self.loadLocalizationStore(bundle: .module)
///      }
///  }
///  ```
public protocol LocalizableTestCase: Sendable {
    var locStore: LocalizationStore { get }
    var locales: Set<Locale> { get }
}

// TODO: Move the initialization to a macro

public extension LocalizableTestCase {
    /// Loads a **LocalizationStore** with the localizations in *resourceDirectoryName*
    ///
    /// - Parameter resourceDirectoryName: The name of a resource directory
    ///    in the application's bundle (default: Localizations)
    /// - Parameter bundle: The *Bundle* to use to load the YAML store
    static func loadLocalizationStore(bundle: Bundle, resourceDirectoryName: String = "Resources") async throws -> LocalizationStore {
        try await bundle.yamlLocalization(
            resourceDirectoryName: resourceDirectoryName
        )
    }

    /// Returns **JSONEncoder** that is configured to perform localization during encoding
    func encoder(locale: Locale = Self.en) -> JSONEncoder {
        JSONEncoder.localizingEncoder(
            locale: locale,
            localizationStore: locStore
        )
    }

    /// Tests that the ViewModel has translations for all localized properties across all locales
    ///
    /// - Parameters:
    ///   - viewModel: A *System.Type* of a type that conforms to **ViewModel**
    ///   - locales: An optional set of **Locale**s to test (default: LocalizableTestCase.locales)
    func expectTranslations<Model>(_ viewModelType: Model.Type, locales: Set<Locale>? = nil) throws where Model: RetrievablePropertyNames & Stubbable {
        for locale in locales ?? self.locales {
            let encoder = encoder(locale: locale)
            let model: Model = try viewModelType.stub()
                .toJSON(encoder: encoder)
                .fromJSON()

            let mirror = Mirror(reflecting: model)
            for child in mirror.children {
                guard let childName = child.label else { continue }

                if let localizable = child.value as? (any Localizable) {
                    guard !localizable.isEmpty else {
                        throw FOSLocalizableError.error("\(childName) -- Missing Translation -- \(locale.identifier)")
                    }
                }

                if let localizedProperty = child.value as? _LocalizedProperty<Model, LocalizableString> {
                    guard localizedProperty.wrappedValue.localizationStatus == .localized else {
                        throw FOSLocalizableError.error("\(childName) -- Is pending localization")
                    }

                    guard !localizedProperty.wrappedValue.isEmpty else {
                        throw FOSLocalizableError.error("\(childName) -- Missing Translation -- \(locale.identifier)")
                    }
                }
            }
        }
    }

    func expectTranslations<L>(_ localizable: L, locales: Set<Locale>? = nil) throws where L: Localizable {
        for locale in locales ?? self.locales {
            let encoder = encoder(locale: locale)
            let localized: L = try localizable
                .toJSON(encoder: encoder)
                .fromJSON()

            guard localized.localizationStatus == .localized else {
                throw FOSLocalizableError.error("\(localizable) -- Is pending localization")
            }
            guard !localized.isEmpty else {
                throw FOSLocalizableError.error("\(localizable) -- Missing Translation -- \(locale.identifier)")
            }
        }
    }

    /// Performs tests to ensure that the **ViewModel**s  complete and stable
    ///
    /// This test performs all aspects of automated verification against the **ViewMode**, including:
    ///
    ///   - ``expectCodable(_:encoder:decoder:_:)``
    ///   - ``expectVersionedViewModel(_:version:encoder:decoder:_:fixedTestFilePath:file:line:)-79yr2``
    ///   - ``expectTranslations(:locales:)``
    ///
    /// ## Example
    ///
    /// ```swift
    /// try expectFullyTestedViewModel(MyViewModel.self)
    /// ```
    ///
    /// - Parameters:
    ///   - viewModelType: A *System.Type* of a type that conforms to **ViewModel**
    ///   - locales: An optional set of **Locale**s to test (default: LocalizableTestCase.locales)
    func expectFullViewModelTests(_ viewModelType: (some ViewModel & ViewModel).Type, locales: Set<Locale>? = nil) throws {
        let vmEncoder = encoder(locale: locales?.first ?? self.locales.first ?? Self.en)

        try expectCodable(viewModelType, encoder: vmEncoder)
        try expectVersionedViewModel(
            viewModelType,
            encoder: vmEncoder
        )
        try expectTranslations(viewModelType, locales: locales)
    }

    /// Performs tests to ensure that the **FieldValidationModel**s  complete and stable
    ///
    /// This test performs all aspects of automated verification against the **ViewMode**, including:
    ///
    ///   - ``expectCodable(_:encoder:decoder:_:)``
    ///   - ``expectTranslations(:locales:)``
    ///
    /// ## Example
    ///
    /// ```swift
    /// try expectFullFieldValidationModelTests(MyFieldModel.self)
    /// ```
    ///
    /// - Parameters:
    ///   - fieldValidationModelType: A *System.Type* of a type that conforms to **FieldValidationModel**
    ///   - locales: An optional set of **Locale**s to test (default: LocalizableTestCase.locales)
    func expectFullFieldValidationModelTests(_ fieldValidationModelType: (some FieldValidationModel & FieldValidationModel).Type, locales: Set<Locale>? = nil) throws {
        let encoder = encoder(locale: locales?.first ?? self.locales.first ?? Self.en)

        try expectCodable(fieldValidationModelType, encoder: encoder)
        try expectTranslations(fieldValidationModelType, locales: locales)
    }

    /// Performs tests to ensure that the **FormField** is complete and stable
    ///
    /// - Parameters:
    ///   - formField: A *FormField* instance to be tested
    ///   - locales: An optional set of **Locale**s to test (default: LocalizableTestCase.locales)
    func expectFullFormFieldTests(_ formField: FormField<some Codable & Hashable>, locales: Set<Locale>? = nil) throws {
        try expectTranslations(formField.title, locales: locales)
        if let placeholder = formField.placeholder {
            try expectTranslations(placeholder, locales: locales)
        }
    }

    static var en: Locale {
        Locale(identifier: "en")
    }

    var en: Locale {
        Self.en
    }

    static var enUS: Locale {
        Locale(identifier: "en-US")
    }

    var enUS: Locale {
        Self.enUS
    }

    static var enGB: Locale {
        Locale(identifier: "en-GB")
    }

    var enGB: Locale {
        Self.enGB
    }

    static var es: Locale {
        Locale(identifier: "es")
    }

    var es: Locale {
        Self.es
    }
}

public enum FOSLocalizableError: Error, CustomDebugStringConvertible {
    case error(_ message: String)

    public var debugDescription: String {
        switch self {
        case .error(let message): "FOSLocalizableError: \(message)"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}
