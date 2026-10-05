// Application+PushNotifications.swift
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

#if APNs
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

public extension Vapor.Application {
    /// Apple push notifications for this server
    ///
    /// Configure once at boot, then send from wherever your server decides who to tell:
    ///
    /// ```swift
    /// try app.pushNotifications.configure(configuration)
    /// try await app.pushNotifications.send(notification, to: devices)
    /// ```
    var pushNotifications: PushNotifications {
        PushNotifications(application: self)
    }
}

/// Sends Apple push notifications to the app installs your server has stored
///
/// Reach it through `app.pushNotifications`. Configure it once in `configure(_:)`
/// with your APNs key (see ``PushConfiguration``), then send a ``PushNotification``
/// to the ``PushDestination`` rows you choose:
///
/// ```swift
/// // A card was assigned: tell every device of the assignee
/// let devices = try await MemberDevice.query(on: req.db)
///     .filter(\.$member.$id == assignee.requireID())
///     .all()
///
/// try await req.application.pushNotifications.send(
///     PushNotification(
///         title: .localized(key: "CardAssigned.title"),
///         body: .localized(key: "CardAssigned.body"),
///         sound: .default
///     ),
///     to: devices
/// )
/// ```
///
/// The title and body are localized for each destination in its own locale, from the
/// same localization YAML your responses use (see `initYamlLocalization`), so each
/// device shows finished text in its app's language.
public struct PushNotifications: Sendable {
    let application: Application

    /// Turns on push notifications for this server
    ///
    /// ```swift
    /// try app.pushNotifications.configure(PushConfiguration(
    ///     privateKey: Environment.get("APNS_PRIVATE_KEY")!,
    ///     keyId: Environment.get("APNS_KEY_ID")!,
    ///     teamId: Environment.get("APNS_TEAM_ID")!,
    ///     onRetiredToken: { deviceToken in
    ///         try await MemberDevice.query(on: app.db)
    ///             .filter(\.$deviceToken == deviceToken)
    ///             .delete()
    ///     }
    /// ))
    /// ```
    ///
    /// Call it once, in `configure(_:)`. The connections to Apple close when the
    /// application shuts down.
    ///
    /// - Throws: When the private key is not a valid APNs `.p8` key, or when push
    ///   notifications are already configured
    public func configure(_ configuration: PushConfiguration) throws {
        try requireUnconfigured()
        try install(
            transport: APNSPushTransport(
                configuration: configuration,
                eventLoopGroup: application.eventLoopGroup
            ),
            onRetiredToken: configuration.onRetiredToken
        )
    }

    /// Sends a notification to each destination
    ///
    /// ```swift
    /// try await app.pushNotifications.send(notification, to: devices)
    /// ```
    ///
    /// Every destination is attempted. For each one, the title and body are localized
    /// in the destination's ``PushDestination/locale`` and sent to its
    /// ``PushDestination/topic`` in its ``PushDestination/environment``. When Apple
    /// answers that a token is retired, `onRetiredToken` from your
    /// ``PushConfiguration`` is called with it.
    ///
    /// > Note: Apple accepting a notification means it will try to deliver it; a device
    /// > that is off receives it when it next connects.
    ///
    /// - Parameters:
    ///   - notification: The notification to send
    ///   - destinations: The app installs to send it to
    /// - Throws: When push notifications are not configured, when the notification's
    ///   text has no translation for a destination's locale, or, after every destination
    ///   was attempted, when any of them failed
    public func send<Destinations: Sequence>(
        _ notification: PushNotification,
        to destinations: Destinations
    ) async throws where Destinations.Element: PushDestination {
        guard let service = application.storage[PushServiceKey.self] else {
            throw PushNotificationsError.notConfigured
        }

        let targets = destinations.map {
            PushTarget(
                deviceToken: $0.deviceToken,
                topic: $0.topic,
                environment: $0.environment,
                locale: $0.locale
            )
        }
        guard !targets.isEmpty else {
            return
        }

        let needsText = notification.title != nil || notification.body != nil
        let store: (any LocalizationStore)? = needsText ? try application.requireLocalizationStore() : nil

        try await service.send(notification, to: targets, store: store)
    }
}

extension PushNotifications {
    /// The test seam: installs `transport` in place of Apple
    func configure(
        transport: some PushTransport,
        onRetiredToken: @escaping @Sendable (String) async throws -> Void
    ) throws {
        try requireUnconfigured()
        install(transport: transport, onRetiredToken: onRetiredToken)
    }

    private func requireUnconfigured() throws {
        guard application.storage[PushServiceKey.self] == nil else {
            throw PushNotificationsError.alreadyConfigured
        }
    }

    private func install(
        transport: some PushTransport,
        onRetiredToken: @escaping @Sendable (String) async throws -> Void
    ) {
        let service = PushService(transport: transport, onRetiredToken: onRetiredToken)
        application.storage[PushServiceKey.self] = service
        application.lifecycle.use(PushServiceShutdown(service: service))
    }
}

