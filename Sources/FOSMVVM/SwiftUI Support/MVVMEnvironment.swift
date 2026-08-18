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
#if os(WASI)
import JavaScriptKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
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

        /// The base URL of the live-invalidation stream
        public let invalidationBaseURL: URL

        /// Initializes the ``MVVMEnvironment``
        ///
        /// - Parameters:
        ///   - serverBaseURL: The base URL of the web service used to retrieve ``ViewModel``s
        ///   - resourcesBaseURL: The base URL of the web service used to retrieve images (default: ``serverBaseURL``)
        ///   - invalidationBaseURL: The base URL of the live-invalidation stream (default: ``serverBaseURL``)
        public init(serverBaseURL: URL, resourcesBaseURL: URL? = nil, invalidationBaseURL: URL? = nil) {
            self.serverBaseURL = serverBaseURL
            self.resourcesBaseURL = resourcesBaseURL ?? serverBaseURL
            self.invalidationBaseURL = invalidationBaseURL ?? serverBaseURL
        }
    }

    public let resourceBundles: [Bundle]
    public let resourceDirectoryName: String?
    private let localizationStore: LocalizationStore?

    /// A configuration of server URLs for each given ``Deployment``
    public let deploymentURLs: [Deployment: URLPackage]

    /// A dictionary of values to populate the *URLRequest*'s HTTPHeaderFields
    public let requestHeaders: [String: String]

    /// Supplies the authentication headers that accompany every ``ServerRequest``
    ///
    /// The provider is consulted per request, so a rotating credential (a refreshed
    /// access token) is picked up on the next call — the dynamic sibling of the static
    /// ``requestHeaders``. On a duplicate header field the provider's value wins.
    /// `nil` (the default) sends requests without authentication headers.
    ///
    /// Use the stock ``BearerCredentialProvider`` for `Authorization: Bearer`
    /// authentication, or conform your own ``ClientCredentialProvider``.
    public let clientCredentialProvider: (any ClientCredentialProvider)?

    /// The transport that delivers server invalidation nudges, or `nil` when live
    /// invalidation is not configured — see ``InvalidationChannel``
    public let invalidationChannel: (any InvalidationChannel)?

    /// A function that is called when there is an error processing a ``ServerRequest``
    ///
    /// Surface rejections (``CredentialRejectedError``) are never routed here — they
    /// always throw to the caller.
    public let requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)?

    /// A custom ``URLSession``
    public let session: URLSession?

    #if canImport(SwiftUI)
    typealias ViewFactory = @MainActor (Data) throws -> AnyView

    #if DEBUG
    struct TestViewRegistration {
        let factory: ViewFactory
        let scrollable: Bool
    }

    @MainActor static var registeredTestTypes: [String: TestViewRegistration] = [:]
    #endif

    /// Registers a *ViewModelView* so that `testHost()` can present it under test
    ///
    /// Gather the calls into a static extension on ``MVVMEnvironment`` — where they can be
    /// made unqualified — and call that from your application's `init()`:
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///
    ///    var body: some Scene {
    ///      WindowGroup {
    ///        LandingPageView()
    ///        #if DEBUG
    ///        .testHost()
    ///        #endif
    ///      }
    ///      .environment(mvvmEnv)
    ///    }
    ///
    ///    init() {
    ///      MVVMEnvironment.registerTestingViews()
    ///    }
    /// }
    ///
    /// private extension MVVMEnvironment {
    ///    // Every ViewModelView is listed here to enable individualized testing of each view
    ///    @MainActor static func registerTestingViews() {
    ///      #if DEBUG
    ///      registerTestView(LandingPageView.self)
    ///      registerTestView(SettingsView.self)
    ///      #endif
    ///    }
    /// }
    /// ```
    ///
    /// Only the *body* of this function is `#if DEBUG`, so the call compiles away to a no-op in
    /// release builds and the `#if DEBUG` can stay inside your helper. Hoisting it up to the
    /// call site in `init()` is equally correct if you prefer it there.
    ///
    /// > Important: `init()` is the only supported home for these calls. `testHost()`
    /// > resolves the view under test *before the first render*, so registration performed
    /// > later — from a computed property such as `mvvmEnv`, from `.onAppear`, or from
    /// > `.task` — arrives too late and the application stops with a diagnostic naming
    /// > the view it could not find.
    ///
    /// > Note: Registration is a no-op in release builds.
    ///
    /// ## Views Designed for a Scrolling Parent
    ///
    /// A view that lives inside a scrolling parent in production — a form card inside a
    /// `ScrollView`, a section of a longer page — is taller than any window when presented
    /// bare: the harness compresses and overlaps its content, burying controls where no tap
    /// can reach them. Declare the design fact at registration and the harness presents the
    /// view inside a vertical `ScrollView`, as production does:
    ///
    /// ```swift
    /// registerTestView(DeviceCardView.self, scrollable: true)
    /// ```
    ///
    /// The declaration also restores what a missing scroll parent silently disables:
    /// XCUITest's automatic scroll-to-visible for off-screen elements, and keyboard
    /// avoidance that scrolls instead of displacing the whole content.
    ///
    /// > Important: `scrollable: true` states the view's *designed* production environment —
    /// > it matches the harness to the design. It is not an escape hatch for a view that
    /// > overflows its production container too; that is a layout bug the harness should
    /// > keep surfacing. There is no per-test override: a suite that needs the same view
    /// > presented both bare and scrolled is claiming the view has two designed
    /// > environments — bring that evidence to FOSUtilities rather than working around
    /// > the declaration.
    ///
    /// - Parameters:
    ///   - type: The *ViewModelView* to make available to *ViewModelDisplayTestCase*
    ///   - scrollable: Declare `true` for a view designed to live inside a scrolling parent
    ///     in production; the harness then presents it inside a vertical `ScrollView`
    ///     (default: `false` — the view is presented bare, exactly as before).
    @MainActor public static func registerTestView<V: ViewModelView>(
        _ type: V.Type,
        scrollable: Bool = false
    ) {
        #if DEBUG
        registeredTestTypes[String(describing: V.VM.self)] = TestViewRegistration(
            factory: { @MainActor data in
                try AnyView(V(viewModel: data.fromJSON()))
            },
            scrollable: scrollable
        )
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
    /// > This is only provided/necessary for applications that create ``ViewModel``s
    /// > in the application as opposed on the server.
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
    /// > This is only provided/necessary for applications that create ``ViewModel``s
    /// > in the application as opposed on the server.
    ///
    /// > The result of this function is **uncached** as opposed to ``clientLocalizationStore``
    public func resolveClientLocalizationStore() throws -> LocalizationStore {
        if let localizationStore {
            localizationStore
        } else {
            try resourceBundles.yamlLocalization(
                resourceDirectoryName: resourceDirectoryName ?? ""
            )
        }
    }

    @ObservationIgnored
    private var _clientLocalizationStore: LocalizationStore?

    /// Returns the URL for the web server that provides ``ViewModel``s for the current ``Deployment``
    public var serverBaseURL: URL {
        get async throws {
            try await currentURLPackage().serverBaseURL
        }
    }

    /// Returns the URL for the web server that provides images and resources for the current ``Deployment``
    public var resourcesBaseURL: URL {
        get async throws {
            try await currentURLPackage().resourcesBaseURL
        }
    }

    /// The one Deployment → ``URLPackage`` resolution every base-URL accessor projects from.
    private func currentURLPackage() async throws -> URLPackage {
        let deployment = await Deployment.current
        guard let result = deploymentURLs[deployment] else {
            throw MVVMEnvironmentError.missingDeploymentConfiguration(deployment: deployment)
        }

        return result
    }

    @ObservationIgnored
    private var _defaultInvalidationChannel: (any InvalidationChannel)?

    @ObservationIgnored
    private var _invalidationDispatcher: InvalidationDispatcher?

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
    ///   - clientCredentialProvider: Supplies the authentication headers that accompany every
    ///     ``ServerRequest``; consulted per request — see ``ClientCredentialProvider`` (default: nil)
    ///   - invalidationChannel: The transport that delivers server invalidation nudges; supply one
    ///     only to replace the standard transport — see ``InvalidationChannel`` (default: nil)
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil). Surface rejections
    ///      (``CredentialRejectedError``) are never routed here — they always throw to the caller.
    ///   - session: An optional *URLSession* to use to process the request (default: *DataFetch.urlSessionConfiguration()*)
    ///   - loadingView: A function that produces a View that will be displayed while the ``ViewModel``
    ///     is being retrieved (default: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview))
    public init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        clientCredentialProvider: (any ClientCredentialProvider)? = nil,
        invalidationChannel: (any InvalidationChannel)? = nil,
        deploymentURLs: [Deployment: URLPackage],
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil,
        session: URLSession? = nil,
        loadingView: (@Sendable () -> AnyView)? = nil
    ) {
        self.localizationStore = nil
        self.resourceBundles = resourceBundles ?? [appBundle]
        self.resourceDirectoryName = resourceDirectoryName
        self.requestHeaders = requestHeaders
        self.clientCredentialProvider = clientCredentialProvider
        self.invalidationChannel = invalidationChannel
        self.deploymentURLs = deploymentURLs
        self.requestErrorHandler = requestErrorHandler
        self.session = session
        self.loadingView = loadingView ?? { AnyView(DefaultLoadingView()) }

        // fosmvvm-review:disable:next no-silent-failure -- This behavior is intentional
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
    ///   - clientCredentialProvider: Supplies the authentication headers that accompany every
    ///     ``ServerRequest``; consulted per request — see ``ClientCredentialProvider`` (default: nil)
    ///   - invalidationChannel: The transport that delivers server invalidation nudges; supply one
    ///     only to replace the standard transport — see ``InvalidationChannel`` (default: nil)
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil). Surface rejections
    ///      (``CredentialRejectedError``) are never routed here — they always throw to the caller.
    ///   - session: An optional *URLSession* to use to process the request (default: *DataFetch.urlSessionConfiguration()*)
    ///   - loadingView: A function that produces a View that will be displayed while the ``ViewModel``
    ///     is being retrieved (default: [ProgressView](https://developer.apple.com/documentation/swiftui/progressview))
    public convenience init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        clientCredentialProvider: (any ClientCredentialProvider)? = nil,
        invalidationChannel: (any InvalidationChannel)? = nil,
        deploymentURLs: [Deployment: URL],
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil,
        session: URLSession? = nil,
        loadingView: (@Sendable () -> AnyView)? = nil
    ) {
        self.init(
            currentVersion: currentVersion,
            appBundle: appBundle,
            resourceBundles: resourceBundles,
            resourceDirectoryName: resourceDirectoryName,
            requestHeaders: requestHeaders,
            clientCredentialProvider: clientCredentialProvider,
            invalidationChannel: invalidationChannel,
            deploymentURLs: deploymentURLs.reduce([Deployment: URLPackage]()) { result, pair in
                var result = result
                let (deployment, url) = pair

                result[deployment] = .init(serverBaseURL: url, resourcesBaseURL: url)
                return result
            },
            requestErrorHandler: requestErrorHandler,
            session: session,
            loadingView: loadingView
        )
    }

    /// Initializes ``MVVMEnvironment`` for SwiftUI previews
    ///
    /// > This overload does **NOT** check the application's version as it is not necessary for previews
    init(
        localizationStore: LocalizationStore,
        deploymentURLs: [Deployment: URLPackage],
        session: URLSession? = nil,
        loadingView: (
            @Sendable () -> AnyView
        )? = nil
    ) {
        self.localizationStore = localizationStore
        self.resourceBundles = []
        self.resourceDirectoryName = nil
        self.requestHeaders = [:]
        self.clientCredentialProvider = nil
        self.invalidationChannel = nil
        self.deploymentURLs = deploymentURLs
        self.requestErrorHandler = nil
        self.session = session
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
    ///   - clientCredentialProvider: Supplies the authentication headers that accompany every
    ///     ``ServerRequest``; consulted per request — see ``ClientCredentialProvider`` (default: nil)
    ///   - invalidationChannel: The transport that delivers server invalidation nudges; supply one
    ///     only to replace the standard transport — see ``InvalidationChannel`` (default: nil)
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - session: An optional *URLSession* to use to process the request (default: *DataFetch.urlSessionConfiguration()*)
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil). Surface rejections
    ///      (``CredentialRejectedError``) are never routed here — they always throw to the caller.
    public init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        clientCredentialProvider: (any ClientCredentialProvider)? = nil,
        invalidationChannel: (any InvalidationChannel)? = nil,
        deploymentURLs: [Deployment: URLPackage],
        session: URLSession? = nil,
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil
    ) {
        #if os(WASI)
        _ = JSObject.global.console.log("[MVVMEnv] Designated init started")
        #endif
        self.localizationStore = nil
        self.resourceBundles = resourceBundles ?? [appBundle]
        self.resourceDirectoryName = resourceDirectoryName
        self.requestHeaders = requestHeaders
        self.clientCredentialProvider = clientCredentialProvider
        self.invalidationChannel = invalidationChannel
        self.deploymentURLs = deploymentURLs
        self.requestErrorHandler = requestErrorHandler
        self.session = session

        #if os(WASI)
        _ = JSObject.global.console.log("[MVVMEnv] Before version setup")
        #endif

        #if canImport(SwiftUI)
        self.loadingView = { AnyView(DefaultLoadingView()) }
        // fosmvvm-review:disable:next no-silent-failure -- This behavior is intentional
        let currentVersion = currentVersion ?? (try? appBundle.appleOSVersion) ?? SystemVersion.current
        SystemVersion.setCurrentVersion(currentVersion)
        #else
        let currentVersion = currentVersion ?? SystemVersion.current
        SystemVersion.setCurrentVersion(currentVersion)
        #endif

        #if os(WASI)
        _ = JSObject.global.console.log("[MVVMEnv] Init complete")
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
    ///   - clientCredentialProvider: Supplies the authentication headers that accompany every
    ///     ``ServerRequest``; consulted per request — see ``ClientCredentialProvider`` (default: nil)
    ///   - invalidationChannel: The transport that delivers server invalidation nudges; supply one
    ///     only to replace the standard transport — see ``InvalidationChannel`` (default: nil)
    ///   - deploymentURLs: The base URLs of the web service for the given ``Deployment``s
    ///   - session: An optional *URLSession* to use to process the request (default: *DataFetch.urlSessionConfiguration()*)
    ///   - requestErrorHandler: A function that can take action when an error occurs when resolving
    ///      ``ViewModel`` via a ``ViewModelRequest`` (default: nil). Surface rejections
    ///      (``CredentialRejectedError``) are never routed here — they always throw to the caller.
    public convenience init(
        currentVersion: SystemVersion? = nil,
        appBundle: Bundle,
        resourceBundles: [Bundle]? = nil,
        resourceDirectoryName: String? = nil,
        requestHeaders: [String: String] = [:],
        clientCredentialProvider: (any ClientCredentialProvider)? = nil,
        invalidationChannel: (any InvalidationChannel)? = nil,
        deploymentURLs: [Deployment: URL],
        session: URLSession? = nil,
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil
    ) {
        #if os(WASI)
        _ = JSObject.global.console.log("[MVVMEnv] Convenience init started")
        #endif
        self.init(
            currentVersion: currentVersion,
            appBundle: appBundle,
            resourceBundles: resourceBundles,
            resourceDirectoryName: resourceDirectoryName,
            requestHeaders: requestHeaders,
            clientCredentialProvider: clientCredentialProvider,
            invalidationChannel: invalidationChannel,
            deploymentURLs: deploymentURLs.reduce([Deployment: URLPackage]()) { result, pair in
                var result = result
                let (deployment, url) = pair

                result[deployment] = .init(serverBaseURL: url, resourcesBaseURL: url)
                return result
            },
            session: session,
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

extension MVVMEnvironment {
    /// The base URL of the live-invalidation stream for the current ``Deployment``
    var invalidationBaseURL: URL {
        get async throws {
            try await currentURLPackage().invalidationBaseURL
        }
    }

    /// The channel the live-invalidation dispatcher consumes: the app-supplied
    /// ``invalidationChannel`` if set, otherwise the lazily-synthesized default SSE channel over
    /// ``invalidationBaseURL`` and ``clientCredentialProvider``. The default channel is
    /// Darwin-only (FoundationNetworking lacks `URLSession.bytes`); on Linux/WASI this is `nil`
    /// and the app degrades to fetch-once.
    @MainActor
    var effectiveInvalidationChannel: (any InvalidationChannel)? {
        if let invalidationChannel {
            return invalidationChannel
        }
        #if canImport(Darwin)
        if let cached = _defaultInvalidationChannel {
            return cached
        }
        let channel = SSEInvalidationChannel(
            baseURL: { [weak self] in
                guard let self else { throw await MVVMEnvironmentError.missingDeploymentConfiguration(deployment: Deployment.current) }
                return try await invalidationBaseURL
            },
            credentialProvider: clientCredentialProvider,
            session: session
        )
        _defaultInvalidationChannel = channel
        return channel
        #else
        return nil
        #endif
    }

    /// The dispatcher live screens register with — lazily created over ``effectiveInvalidationChannel``.
    /// `@MainActor`-only, like the channel memo it mirrors: creation and every consultation happen on
    /// the main actor, which is what leaves `_invalidationDispatcher` safe to store unsynchronized.
    @MainActor
    var invalidationDispatcher: InvalidationDispatcher {
        if let _invalidationDispatcher {
            return _invalidationDispatcher
        }
        let dispatcher = InvalidationDispatcher(channel: effectiveInvalidationChannel)
        _invalidationDispatcher = dispatcher
        return dispatcher
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
