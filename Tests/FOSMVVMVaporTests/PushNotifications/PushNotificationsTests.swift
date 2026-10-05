// PushNotificationsTests.swift
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
import APNSCore
import Crypto
import FOSMVVM
@testable import FOSMVVMVapor
import Foundation
import Testing
import Vapor

@Suite("app.pushNotifications — send")
struct PushNotificationsTests {
    @Test func localizesTitleAndBodyInEachDestinationsLocale() async throws {
        try await withPushApp { app, transport, _ in
            try await app.pushNotifications.send(
                .cardAssigned,
                to: [Device(token: "aa01", locale: .en), Device(token: "bb02", locale: .es)]
            )

            let sent = await transport.sentByToken
            #expect(sent["aa01"]?.payload.title == "New card")
            #expect(sent["aa01"]?.payload.body == "A card was assigned to you")
            #expect(sent["bb02"]?.payload.title == "Tarjeta nueva")
            #expect(sent["bb02"]?.payload.body == "Se te asignó una tarjeta")
        }
    }

    @Test func localizesASubstitutionsBodyWithItsValuesInEachLocale() async throws {
        try await withPushApp { app, transport, _ in
            let notification = PushNotification(
                title: LocalizableString.localized(key: "PushTest.title"),
                body: LocalizableString.localized(key: "PushTest.assigned")
                    .bind(substitutions: ["boardName": LocalizableString.constant("Roadmap")])
            )
            try await app.pushNotifications.send(
                notification,
                to: [Device(token: "aa01", locale: .en), Device(token: "bb02", locale: .es)]
            )

            let sent = await transport.sentByToken
            #expect(sent["aa01"]?.payload.title == "New card")
            #expect(sent["aa01"]?.payload.body == "A card on Roadmap was assigned to you")
            #expect(sent["bb02"]?.payload.title == "Tarjeta nueva")
            #expect(sent["bb02"]?.payload.body == "Se te asignó una tarjeta en Roadmap")
        }
    }

