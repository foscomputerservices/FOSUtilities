// YamlLocalizationStore.swift
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

#if canImport(Vapor)
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor
import Yams

public extension Request {
    var locale: Locale? {
        var result: Locale?

        let accepts = headers[HTTPHeaders.Name.acceptLanguage]
        for lang in accepts where result == nil {
            result = Locale(identifier: lang)
        }

        return result
    }

    func requireLocale() throws -> Locale {
        guard let locale else {
            throw YamlStoreError.noLocaleFound
        }

        return locale
    }
}

public extension Application {
    var localizationStore: LocalizationStore? {
        get {
            storage[YamlLocalizationStore.self]
        }
        set {
            storage[YamlLocalizationStore.self] = newValue
        }
    }

    func requireLocalizationStore() throws -> LocalizationStore {
        guard let localizationStore else {
            throw YamlStoreError.noLocalizationStore
        }

        return localizationStore
    }

    /// Initializes the YAML Localization services for the Vapor application
    ///
    /// # Example
    ///
    /// ```swift
    /// app.initYamlLocalization(
    ///     bundle: Bundle.module,
    ///     resourceDirectoryName: "Localization"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - bundle: The application's resource bundle
    ///   - resourceDirectoryName: The name of the directory containing yml files
    func initYamlLocalization(bundle: Bundle, resourceDirectoryName: String) throws {
        let config = try bundle.yamlStoreConfig(
            resourceDirectoryName: resourceDirectoryName
        )
        lifecycle.use(YamlLocalizationInitializer(config: config))
    }
}

private struct YamlLocalizationInitializer: LifecycleHandler {
    let config: YamlStoreConfig

    func willBootAsync(_ app: Application) async throws {
        app.logger.info("Begin: Loading YAML files")

        app.localizationStore = try await YamlStore(config: config)

        app.logger.info("End: Loading YAML files")
    }
}

private struct YamlLocalizationStore: StorageKey {
    typealias Value = LocalizationStore
}
#endif
