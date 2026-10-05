// PushConfiguration.swift
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
import Foundation

/// Your APNs signing key and what to do when Apple retires a device token
///
/// Read the key from your server's own environment at boot, never from source, and
/// pass the configuration to ``PushNotifications/configure(_:)``:
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
/// The key is the contents of the `.p8` file you download from the Keys section of
/// your Apple Developer account; the key id and team id are shown beside it. One key
/// signs for every app of your team, in both ``PushEnvironment`` cases.
///
/// `onRetiredToken` is called with a device token Apple reports it will never deliver
/// to again: the app was deleted, or the token was replaced. Delete the stored row
/// there, so later sends skip it.
public struct PushConfiguration: Sendable {
    let privateKey: String
    let keyId: String
    let teamId: String
    let onRetiredToken: @Sendable (String) async throws -> Void

    /// Creates the configuration
    ///
    /// ```swift
    /// let configuration = PushConfiguration(
    ///     privateKey: Environment.get("APNS_PRIVATE_KEY")!,
    ///     keyId: Environment.get("APNS_KEY_ID")!,
    ///     teamId: Environment.get("APNS_TEAM_ID")!,
    ///     onRetiredToken: { deviceToken in
    ///         try await MemberDevice.query(on: app.db)
    ///             .filter(\.$deviceToken == deviceToken)
    ///             .delete()
    ///     }
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - privateKey: The contents of your APNs `.p8` key file
    ///   - keyId: The key's identifier, shown beside the key in your developer account
    ///   - teamId: Your Apple Developer team identifier
    ///   - onRetiredToken: Called with each device token Apple has retired; delete its row here
    public init(
        privateKey: String,
        keyId: String,
        teamId: String,
        onRetiredToken: @escaping @Sendable (String) async throws -> Void
    ) {
        self.privateKey = privateKey
        self.keyId = keyId
        self.teamId = teamId
        self.onRetiredToken = onRetiredToken
    }
}
#endif