/// One destination's values, read once so the rows themselves never cross tasks
struct PushTarget: Sendable {
    let deviceToken: String
    let topic: String
    let environment: PushEnvironment
    let locale: Locale
}

struct PushService: Sendable {
    /// Existential by design: the transport is chosen at runtime (Apple, or a test's).
    let transport: any PushTransport
    let onRetiredToken: @Sendable (String) async throws -> Void

    /// How many deliveries are in flight at once
    private static let window = 16

    func send(
        _ notification: PushNotification,
        to targets: [PushTarget],
        store: (any LocalizationStore)?
    ) async throws {
        let deliveries = Self.deliveries(of: notification, to: targets, store: store)

        var failures: [any Error] = []
        await withTaskGroup(of: (any Error)?.self) { group in
            var pending = deliveries[...]
            func enqueueNext() {
                guard let (target, payload) = pending.popFirst() else {
                    return
                }
                group.addTask {
                    await deliver(payload, to: target)
                }
            }

            for _ in 0..<Self.window {
                enqueueNext()
            }
            for await failure in group {
                if let failure {
                    failures.append(failure)
                }
                enqueueNext()
            }
        }

        guard failures.isEmpty else {
            throw PushNotificationsError.deliveryFailed(failures, attempted: targets.count)
        }
    }

    private func deliver(_ payload: Result<PushPayload, any Error>, to target: PushTarget) async -> (any Error)? {
        do {
            let result = try await transport.deliver(
                payload.get(),
                to: target.deviceToken,
                topic: target.topic,
                environment: target.environment
            )
            if result == .retired {
                try await onRetiredToken(target.deviceToken)
            }
            return nil
        } catch {
            return error
        }
    }

    /// Pairs each target with its payload, localizing once per distinct locale
    static func deliveries(
        of notification: PushNotification,
        to targets: [PushTarget],
        store: (any LocalizationStore)?
    ) -> [(PushTarget, Result<PushPayload, any Error>)] {
        var byLocale: [Locale: Result<PushPayload, any Error>] = [:]
        return targets.map { target in
            if let payload = byLocale[target.locale] {
                return (target, payload)
            }
            let payload = Result<PushPayload, any Error> {
                try PushPayload(
                    title: localize(notification.title, in: target.locale, store: store),
                    body: localize(notification.body, in: target.locale, store: store),
                    badge: notification.badge,
                    sound: notification.sound,
                    interruptionLevel: notification.interruptionLevel
                )
            }
            byLocale[target.locale] = payload
            return (target, payload)
        }
    }

    private static func localize(
        _ text: LocalizableString?,
        in locale: Locale,
        store: (any LocalizationStore)?
    ) throws -> String? {
        guard let text else {
            return nil
        }
        guard let store else {
            throw PushNotificationsError.notConfigured
        }

        // Strict: a missing translation fails this destination instead of sending a
        // blank alert.
        let encoder = JSONEncoder.localizingEncoder(in: locale, store: store, strictLocalization: true)
        return try JSONDecoder().decode(String.self, from: encoder.encode(text))
    }
}

private struct PushServiceKey: StorageKey {
    typealias Value = PushService
}

struct PushServiceShutdown: LifecycleHandler {
    let service: PushService

    func shutdown(_ application: Application) {
        // APNSClient offers only an async shutdown, so bridge to it. Blocking is safe for
        // the reason Vapor's own HTTPClient.syncShutdown() is: app.shutdown() is never
        // called from an event loop the clients close on.
        let transport = service.transport
        do {
            try Task.synchronous {
                try await transport.shutdown()
            }
        } catch {
            Self.report(error, to: application)
        }
    }

    func shutdownAsync(_ application: Application) async {
        do {
            try await service.transport.shutdown()
        } catch {
            Self.report(error, to: application)
        }
    }

    private static func report(_ error: any Error, to application: Application) {
        application.logger.warning("Push notifications: closing the connections to Apple failed: \(error)")
    }
}

/// Configuration and delivery failures; internal like LiveInvalidationError, its value
/// is the diagnostic message.
enum PushNotificationsError: Error, CustomDebugStringConvertible {
    case notConfigured
    case alreadyConfigured
    case invalidPrivateKey
    case deliveryFailed([any Error], attempted: Int)

    var debugDescription: String {
        switch self {
        case .notConfigured:
            "Push notifications are not configured; call app.pushNotifications.configure(_:) in configure(_:)"
        case .alreadyConfigured:
            "app.pushNotifications.configure(_:) was called more than once"
        case .invalidPrivateKey:
            "PushConfiguration.privateKey is not a PEM-encoded APNs .p8 key"
        case .deliveryFailed(let failures, let attempted):
            "Push notifications: \(failures.count) of \(attempted) deliveries failed; first: \(String(reflecting: failures[0]))"
        }
    }
}
#endif