    @Test func missingTranslationOfASubstitutionsBodyFailsThatDestination() async throws {
        try await withPushApp { app, transport, _ in
            let notification = PushNotification(
                body: LocalizableString.localized(key: "PushTest.missing")
                    .bind(substitutions: ["boardName": LocalizableString.constant("Roadmap")])
            )
            let error = await #expect(throws: PushNotificationsError.self) {
                try await app.pushNotifications.send(notification, to: [Device(token: "aa01")])
            }

            let (failures, attempted) = try #require(error?.deliveryFailures)
            #expect(attempted == 1)
            let allMissingTranslations = failures.allSatisfy(\.isMissingTranslation)
            #expect(allMissingTranslations)
            #expect(await transport.sentByToken.isEmpty)
        }
    }

    @Test func carriesContentAvailableAndTheAppPayload() async throws {
        try await withPushApp { app, transport, _ in
            let notification = PushNotification(
                title: LocalizableString.localized(key: "PushTest.title"),
                contentAvailable: true,
                payload: CardAssignedPayload(boardName: "Roadmap", unreadCount: 4)
            )
            try await app.pushNotifications.send(notification, to: [Device(token: "aa01")])

            let payload = try #require(await transport.sentByToken["aa01"]?.payload)
            #expect(payload.contentAvailable)
            #expect(!payload.isBackground)

            let root = try encodedRoot(payload)
            let decoded = try JSONDecoder().decode(CardAssignedPayload.self, from: JSONSerialization.data(withJSONObject: root))
            #expect(decoded == CardAssignedPayload(boardName: "Roadmap", unreadCount: 4))
        }
    }

    @Test func sendsABadgeOnlyContentAvailablePushForTVOS() async throws {
        try await withPushApp(localized: false) { app, transport, _ in
            try await app.pushNotifications.send(
                PushNotification(badge: 2, contentAvailable: true),
                to: [Device(token: "aa01", topic: "com.example.boards.tv")]
            )

            let sent = try #require(await transport.sentByToken["aa01"])
            #expect(sent.topic == "com.example.boards.tv")
            #expect(sent.payload.isBadgeOnly)
            #expect(sent.payload.badge == 2)
            #expect(sent.payload.contentAvailable)
            // A badge is something the user sees, so this is an alert push, not a background one
            #expect(!sent.payload.isBackground)
        }
    }

    @Test func aPayloadThatIsNotAnObjectThrowsBeforeSending() async throws {
        try await withPushApp(localized: false) { app, transport, _ in
            let error = await #expect(throws: PushNotificationsError.self) {
                try await app.pushNotifications.send(
                    PushNotification(badge: 1, payload: ["Roadmap", "Backlog"]),
                    to: [Device(token: "aa01")]
                )
            }
            #expect(error?.isPayloadNotAnObject == true)
            #expect(await transport.sentByToken.isEmpty)
        }
    }

    @Test func aPayloadUsingTheAPSKeyThrowsBeforeSending() async throws {
        try await withPushApp(localized: false) { app, transport, _ in
            let error = await #expect(throws: PushNotificationsError.self) {
                try await app.pushNotifications.send(
                    PushNotification(badge: 1, payload: ["aps": "mine"]),
                    to: [Device(token: "aa01")]
                )
            }
            #expect(error?.isPayloadUsesAPSKey == true)
            #expect(await transport.sentByToken.isEmpty)
        }
    }

    @Test func carriesBadgeSoundAndInterruptionLevel() async throws {
        try await withPushApp { app, transport, _ in
            let notification = PushNotification(
                title: LocalizableString.localized(key: "PushTest.title"),
                badge: 7,
                sound: .named("card-assigned.caf"),
                interruptionLevel: .timeSensitive
            )
            try await app.pushNotifications.send(notification, to: [Device(token: "aa01")])

            let payload = try #require(await transport.sentByToken["aa01"]?.payload)
            #expect(payload.title == "New card")
            #expect(payload.body == nil)
            #expect(payload.badge == 7)
            #expect(payload.sound == .named("card-assigned.caf"))
            #expect(payload.interruptionLevel == .timeSensitive)
        }
    }

    @Test func sendsBadgeOnlyWithoutLocalizationStore() async throws {
        try await withPushApp(localized: false) { app, transport, _ in
            try await app.pushNotifications.send(PushNotification(badge: 3), to: [Device(token: "aa01")])

            let payload = try #require(await transport.sentByToken["aa01"]?.payload)
            #expect(payload.isBadgeOnly)
            #expect(payload.badge == 3)
        }
    }

    @Test func routesEachDestinationToItsTopicAndEnvironment() async throws {
        try await withPushApp { app, transport, _ in
            try await app.pushNotifications.send(
                PushNotification(badge: 1),
                to: [
                    Device(token: "aa01", topic: "com.example.boards", environment: .production),
                    Device(token: "bb02", topic: "com.example.boards.watchkitapp", environment: .sandbox)
                ]
            )

            let sent = await transport.sentByToken
            #expect(sent["aa01"]?.topic == "com.example.boards")
            #expect(sent["aa01"]?.environment == .production)
            #expect(sent["bb02"]?.topic == "com.example.boards.watchkitapp")
            #expect(sent["bb02"]?.environment == .sandbox)
        }
    }

    @Test func reportsRetiredTokensToTheHook() async throws {
        try await withPushApp(retiredTokens: ["dead"]) { app, _, retired in
            try await app.pushNotifications.send(
                PushNotification(badge: 1),
                to: [Device(token: "aa01"), Device(token: "dead")]
            )

            #expect(await retired.tokens == ["dead"])
        }
    }

    @Test func attemptsEveryDestinationBeforeThrowing() async throws {
        try await withPushApp(failingTokens: ["fail"]) { app, transport, _ in
            let error = await #expect(throws: PushNotificationsError.self) {
                try await app.pushNotifications.send(
                    PushNotification(badge: 1),
                    to: [Device(token: "fail"), Device(token: "aa01"), Device(token: "bb02")]
                )
            }

            let (failures, attempted) = try #require(error?.deliveryFailures)
            #expect(attempted == 3)
            #expect(failures.count == 1)
            #expect((failures.first as? Abort)?.status == .serviceUnavailable)

            let sent = await transport.sentByToken
            #expect(Set(sent.keys) == ["aa01", "bb02"])
        }
    }

    @Test func missingTranslationFailsInsteadOfSendingBlankText() async throws {
        try await withPushApp { app, transport, _ in
            let error = await #expect(throws: PushNotificationsError.self) {
                try await app.pushNotifications.send(
                    PushNotification(title: LocalizableString.localized(key: "PushTest.missing")),
                    to: [Device(token: "aa01")]
                )
            }

            let (failures, attempted) = try #require(error?.deliveryFailures)
            #expect(attempted == 1)
            #expect(failures.count == 1)
            let allMissingTranslations = failures.allSatisfy(\.isMissingTranslation)
            #expect(allMissingTranslations)
            #expect(await transport.sentByToken.isEmpty)
        }
    }

    @Test func sendWithoutConfigurationThrows() async throws {
        let app = try await Application.make(.testing)
        let error = await #expect(throws: PushNotificationsError.self) {
            try await app.pushNotifications.send(PushNotification(badge: 1), to: [Device(token: "aa01")])
        }
        #expect(error?.isNotConfigured == true)
        try await app.asyncShutdown()
    }

    @Test func configuringTwiceThrows() async throws {
        let app = try await Application.make(.testing)
        try app.pushNotifications.configure(transport: RecordingTransport(), onRetiredToken: { _ in })
        let error = #expect(throws: PushNotificationsError.self) {
            try app.pushNotifications.configure(transport: RecordingTransport(), onRetiredToken: { _ in })
        }
        #expect(error?.isAlreadyConfigured == true)
        try await app.asyncShutdown()
    }
}

