// LocalizableTestCase.swift
//
// Created by David Hunt on 9/11/24
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
import Testing

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
///  final class MyTestSuite: LocalizableTestCase {
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
    ///   - sourceLocation: The **SourceLocation** of the caller
    func expectTranslations<VM: ViewModel>(_ viewModelType: VM.Type, locales: Set<Locale>? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        for locale in locales ?? self.locales {
            let vmEncoder = encoder(locale: locale)
            let vm: VM = try viewModelType.stub()
                .toJSON(encoder: vmEncoder)
                .fromJSON()

            let mirror = Mirror(reflecting: vm)
            for child in mirror.children {
                guard let childName = child.label else { continue }

                if let localizable = child.value as? (any Localizable) {
                    #expect(!localizable.isEmpty, "\(childName) -- Missing Translation -- \(locale.identifier)", sourceLocation: sourceLocation)
                }

                if let localizedProperty = child.value as? _LocalizedProperty<VM, LocalizableString> {
                    #expect(localizedProperty.wrappedValue.localizationStatus == .localized, "\(childName) -- Is pending localization", sourceLocation: sourceLocation)
                    #expect(!localizedProperty.wrappedValue.isEmpty, "\(childName) -- Missing Translation -- \(locale.identifier)", sourceLocation: sourceLocation)
                }
            }
        }
    }

    /// Performs tests to ensure that the **ViewModel**s  complete and stable
    ///
    /// This test performs all aspects of automated verification against the **ViewMode**, including:
    ///
    ///   - ``expectCodable(_:encoder:decoder:_:)``
    ///   - ``expectVersionedViewModel(_:version:encoder:decoder:_:fixedTestFilePath:file:line:)-79yr2``
    ///   - ``expectTranslations(viewModel:locales:sourceLocation:)``
    ///
    /// ## Example
    ///
    /// ```swift
    /// try expectFullyTestedViewModel(MyViewModel.self)
    /// ```
    ///
    /// - Parameters:
    ///   - viewModel: A *System.Type* of a type that conforms to **ViewModel**
    ///   - locales: An optional set of **Locale**s to test (default: LocalizableTestCase.locales)
    ///   - sourceLocation: The **SourceLocation** of the caller
    func expectFullViewModelTests(_ viewModelType: (some ViewModel & ViewModel).Type, locales: Set<Locale>? = nil, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let vmEncoder = encoder(locale: locales?.first ?? self.locales.first ?? Self.en)

        try expectCodable(viewModelType, encoder: vmEncoder)
        try expectVersionedViewModel(
            viewModelType,
            encoder: vmEncoder,
            file: sourceLocation._filePath,
            line: sourceLocation.line
        )
        try expectTranslations(viewModelType, locales: locales, sourceLocation: sourceLocation)
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
