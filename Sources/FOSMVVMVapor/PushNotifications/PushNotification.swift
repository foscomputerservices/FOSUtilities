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
/// it with ``PushNotifications/send(_:to:)``:
///
/// ```swift
/// let notification = PushNotification(
///     title: .localized(key: "CardAssigned.title"),
///     body: .localized(key: "CardAssigned.body"),
///     badge: unreadCount,
///     sound: .default,
///     interruptionLevel: .timeSensitive
/// )
/// try await app.pushNotifications.send(notification, to: devices)
/// ```
///
/// The title and body are looked up in your server's localization YAML, once per
/// destination, in that destination's ``PushDestination/locale``:
///
/// ```yaml
/// en:
///   CardAssigned:
///     title: "New card"
///     body: "A card was assigned to you"
/// ```
///
/// Leave out the title and body to update only the app icon's badge:
///
/// ```swift
/// let badgeOnly = PushNotification(badge: unreadCount)
/// ```
///
/// > Tip: tvOS shows only the badge, so send badge-only notifications to tvOS apps.
///
/// > Note: How urgent a notification is belongs to your app. Map your own kinds of
/// > alert to ``InterruptionLevel`` when you build each notification.
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

    /// The bold line of the notification, or `nil` for none
    public var title: LocalizableString?

    /// The text of the notification, or `nil` for none
    public var body: LocalizableString?

    /// The number shown on the app's icon; `0` removes the badge, `nil` leaves it as it is
    public var badge: Int?

    /// The sound to play, or `nil` for a silent notification
    public var sound: Sound?

    /// How strongly the notification may interrupt the user
    public var interruptionLevel: InterruptionLevel

    /// Creates a notification
    ///
    /// ```swift
    /// let assigned = PushNotification(
    ///     title: .localized(key: "CardAssigned.title"),
    ///     body: .localized(key: "CardAssigned.body"),
    ///     sound: .default
    /// )
    /// let badgeOnly = PushNotification(badge: unreadCount)
    /// ```
    ///
    /// - Parameters:
    ///   - title: The bold line, localized per destination (default: none)
    ///   - body: The text, localized per destination (default: none)
    ///   - badge: The number shown on the app's icon (default: unchanged)
    ///   - sound: The sound to play (default: silent)
    ///   - interruptionLevel: How strongly it may interrupt (default: ``InterruptionLevel/active``)
    public init(
        title: LocalizableString? = nil,
        body: LocalizableString? = nil,
        badge: Int? = nil,
        sound: Sound? = nil,
        interruptionLevel: InterruptionLevel = .active
    ) {
        self.title = title
        self.body = body
        self.badge = badge
        self.sound = sound
        self.interruptionLevel = interruptionLevel
    }
}
#endif
