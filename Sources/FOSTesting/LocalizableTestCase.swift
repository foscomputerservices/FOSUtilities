// LocalizableTestCase.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Services, LLC
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
///          self.locStore = try await Self.loadLocalizationStore()
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
    static func loadLocalizationStore(bundle: Bundle, resourceDirectoryName: String = "Resources") async throws -> LocalizationStore {
        try await bundle.yamlLocalization(
            resourceDirectoryName: resourceDirectoryName
        )
    }

    func encoder(locale: Locale? = nil) -> JSONEncoder {
        JSONEncoder.localizingEncoder(
            locale: locale ?? en,
            localizationStore: locStore
        )
    }

    func expectTranslations<VM: ViewModel>(viewModel: VM.Type, locales: Set<Locale>? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        for locale in locales ?? self.locales {
            let vmEncoder = JSONEncoder.localizingEncoder(
                locale: locale,
                localizationStore: locStore
            )
            let vm: VM = try viewModel.stub()
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