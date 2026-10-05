// PushRegistration.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

#if canImport(UserNotifications)
import FOSFoundation
import Foundation
import UserNotifications
#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Asks for permission to notify, registers with Apple, and hands your app each device token
///
/// Create one in your app delegate, ask for permission at every launch, and forward
/// the token Apple delivers. Your `onDeviceToken` hook sends it to your server with
/// your own register request:
///
/// ```swift
/// #if DEBUG
/// let pushEnvironment = PushEnvironment.sandbox
/// #else
/// let pushEnvironment = PushEnvironment.production
/// #endif
///
/// final class AppDelegate: NSObject, UIApplicationDelegate {
///     let pushRegistration = PushRegistration(environment: pushEnvironment) { registration in
///         let request = RegisterDeviceRequest(requestBody: .init(
///             deviceToken: registration.deviceToken,
///             topic: registration.topic,
///             environment: registration.environment,
///             locale: registration.locale
///         ))
///         try? await request.processRequest(mvvmEnv: BoardsApp.mvvmEnv)
///     }
///
///     func application(
///         _ application: UIApplication,
///         didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
///     ) -> Bool {
///         Task { try? await pushRegistration.requestPermission() }
///         return true
///     }
///
///     func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
///         pushRegistration.deviceTokenReceived(deviceToken)
///     }
/// }
///
/// @main
/// struct BoardsApp: App {
///     @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
///     // ...
/// }
/// ```
///
/// SwiftUI has no way to receive the device token, so the app delegate's one forwarding
/// line is required. On macOS the delegate is an `NSApplicationDelegate` adapted with
/// `@NSApplicationDelegateAdaptor`, and the method is
/// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` on `NSApplication`.
/// On watchOS it is a `WKApplicationDelegate` adapted with `@WKApplicationDelegateAdaptor`,
/// and the method is `didRegisterForRemoteNotifications(withDeviceToken:)`.
///
/// > Important: Ask at every launch. Apple hands over the token each time, and
/// > registering each time keeps the language your server stores current, so
/// > notifications arrive in the app's language even after the user changes it.
///
/// > Note: The hook is called on every launch and whenever Apple replaces the token,
/// > so your server's register request should insert or update, never only insert.
@MainActor
public final class PushRegistration {
    /// What your server stores for this app install
    ///
    /// Your `onDeviceToken` hook receives one; copy its four values into your register
    /// request:
    ///
    /// ```swift
    /// let pushRegistration = PushRegistration(environment: pushEnvironment) { registration in
    ///     let request = RegisterDeviceRequest(requestBody: .init(
    ///         deviceToken: registration.deviceToken,
    ///         topic: registration.topic,
    ///         environment: registration.environment,
    ///         locale: registration.locale
    ///     ))
    ///     try? await request.processRequest(mvvmEnv: BoardsApp.mvvmEnv)
    /// }
    /// ```
    ///
    /// Your server's row conforms to FOSMVVMVapor's `PushDestination` with these values.
    public struct Registration: Hashable, Sendable, Stubbable {
        /// The token Apple issued to this app install, as hexadecimal text
        public let deviceToken: String

        /// This app's bundle identifier, which addresses the notification to it
        ///
        /// > Important: An app whose bundle has no bundle identifier cannot be addressed.
        /// > Debug builds stop with an assertion; release builds hand over an empty topic,
        /// > which Apple rejects when your server sends to it.
        public let topic: String

        /// The APNs environment that issued ``deviceToken``
        public let environment: PushEnvironment

        /// The language the app is running in, which notification text should use
        ///
        /// This is the app's own language, so a user who chose French for this app
        /// receives French notifications even when the device is set to English. An app
        /// with no localization of its own (only `Base`) uses the device's language.
        public let locale: Locale

        /// A ``Registration`` for tests and previews
        ///
        /// Test the code your `onDeviceToken` hook runs without registering with Apple:
        ///
        /// ```swift
        /// extension RegisterDeviceRequest.RequestBody {
        ///     init(_ registration: PushRegistration.Registration) {
        ///         self.init(
        ///             deviceToken: registration.deviceToken,
        ///             topic: registration.topic,
        ///             environment: registration.environment,
        ///             locale: registration.locale
        ///         )
        ///     }
        /// }
        ///
        /// @Test func registerBodyCarriesTheAppsLanguage() {
        ///     let registration = PushRegistration.Registration.stub(locale: Locale(identifier: "fr"))
        ///
        ///     #expect(RegisterDeviceRequest.RequestBody(registration).locale == registration.locale)
        /// }
        /// ```
        ///
        /// - Parameters:
        ///   - deviceToken: The token as hexadecimal text (default: 64 hexadecimal digits)
        ///   - topic: The app's bundle identifier (default: `com.example.boards`)
        ///   - environment: The APNs environment (default: ``PushEnvironment/sandbox``)
        ///   - locale: The app's language (default: English)
        public static func stub(
            deviceToken: String = String(repeating: "a1", count: 32),
            topic: String = "com.example.boards",
            environment: PushEnvironment = .sandbox,
            locale: Locale = Locale(identifier: "en")
        ) -> Self {
            .init(deviceToken: deviceToken, topic: topic, environment: environment, locale: locale)
        }

