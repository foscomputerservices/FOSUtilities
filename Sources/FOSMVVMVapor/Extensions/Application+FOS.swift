// Application+FOS.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Vapor
import Yams

public extension Application {
    /// Provides access to the *LocalizationStore* that is attached to the
    /// Vapor Application instance.
    var localizationStore: LocalizationStore? {
        get {
            storage[YamlLocalizationStore.self]
        }
        set {
            storage[YamlLocalizationStore.self] = newValue
        }
    }

    /// Retrieves the *LocalizationStore* from the Vapor Application
    ///
    /// - Throws: *YamlStoreError.noLocalizationStore* if one has not been attached
    func requireLocalizationStore() throws -> LocalizationStore {
        guard let localizationStore else {
            throw YamlStoreError.noLocalizationStore
        }

        return localizationStore
    }

    /// Initializes the YAML Localization services for the Vapor application
    ///
    /// ## Example
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

    // MARK: MVVMEnvironment

    var mvvmEnvironment: MVVMEnvironment? {
        get { storage[MVVMEnvironmentStore.self] }
        set { storage[MVVMEnvironmentStore.self] = newValue }
    }

    fileprivate var _serverBaseURL: URL? {
        get { storage[ServerBaseURLStore.self] }
        set { storage[ServerBaseURLStore.self] = newValue }
    }

    var serverBaseURL: URL {
        guard let _serverBaseURL else {
            fatalError("Attempted to access MVVMEnvironment/serverBaseURL before it was initialized")
        }

        return _serverBaseURL
    }

    func initMVVMEnvironment(_ mvvmEnvironment: MVVMEnvironment) async throws {
        lifecycle.use(MVVMEnvironmentInitializer(
            mvvmEnvironment: mvvmEnvironment,
            serverBaseURL: try await mvvmEnvironment.serverBaseURL
        ))
    }
}

private struct YamlLocalizationInitializer: LifecycleHandler {
    let config: YamlStoreConfig

    fileprivate func willBootAsync(_ app: Application) async throws {
        app.logger.info("Begin: Loading YAML files")

        app.localizationStore = try YamlStore(config: config)

        app.logger.info("End: Loading YAML files")
    }
}

private struct YamlLocalizationStore: StorageKey {
    typealias Value = LocalizationStore
}

private struct MVVMEnvironmentInitializer: LifecycleHandler {
    let mvvmEnvironment: MVVMEnvironment
    let serverBaseURL: URL

    fileprivate func willBootAsync(_ app: Application) async throws {
        app.logger.info("MVVM Environment WebService: \(serverBaseURL.absoluteString)")
        app.mvvmEnvironment = mvvmEnvironment
        app._serverBaseURL = try await mvvmEnvironment.serverBaseURL
    }
}

private struct MVVMEnvironmentStore: StorageKey {
    typealias Value = MVVMEnvironment
}

private struct ServerBaseURLStore: StorageKey {
    typealias Value = URL
}
