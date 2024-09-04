// LocalizableTestCase.swift
//
// Created by David Hunt on 6/23/24
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
@testable import FOSMVVM
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
///  final class MyTestSuite: LocalizableTestCase {
///
///      let locStore: LocalizationStore
///      init() async throws {
///          self.locStore = try await Self.loadLocalizationStore()
///      }
///  }
///  ```
protocol LocalizableTestCase: Sendable {
    var locStore: LocalizationStore { get }
}

// TODO: Move the initialization to a macro

extension LocalizableTestCase {
    /// Loads a **LocalizationStore** with the localizations in *resourceDirectoryName*
    ///
    /// - Parameter resourceDirectoryName: The name of a resource directory
    ///    in the application's bundle (default: TestYAML)
    static func loadLocalizationStore(resourceDirectoryName: String = "TestYAML") async throws -> LocalizationStore {
        try await Bundle.module.yamlLocalization(
            resourceDirectoryName: resourceDirectoryName
        )
    }

    func encoder(locale: Locale? = nil) -> JSONEncoder {
        JSONEncoder.localizingEncoder(
            locale: locale ?? en,
            localizationStore: locStore
        )
    }

    var en: Locale {
        Locale(identifier: "en")
    }

    var enUS: Locale {
        Locale(identifier: "en-US")
    }

    var enGB: Locale {
        Locale(identifier: "en-GB")
    }

    var es: Locale {
        Locale(identifier: "es")
    }
}