        public static func stub() -> Self {
            .stub(environment: .sandbox)
        }
    }

    private let onDeviceToken: @MainActor @Sendable (Registration) async -> Void
    private let environment: PushEnvironment
    private let bundle: Bundle

    /// Creates the registration
    ///
    /// ```swift
    /// #if DEBUG
    /// let environment = PushEnvironment.sandbox
    /// #else
    /// let environment = PushEnvironment.production
    /// #endif
    ///
    /// let pushRegistration = PushRegistration(environment: environment) { registration in
    ///     // send registration.deviceToken, .topic, .environment and .locale to your server
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - environment: The APNs environment this build of the app is signed for
    ///   - onDeviceToken: Called with this install's token at every launch and
    ///     whenever Apple replaces it; send it to your server here
    public convenience init(
        environment: PushEnvironment,
        onDeviceToken: @escaping @MainActor @Sendable (Registration) async -> Void
    ) {
        self.init(environment: environment, bundle: .main, onDeviceToken: onDeviceToken)
    }

    init(
        environment: PushEnvironment,
        bundle: Bundle,
        onDeviceToken: @escaping @MainActor @Sendable (Registration) async -> Void
    ) {
        self.environment = environment
        self.bundle = bundle
        self.onDeviceToken = onDeviceToken
    }

    /// Asks the user for permission to notify and, once granted, registers with Apple
    ///
    /// ```swift
    /// let granted = try await pushRegistration.requestPermission()
    /// ```
    ///
    /// The user is asked only the first time; later calls return their answer. When
    /// permission is granted, Apple then delivers the device token to your app
    /// delegate, which forwards it with ``deviceTokenReceived(_:)``.
    ///
    /// > Tip: tvOS shows only badges, so ask with `badgeOnly: true` there.
    ///
    /// - Parameter badgeOnly: Ask only to badge the app icon, not to show alerts or
    ///   play sounds (default: **false**)
    /// - Returns: **true** when the user allows notifications
    @discardableResult
    public func requestPermission(badgeOnly: Bool = false) async throws -> Bool {
        let options: UNAuthorizationOptions = badgeOnly ? [.badge] : [.alert, .badge, .sound]
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        if granted {
            registerForRemoteNotifications()
        }
        return granted
    }

    /// Forwards the device token Apple delivered to your app delegate
    ///
    /// ```swift
    /// func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    ///     pushRegistration.deviceTokenReceived(deviceToken)
    /// }
    /// ```
    ///
    /// Your `onDeviceToken` hook is then called with the token as text, with this
    /// app's topic, environment and language.
    ///
    /// - Parameter token: The token Apple passed to your app delegate
    public func deviceTokenReceived(_ token: Data) {
        Task {
            await handOver(token)
        }
    }

    func handOver(_ token: Data) async {
        await onDeviceToken(registration(from: token))
    }

    func registration(from token: Data) -> Registration {
        .init(
            deviceToken: token.map { String(format: "%02x", $0) }.joined(),
            topic: topic,
            environment: environment,
            locale: Self.language(from: bundle.preferredLocalizations)
        )
    }

    private var topic: String {
        guard let bundleIdentifier = bundle.bundleIdentifier else {
            assertionFailure("PushRegistration: the app's bundle has no bundle identifier, so its device token has no topic")
            return ""
        }
        return bundleIdentifier
    }

    /// The first preferred localization that names a language
    ///
    /// `Base` holds an app's unlocalized resources, not a language.
    static func language(from preferredLocalizations: [String]) -> Locale {
        if let language = preferredLocalizations.first(where: { $0 != "Base" }) {
            return Locale(identifier: language)
        }
        return Locale(identifier: Locale.current.language.minimalIdentifier)
    }

    private func registerForRemoteNotifications() {
        #if os(watchOS)
        WKApplication.shared().registerForRemoteNotifications()
        #elseif canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif canImport(AppKit)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
#endif