@Suite("app.pushNotifications — Apple configuration")
struct PushConfigurationTests {
    @Test func configuresWithAValidKeyWithoutContactingApple() async throws {
        let app = try await Application.make(.testing)
        try app.pushNotifications.configure(PushConfiguration(
            privateKey: P256.Signing.PrivateKey().pemRepresentation,
            keyId: "KEYID12345",
            teamId: "TEAMID1234",
            onRetiredToken: { _ in }
        ))
        try await app.asyncShutdown()
    }

    @Test func rejectsAnInvalidKey() async throws {
        let app = try await Application.make(.testing)
        let error = #expect(throws: PushNotificationsError.self) {
            try app.pushNotifications.configure(PushConfiguration(
                privateKey: "not a key",
                keyId: "KEYID12345",
                teamId: "TEAMID1234",
                onRetiredToken: { _ in }
            ))
        }
        #expect(error?.isInvalidPrivateKey == true)
        try await app.asyncShutdown()
    }

    @Test func closesTheConnectionsToAppleOnSynchronousShutdown() async throws {
        let app = try await Application.make(.testing)
        let transport = try APNSPushTransport(
            configuration: PushConfiguration(
                privateKey: P256.Signing.PrivateKey().pemRepresentation,
                keyId: "KEYID12345",
                teamId: "TEAMID1234",
                onRetiredToken: { _ in }
            ),
            eventLoopGroup: app.eventLoopGroup
        )

        await shutDownSynchronously(transport, of: app)

        try await app.asyncShutdown()
    }

    @Test func goneIsRetiredAndBadDeviceTokenIsNot() {
        #expect(APNSPushTransport.isRetired(APNSError(responseStatus: 410)))
        #expect(!APNSPushTransport.isRetired(APNSError(responseStatus: 400)))
        #expect(!APNSPushTransport.isRetired(APNSError(responseStatus: 429)))
    }
}

@Suite("app.pushNotifications — shutdown")
struct PushShutdownTests {
    @Test func asyncShutdownClosesTheTransport() async throws {
        let app = try await Application.make(.testing)
        let transport = RecordingTransport()
        try app.pushNotifications.configure(transport: transport, onRetiredToken: { _ in })

        try await app.asyncShutdown()

        #expect(await transport.isShutDown)
    }

    @Test func synchronousShutdownClosesTheTransport() async throws {
        let app = try await Application.make(.testing)
        let transport = RecordingTransport()

        await shutDownSynchronously(transport, of: app)

        #expect(await transport.isShutDown)
        try await app.asyncShutdown()
    }
}

// MARK: - Support

