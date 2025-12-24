// MVVMEnvironment.swift
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
#if canImport(SwiftUI)
import SwiftUI
#else
import Observation
#endif

/// ``MVVMEnvironment`` provides configuration information to to the
/// SwiftUI MVVM implementation
///
/// An ``MVVMEnvironment`` instance should be created and registered
/// in the [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment) at application startup.
///
/// ## Example
///
/// ```swift
///  @main
///  struct MyApp: App {
///      var body: some Scene {
///          WindowGroup {
///              Text("Hello World!")
///          }
///          .environment(
///              MVVMEnvironment(
///                  currentVersion: .currentApplicationVersion,
///                  appBundle: Bundle.main,
///                  deploymentURLs: [
///                     .production: URL(string: "https://api.mywebserver.com")!,
///                     .staging: URL(string: "https://staging-api.mywebserver.com")!,
///                     .debug: URL(string: "http://localhost:8080")!
///                   ]
///              ) {
///                 AnyView { Text("Loading...") }
///              }
///          )
///      }
///  }
/// ```
@Observable
public final class MVVMEnvironment: @unchecked Sendable {
    // NOTE: This is an @Observable final class only because SwiftUI's
    //       Environment implementation requires this; otherwise it
    //       could be a simple struct.

    /// A set of base URLs that define where the server resources can be found
    public struct URLPackage: Sendable {
        /// The base URL of the web service
        public let serverBaseURL: URL

        /// The base  URL for images
        public let resourcesBaseURL: URL

        /// Initializes the ``MVVMEnvironment``
        ///
        /// - Parameters:
        ///   - serverBaseURL: The base URL of the web service used to retrieve ``ViewModel``s
        ///   - resourcesBaseURL: The base URL of the web service used to retrieve images (default: ``serverBaseURL``)
        public init(serverBaseURL: URL, resourcesBaseURL: URL? = nil) {
            self.serverBaseURL = serverBaseURL
            self.resourcesBaseURL = resourcesBaseURL ?? serverBaseURL
        }
    }

    public let resourceBundles: [Bundle]
    public let resourceDirectoryName: String?
    private let localizationStore: LocalizationStore?

    /// A configuration of server URLs for each given ``Deployment``
    public let deploymentURLs: [Deployment: URLPackage]

    /// A dictionary of values to populate the *URLRequest*'s HTTPHeaderFields
    public let requestHeaders: [String: String]

