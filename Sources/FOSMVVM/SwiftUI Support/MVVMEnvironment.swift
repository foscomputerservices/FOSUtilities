// MVVMEnvironment.swift
//
// Created by David Hunt on 1/2/25
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
#if canImport(SwiftUI)
import Foundation
import SwiftUI

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
public final class MVVMEnvironment: Sendable {
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

    /// A configuration of server URLs for each given ``Deployment``
    public let deploymentURLs: [Deployment: URLPackage]

    /// A view to be presented when the ``ViewModel`` is being requested
    /// from the web service
    ///
    /// > Note: A non-localized "Loading..." is presented if no view is provided
    public let loadingView: @Sendable () -> AnyView

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

    /// Initializes the ``MVVMEnvironment``
    ///
    /// > If *currentVersion* is not specified, *SystemVersion.currentVersion* is set to *appBundle.appleOSVersion*, which is loaded from the xcodeproj.
    /// > See also: <doc:Versioning>
    ///
    /// - Parameters:
    ///   - currentVersion: The current SystemVersion of the application (default: see note)
    ///   - appBundle: The applications *Bundle* (e.g. *Bundle.main*)
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - loadingView: A function that produces a View that will be displayed while the ``ViewModel``
    ///     is being retrieved (default: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview))
    public init(currentVersion: SystemVersion? = nil, appBundle: Bundle, deploymentURLs: [Deployment: URLPackage], loadingView: (@Sendable () -> AnyView)? = nil) {
        self.deploymentURLs = deploymentURLs
        self.loadingView = loadingView ?? { AnyView(DefaultLoadingView()) }

        let currentVersion = currentVersion ?? (try? appBundle.appleOSVersion) ?? SystemVersion.current
        Self.ensureVersionsCompatible(currentVersion: currentVersion, appBundle: appBundle)
        SystemVersion.setCurrentVersion(currentVersion)
    }

    /// Initializes the ``MVVMEnvironment``
    ///
    /// This convenience initializer uses each deployment URL for both the *serverBaseURL* and the *resourcesBaseURL*.
    ///
    /// - Parameters:
    ///   - currentVersion: The current SystemVersion of the application (default: see note)
    ///   - appBundle: The applications *Bundle* (e.g. *Bundle.main*)
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - loadingView: A function that produces a View that will be displayed while the ``ViewModel``
    ///     is being retrieved (default: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview))
    public convenience init(currentVersion: SystemVersion? = nil, appBundle: Bundle, deploymentURLs: [Deployment: URL], loadingView: (@Sendable () -> AnyView)? = nil) {
        self.init(
            currentVersion: currentVersion,
            appBundle: appBundle,
            deploymentURLs: deploymentURLs.reduce([Deployment: URLPackage]()) { result, pair in
                var result = result
                let (deployment, url) = pair

                result[deployment] = .init(serverBaseURL: url, resourcesBaseURL: url)
                return result
            },
            loadingView: loadingView
        )
    }
}

public enum MVVMEnvironmentError: Error {
    case missingDeploymentConfiguration(deployment: Deployment)
}

private struct DefaultLoadingView: View {
    var body: some View {
        ProgressView()
    }
}

private extension MVVMEnvironment {
    static func ensureVersionsCompatible(currentVersion: SystemVersion, appBundle: Bundle) {
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
    }
}
#endif
