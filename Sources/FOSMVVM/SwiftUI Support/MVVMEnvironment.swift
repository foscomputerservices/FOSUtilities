// MVVMEnvironment.swift
//
// Created by David Hunt on 9/11/24
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
public final class MVVMEnvironment {
    /// A set of base URLs that define where the server resources can be found
    public struct URLPackage: Sendable {
        /// The base URL of the web service
        public let serverBaseURL: URL

        /// The base  URL for images
        public let resourcesBaseURL: URL

        /// Initializes the ``MMVEnvironment``
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
    public let loadingView: () -> AnyView

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

    /// Initializes the ``MMVEnvironment``
    ///
    /// - Parameters:
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - loadingView: <#loadingView description#>
    public init(deploymentURLs: [Deployment: URLPackage], loadingView: (() -> AnyView)? = nil) {
        self.deploymentURLs = deploymentURLs
        self.loadingView = loadingView ?? { AnyView(DefaultLoadingView()) }
    }

    /// Initializes the ``MVVMEnvironment``
    ///
    /// This convenience initializer uses each deployment URL for both the *serverBaseURL* and the *resourcesBaseURL*.
    ///
    /// - Parameters:
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - loadingView: <#loadingView description#>
    public convenience init(deploymentURLs: [Deployment: URL], loadingView: (() -> AnyView)? = nil) {
        self.init(
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
#endif