/// Calls the handler's synchronous shutdown, as Vapor's `app.shutdown()` does, on a
/// thread of its own so it never blocks the test's cooperative thread.
///
/// `app.shutdown()` itself cannot be used: on an `Application.make` app it leaves
/// Vapor's own serve command running and traps.
private func shutDownSynchronously(_ transport: some PushTransport, of app: Application) async {
    let handler = PushServiceShutdown(service: PushService(transport: transport, onRetiredToken: { _ in }))
    await withCheckedContinuation { continuation in
        Thread.detachNewThread {
            handler.shutdown(app)
            continuation.resume()
        }
    }
}

private extension PushNotificationsError {
    var deliveryFailures: (failures: [any Error], attempted: Int)? {
        if case .deliveryFailed(let failures, let attempted) = self {
            return (failures, attempted)
        }
        return nil
    }

    var isNotConfigured: Bool {
        if case .notConfigured = self {
            return true
        }
        return false
    }

    var isAlreadyConfigured: Bool {
        if case .alreadyConfigured = self {
            return true
        }
        return false
    }

    var isPayloadNotAnObject: Bool {
        if case .payloadNotAnObject = self {
            return true
        }
        return false
    }

    var isPayloadUsesAPSKey: Bool {
        if case .payloadUsesAPSKey = self {
            return true
        }
        return false
    }

    var isInvalidPrivateKey: Bool {
        if case .invalidPrivateKey = self {
            return true
        }
        return false
    }
}

private extension Error {
    var isMissingTranslation: Bool {
        if case .missingTranslation = self as? LocalizerError {
            return true
        }
        return false
    }
}

private extension PushNotification {
    static let cardAssigned = PushNotification(
        title: LocalizableString.localized(key: "PushTest.title"),
        body: LocalizableString.localized(key: "PushTest.body"),
        sound: .default
    )
}

private struct CardAssignedPayload: Codable, Equatable, Sendable {
    let boardName: String
    let unreadCount: Int
}

private func encodedRoot(_ payload: PushPayload) throws -> [String: Any] {
    let data = try JSONEncoder().encode(payload)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private extension Locale {
    static let en = Locale(identifier: "en")
    static let es = Locale(identifier: "es")
}

private struct Device: PushDestination {
    let deviceToken: String
    let topic: String
    let environment: PushEnvironment
    let locale: Locale

    init(token: String, topic: String = "com.example.boards", environment: PushEnvironment = .production, locale: Locale = .en) {
        self.deviceToken = token
        self.topic = topic
        self.environment = environment
        self.locale = locale
    }
}

private actor RecordingTransport: PushTransport {
    struct Sent {
        let payload: PushPayload
        let topic: String
        let environment: PushEnvironment
    }

    private(set) var sentByToken: [String: Sent] = [:]
    private(set) var isShutDown = false
    private let retiredTokens: Set<String>
    private let failingTokens: Set<String>

    init(retiredTokens: Set<String> = [], failingTokens: Set<String> = []) {
        self.retiredTokens = retiredTokens
        self.failingTokens = failingTokens
    }

    func deliver(
        _ payload: PushPayload,
        to deviceToken: String,
        topic: String,
        environment: PushEnvironment
    ) async throws -> PushDeliveryResult {
        if failingTokens.contains(deviceToken) {
            throw Abort(.serviceUnavailable)
        }
        if retiredTokens.contains(deviceToken) {
            return .retired
        }
        sentByToken[deviceToken] = Sent(payload: payload, topic: topic, environment: environment)
        return .delivered
    }

    func shutdown() async throws {
        isShutDown = true
    }
}

private actor RetiredTokens {
    private(set) var tokens: [String] = []

    func append(_ token: String) {
        tokens.append(token)
    }
}

private func withPushApp(
    localized: Bool = true,
    retiredTokens: Set<String> = [],
    failingTokens: Set<String> = [],
    _ body: (Application, RecordingTransport, RetiredTokens) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    let transport = RecordingTransport(retiredTokens: retiredTokens, failingTokens: failingTokens)
    let retired = RetiredTokens()
    do {
        if localized {
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
        }
        try app.pushNotifications.configure(transport: transport) { token in
            await retired.append(token)
        }
        // The YAML store loads in an async lifecycle handler.
        try await app.asyncBoot()
        try await body(app, transport, retired)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
#endif