    /// A function that is called when there is an error processing a ``ServerRequest``
    public let requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)?

    #if canImport(SwiftUI)
    typealias ViewFactory = (Data) throws -> AnyView

    #if DEBUG
    var registeredTestTypes: [String: ViewFactory] = [:]
    #endif

    @MainActor public func registerTestView<V: ViewModelView>(_ type: V.Type) {
        #if DEBUG
        registeredTestTypes[String(describing: V.VM.self)] = { data in
            try AnyView(V(viewModel: data.fromJSON()))
        }
        #endif
    }

    /// A view to be presented when the ``ViewModel`` is being requested
    /// from the web service
    ///
    /// > Note: A non-localized "Loading..." is presented if no view is provided
    public let loadingView: @Sendable () -> AnyView
    #endif

    /// A ``LocalizationStore`` instance that provides access to the localization data
    ///
    /// > This is only provided/necessary for applications that created ``ViewModel``s
    /// > in the application as opposed on the server.
    @MainActor
    public var clientLocalizationStore: LocalizationStore? {
        get throws {
            if let store = _clientLocalizationStore {
                return store
            }

            let locStore = try resolveClientLocalizationStore()
            _clientLocalizationStore = locStore
            return locStore
        }
    }

    /// Returns a ``LocalizationStore`` instance that provides access to the localization data
    ///
    /// > This is only provided/necessary for applications that created ``ViewModel``s
    /// > in the application as opposed on the server.
    ///
    /// > The result of this function is **uncached** as opposed to ``clientLocalizationStore``
    public func resolveClientLocalizationStore() throws -> LocalizationStore {
        let locStore: LocalizationStore = if let localizationStore {
            localizationStore
        } else {
            try resourceBundles.yamlLocalization(
                resourceDirectoryName: resourceDirectoryName ?? ""
            )
        }
        return locStore
    }

    @ObservationIgnored @MainActor
    private var _clientLocalizationStore: LocalizationStore?

    /// Returns the URL for the web server that provides ``ViewModel``s for the current ``Deployment``
    @MainActor
    public var serverBaseURL: URL {
        get async throws {
            let deployment = await Deployment.current
            guard let result = deploymentURLs[deployment] else {
                throw MVVMEnvironmentError.missingDeploymentConfiguration(deployment: deployment)
            }

            return result.serverBaseURL
        }
    }

    /// Returns the URL for the web server that provides images and resources for the current ``Deployment``
    @MainActor
    public var resourcesBaseURL: URL {
        get async throws {
            let deployment = await Deployment.current
            guard let result = deploymentURLs[deployment] else {
                throw MVVMEnvironmentError.missingDeploymentConfiguration(deployment: deployment)
            }

            return result.resourcesBaseURL
        }
    }

    #if canImport(SwiftUI)
    /// Initializes the ``MVVMEnvironment`` for SwiftUI
    ///
    /// > If *currentVersion* is not specified, *SystemVersion.currentVersion* is set to *appBundle.appleOSVersion*, which is loaded from the xcodeproj.
    /// > See also: <doc:Versioning>
    ///
    /// - Parameters:
    ///   - currentVersion: The current SystemVersion of the application (default: see note)
    ///   - appBundle: The application's *Bundle* (e.g. *Bundle.main*)
    ///   - resourceBundles: All *Bundle*s that contain YAML resources (default: appBundle)
    ///   - resourceDirectoryName: The directory name that contains the resources (default: nil).  Only needed
    ///          if the client application is hosting the YAML files.
    ///   - requestHeaders: A set of HTTP header fields for the URLRequest
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil)
    ///   - loadingView: A function that produces a View that will be displayed while the ``ViewModel``
    ///     is being retrieved (default: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview))
    @MainActor public init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        deploymentURLs: [Deployment: URLPackage],
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil,
        loadingView: (@Sendable () -> AnyView)? = nil
    ) {
        self.localizationStore = nil
        self.resourceBundles = resourceBundles ?? [appBundle]
        self.resourceDirectoryName = resourceDirectoryName
        self.requestHeaders = requestHeaders
        self.deploymentURLs = deploymentURLs
        self.requestErrorHandler = requestErrorHandler
        self.loadingView = loadingView ?? { AnyView(DefaultLoadingView()) }

        let currentVersion = currentVersion ?? (try? appBundle.appleOSVersion) ?? SystemVersion.current
        Self.ensureVersionsCompatible(currentVersion: currentVersion, appBundle: appBundle)
        SystemVersion.setCurrentVersion(currentVersion)
    }

    /// Initializes the ``MVVMEnvironment`` for SwiftUI
    ///
    /// This convenience initializer uses each deployment URL for both the *serverBaseURL* and the *resourcesBaseURL*.
    ///
    /// > If *currentVersion* is not specified, *SystemVersion.currentVersion* is set to *appBundle.appleOSVersion*, which is loaded from the xcodeproj.
    /// > See also: <doc:Versioning>
    ///
    /// - Parameters:
    ///   - currentVersion: The current SystemVersion of the application (default: see note)
    ///   - appBundle: The applications *Bundle* (e.g. *Bundle.main*)
    ///   - resourceBundles: All *Bundle*s that contain YAML resources (default: appBundle)
    ///   - resourceDirectoryName: The directory name that contains the resources (default: nil).  Only needed
    ///          if the client application is hosting the YAML files.
    ///   - requestHeaders: A set of HTTP header fields for the URLRequest
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil)
    ///   - loadingView: A function that produces a View that will be displayed while the ``ViewModel``
    ///     is being retrieved (default: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview))
    @MainActor public convenience init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        deploymentURLs: [Deployment: URL],
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil,
        loadingView: (@Sendable () -> AnyView)? = nil
    ) {
        self.init(
            currentVersion: currentVersion,
            appBundle: appBundle,
            resourceBundles: resourceBundles,
            resourceDirectoryName: resourceDirectoryName,
            requestHeaders: requestHeaders,
            deploymentURLs: deploymentURLs.reduce([Deployment: URLPackage]()) { result, pair in
                var result = result
                let (deployment, url) = pair

                result[deployment] = .init(serverBaseURL: url, resourcesBaseURL: url)
                return result
            },
            requestErrorHandler: requestErrorHandler,
            loadingView: loadingView
        )
    }

    /// Initializes ``MVVMEnvironment`` for SwiftUI previews
    ///
    /// > This overload does **NOT** check the application's version as it is not necessary for previews
    @MainActor init(
        localizationStore: LocalizationStore,
        deploymentURLs: [Deployment: URLPackage],
        loadingView: (
            @Sendable () -> AnyView
        )? = nil
    ) {
        self.localizationStore = localizationStore
        self.resourceBundles = []
        self.resourceDirectoryName = nil
        self.requestHeaders = [:]
        self.deploymentURLs = deploymentURLs
        self.requestErrorHandler = nil
        self.loadingView = loadingView ?? { AnyView(DefaultLoadingView()) }

        SystemVersion.setCurrentVersion(SystemVersion.current)
    }
    #endif

    /// Initializes the ``MVVMEnvironment`` for non-SwiftUI Applications
    ///
    /// > If *currentVersion* is not specified, *SystemVersion.currentVersion* is set to *appBundle.appleOSVersion*, which is loaded from the xcodeproj.
    /// > See also: <doc:Versioning>
    ///
    /// - Parameters:
    ///   - currentVersion: The current SystemVersion of the application (default: see note)
    ///   - appBundle: The application's *Bundle* (e.g. *Bundle.main*)
    ///   - resourceBundles: All *Bundle*s that contain YAML resources (default: appBundle)
    ///   - resourceDirectoryName: The directory name that contains the resources (default: nil).  Only needed
    ///          if the client application is hosting the YAML files.
    ///   - requestHeaders: A set of HTTP header fields for the URLRequest
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil)
    @MainActor public init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        deploymentURLs: [Deployment: URLPackage],
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil
    ) {
        self.localizationStore = nil
        self.resourceBundles = resourceBundles ?? [appBundle]
        self.resourceDirectoryName = resourceDirectoryName
        self.requestHeaders = requestHeaders
        self.deploymentURLs = deploymentURLs
        self.requestErrorHandler = requestErrorHandler

        
        #if canImport(SwiftUI)
        self.loadingView = { AnyView(DefaultLoadingView()) }
        let currentVersion = currentVersion ?? (try? appBundle.appleOSVersion) ?? SystemVersion.current
        SystemVersion.setCurrentVersion(currentVersion)
        #else
        let currentVersion = currentVersion ?? SystemVersion.current
        SystemVersion.setCurrentVersion(currentVersion)
        #endif

    }

    /// Initializes the ``MVVMEnvironment`` for non-SwiftUI Applications
    ///
    /// This convenience initializer uses each deployment URL for both the *serverBaseURL* and the *resourcesBaseURL*.
    ///
    /// > If *currentVersion* is not specified, *SystemVersion.currentVersion* is set to *appBundle.appleOSVersion*, which is loaded from the xcodeproj.
    /// > See also: <doc:Versioning>
    ///
    /// - Parameters:
    ///   - currentVersion: The current SystemVersion of the application (default: see note)
    ///   - appBundle: The applications *Bundle* (e.g. *Bundle.main*)
    ///   - resourceBundles: All *Bundle*s that contain YAML resources (default: appBundle)
    ///   - resourceDirectoryName: The directory name that contains the resources (default: nil).  Only needed
    ///          if the client application is hosting the YAML files.
    ///   - requestHeaders: A set of HTTP header fields for the URLRequest
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil)
    @MainActor public convenience init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        deploymentURLs: [Deployment: URL],
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil
    ) {
        self.init(
            currentVersion: currentVersion,
            appBundle: appBundle,
            resourceBundles: resourceBundles,
            resourceDirectoryName: resourceDirectoryName,
            requestHeaders: requestHeaders,
            deploymentURLs: deploymentURLs.reduce([Deployment: URLPackage]()) { result, pair in
                var result = result
                let (deployment, url) = pair

                result[deployment] = .init(serverBaseURL: url, resourcesBaseURL: url)
                return result
            },
            requestErrorHandler: requestErrorHandler
        )
    }
}

public enum MVVMEnvironmentError: Error, CustomDebugStringConvertible {
    case missingDeploymentConfiguration(deployment: Deployment)

    public var debugDescription: String {
        switch self {
        case .missingDeploymentConfiguration(deployment: let deployment):
            "debugDescription: Missing deployment configuration for \(deployment)"
        }
    }
}

private extension MVVMEnvironment {
    static func ensureVersionsCompatible(currentVersion: SystemVersion, appBundle: Bundle) {
        #if canImport(SwiftUI)
        do {
            let bundleVersion = try appBundle.appleOSVersion

            guard bundleVersion.isCompatible(with: currentVersion) else {
                fatalError("The app bundle version (\(bundleVersion)) does not match the current system version (\(currentVersion)). Please update your app bundle version to \(currentVersion) in the project settings.")
            }
        } catch let error as SystemVersionError {
            fatalError("Unable to retrieve SystemVersion from Bundle: \(error.localizedDescription)")
        } catch let e {
            fatalError("Error retrieving SystemVersion: \(e.localizedDescription)")
        }
        #endif
    }
}

#if canImport(SwiftUI)

private struct DefaultLoadingView: View {
    var body: some View {
        ProgressView()
    }
}

#endif
