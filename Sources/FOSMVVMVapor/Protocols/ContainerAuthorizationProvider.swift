// ContainerAuthorizationProvider.swift
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

import FOSMVVM
import Foundation
import Vapor

/// Supplies the current subject's container authorizations for a request — conform once, register at
/// boot, and every framework load is scoped by what you return.
///
/// ```swift
/// struct GrantProvider: ContainerAuthorizationProvider {
///     func containerAuthorizations(for request: Request) async throws -> [DockGrant] {
///         // however your app resolves the subject — session, token, headers…
///         let userId = try request.auth.require(SessionUser.self).id
///         return try await UserDockGrantRow.query(on: request.db)
///             .filter(\.$user.$id == userId).all()
///             .map(\.snapshot)                       // project Sendable value snapshots
///     }
/// }
/// ```
///
/// The framework fetches through your provider when first needed and reuses the result for every load
/// in that request — return the **complete** grant set, never a per-container slice. Return `[]` for
/// an unauthenticated or unprivileged subject: they simply load empty sets (routes stay
/// authentication-only; data access is enforced by scoping, never by route guards).
public protocol ContainerAuthorizationProvider: Sendable {
    /// Your app's authorization value (see ``ContainerAuthorization`` for the conformance pattern).
    associatedtype Authorization: ContainerAuthorization
    /// The current subject's complete authorization set for this request.
    func containerAuthorizations(for request: Request) async throws -> [Authorization]
}
