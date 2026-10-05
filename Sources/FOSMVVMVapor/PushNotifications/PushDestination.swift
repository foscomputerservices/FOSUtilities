// PushDestination.swift
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

/// One app install that can receive a push notification
///
/// Conform the row your server stores for each registered device token, then pass
/// the rows you choose as recipients to ``PushNotificationService/send(_:to:)``:
///
/// ```swift
/// final class MemberDevice: Model, PushDestination, @unchecked Sendable {
///     static let schema = "member_devices"
///
///     @ID(key: .id) var id: UUID?
///     @Parent(key: "member_id") var member: Member
///     @Field(key: "device_token") var deviceToken: String
///     @Field(key: "topic") var topic: String
///     @Field(key: "environment") var environment: PushEnvironment
///     @Field(key: "locale") var locale: Locale
///
///     init() {}
/// }
/// ```
///
/// Your app's register request writes the row: the token, its app's bundle identifier
/// as the topic, the APNs environment the app was signed for, and the app's language.
/// The table, what a token belongs to, and when a row is deleted are yours.
///
/// > Note: Notification text is localized into ``locale`` for each destination, so a
/// > row registered from a French app receives French text.
public protocol PushDestination {
    /// The device token the app received from Apple, as hexadecimal text
    var deviceToken: String { get }

    /// The bundle identifier of the app that registered ``deviceToken``
    var topic: String { get }

    /// The APNs environment ``deviceToken`` belongs to
    var environment: PushEnvironment { get }

    /// The language notification text is localized into for this destination
    var locale: Locale { get }
}
#endif
