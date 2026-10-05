// PushNotification.swift
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
import FOSMVVM
import Foundation

/// A notification to show on your users' devices
///
/// Build one with the words, badge, sound and interruption level you want, then send
/// it with ``PushNotificationService/send(_:to:)``:
///
/// ```swift
/// let notification = PushNotification(
///     title: LocalizableString.localized(key: "CardAssigned.title"),
///     body: LocalizableString.localized(key: "CardAssigned.body")
///         .bind(substitutions: ["boardName": LocalizableString.constant(board.name)]),
///     badge: unreadCount,
///     sound: .default,
///     interruptionLevel: .timeSensitive
/// )
/// try await app.pushNotifications.send(notification, to: devices)
/// ```
///
/// The title and body can be any `Localizable`. They are looked up in your server's
/// localization YAML once per destination, in that destination's
/// ``PushDestination/locale``, with their substitutions filled in:
///
/// ```yaml
/// en:
///   CardAssigned:
///     title: "New card"
///     body: "A card on %{boardName} was assigned to you"
/// ```
///
/// Leave out the title and body to update only the app icon's badge. Add
/// `contentAvailable: true` to also wake the app in the background, for example to
/// refresh a tvOS app's content:
///
/// ```swift
/// let tvRefresh = PushNotification(badge: unreadCount, contentAvailable: true)
/// ```
///
/// Give the app the data it needs as a `payload` of your own `Codable` type. It
/// arrives beside the notification's text, and the app decodes it with the same type:
///
/// ```swift
/// struct CardAssignedPayload: Codable, Sendable {
///     let boardName: String
/// }
///
/// let assigned = PushNotification(
///     title: LocalizableString.localized(key: "CardAssigned.title"),
///     payload: CardAssignedPayload(boardName: board.name)
/// )
/// ```
///
/// ```swift
/// // On the device, in your UNUserNotificationCenterDelegate
/// let data = try JSONSerialization.data(withJSONObject: response.notification.request.content.userInfo)
/// let payload = try JSONDecoder().decode(CardAssignedPayload.self, from: data)
/// ```
///
/// > Tip: tvOS shows only the badge, so send badge-only notifications to tvOS apps.
///
/// > Note: How urgent a notification is belongs to your app. Map your own kinds of
/// > alert to ``InterruptionLevel`` when you build each notification.
///
/// > Important: The payload must encode as a keyed object (a `struct` or a dictionary)
/// > and must not use the key `aps`, which belongs to Apple. Otherwise
/// > ``PushNotificationService/send(_:to:)`` throws before contacting Apple.
public struct PushNotification: Sendable {
    /// How strongly the notification may interrupt the user
    ///
    /// ```swift
    /// let level: PushNotification.InterruptionLevel = alert.isUrgent ? .timeSensitive : .passive
    /// ```
    public enum InterruptionLevel: Hashable, CaseIterable, Sendable {
        /// Added to the notification list silently; never lights the screen
        case passive

        /// Presented immediately, lighting the screen and playing a sound if one is set
        case active

        /// Presented immediately, breaking through Focus and scheduled summaries
        case timeSensitive

        /// Presented immediately, breaking through Focus and the mute switch
        ///
        /// > Important: Critical alerts need Apple's Critical Alerts entitlement in the
        /// > receiving app. Without it, the device presents the notification at a lower
        /// > level.
        case critical
    }

    /// The sound played when the notification is presented
    ///
    /// ```swift
    /// let sound: PushNotification.Sound = .named("card-assigned.caf")
    /// ```
    public enum Sound: Hashable, Sendable {
        /// The system's default notification sound
        case `default`

        /// A sound file in the receiving app's bundle or its `Library/Sounds` folder
        case named(_ fileName: String)
    }

    /// The number shown on the app's icon; `0` removes the badge, `nil` leaves it as it is
    public var badge: Int?

    /// The sound to play, or `nil` for a silent notification
    public var sound: Sound?

    /// How strongly the notification may interrupt the user
    public var interruptionLevel: InterruptionLevel

    /// When **true**, the app is woken in the background to fetch new content
    public var contentAvailable: Bool

    let title: LocalizedText?
    let body: LocalizedText?
    let payload: AppPayload?

    /// Creates a notification
    ///
    /// ```swift
    /// let assigned = PushNotification(
    ///     title: LocalizableString.localized(key: "CardAssigned.title"),
    ///     body: LocalizableString.localized(key: "CardAssigned.body")
    ///         .bind(substitutions: ["boardName": LocalizableString.constant(board.name)]),
    ///     sound: .default,
    ///     payload: CardAssignedPayload(boardName: board.name)
    /// )
    /// let refresh = PushNotification(badge: unreadCount, contentAvailable: true)
    /// ```
    ///
    /// > Note: Name the type of a title or body, as in `LocalizableString.localized(key:)`;
    /// > they accept any `Localizable`, so a bare `.localized(key:)` has no type to
    /// > resolve against.
    ///
    /// - Parameters:
    ///   - title: The bold line, localized per destination (default: none)
    ///   - body: The text, localized per destination (default: none)
    ///   - badge: The number shown on the app's icon (default: unchanged)
    ///   - sound: The sound to play (default: silent)
    ///   - interruptionLevel: How strongly it may interrupt (default: ``InterruptionLevel/active``)
    ///   - contentAvailable: Wake the app in the background (default: **false**)
    ///   - payload: Your app's data, delivered beside the notification (default: none)
    public init(
        title: (some Localizable)? = LocalizableString?.none,
        body: (some Localizable)? = LocalizableString?.none,
        badge: Int? = nil,
        sound: Sound? = nil,
        interruptionLevel: InterruptionLevel = .active,
        contentAvailable: Bool = false,
        payload: (some Encodable & Sendable)? = Never?.none
    ) {
        self.title = title.map(LocalizedText.init)
        self.body = body.map(LocalizedText.init)
        self.badge = badge
        self.sound = sound
        self.interruptionLevel = interruptionLevel
        self.contentAvailable = contentAvailable
        self.payload = payload.map(AppPayload.init)
    }
}

extension PushNotification {
    /// A title or body, resolved for one destination's locale when sent
    struct LocalizedText: Sendable {
        let localize: @Sendable (Locale, any LocalizationStore) throws -> String

        init(_ text: some Localizable) {
            self.localize = { locale, store in
                // Strict: a missing translation fails this destination instead of sending
                // a blank alert. The round trip is the client's path, so every Localizable
                // resolves exactly as it does in a response.
                let encoder = JSONEncoder.localizingEncoder(in: locale, store: store, strictLocalization: true)
                return try JSONDecoder().decode(type(of: text), from: encoder.encode(text)).localizedString
            }
        }
    }

    /// The app's own payload, encoded beside the `aps` dictionary
    struct AppPayload: Sendable {
        let encode: @Sendable (any Encoder) throws -> Void

        init(_ payload: some Encodable & Sendable) {
            self.encode = { try payload.encode(to: $0) }
        }
    }
}
#endif
