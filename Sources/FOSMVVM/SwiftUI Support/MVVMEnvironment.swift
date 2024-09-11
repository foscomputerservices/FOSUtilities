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
///                  serverBaseURL: URL(string: "http://localhost:8080")!
///              ) {
///                 AnyView { Text("Loading...") }
///              }
///          )
///      }
///  }
/// ```
@Observable
public final class MVVMEnvironment {
    /// The base URL of the web service
    public let serverBaseURL: URL

    /// The base  URL for images
    public let imagesBaseURL: URL

    /// A view to be presented when the ``ViewModel`` is being requested
    /// from the web service
    ///
    /// > Note: A non-localized "Loading..." is presented if no view is provided
    public let loadingView: () -> AnyView

    /// Initializes the ``MMVEnvironment``
    ///
    /// - Parameters:
    ///   - serverBaseURL: The base URL of the web service used to retrieve ``ViewModel``s
    ///   - imagesBaseURL: The base URL of the web service used to retrieve images (default: ``serverBaseURL``)
    ///   - loadingView: <#loadingView description#>
    public init(serverBaseURL: URL, imagesBaseURL: URL? = nil, loadingView: (() -> AnyView)? = nil) {
        self.serverBaseURL = serverBaseURL
        self.imagesBaseURL = imagesBaseURL ?? serverBaseURL
        self.loadingView = loadingView ?? { AnyView(DefaultLoadingView()) }
    }
}

private struct DefaultLoadingView: View {
    var body: some View {
        ProgressView()
    }
}
#endif
