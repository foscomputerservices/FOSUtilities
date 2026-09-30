// ModelAuthorizationProvider.swift
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

/// Supplies the current subject's grants for a request — conform once, register at boot, and
/// every framework load is scoped by what you return.
///
/// ```swift
/// struct GrantProvider: ModelAuthorizationProvider {
///     func modelAuthorizations(for request: Request) async throws -> [Grant] {
///         // however your app resolves the subject — session, token, headers…
///         let userId = try request.auth.require(SessionUser.self).id
///         return try await UserGrantRow.query(on: request.db)
///             .filter(\.$user.$id == userId).all()
///             .map(\.snapshot)                       // project Sendable value snapshots
///     }
///
///     func subjectIdentity(for request: Request) async throws -> ModelIdentity? {
///         try request.auth.require(SessionUser.self).modelIdentity
///     }
/// }
/// ```
///
/// The framework fetches through your provider when first needed and reuses the result for every load
/// in that request — return the **complete** grant set, never a per-model slice. Return `[]` for
/// an unauthenticated or unprivileged subject: they simply load empty sets (routes stay
/// authentication-only; data access is enforced by scoping, never by route guards).
public protocol ModelAuthorizationProvider: Sendable {
    /// Your app's grant value (see ``ModelAuthorization`` for the conformance pattern).
    associatedtype Authorization: ModelAuthorization

    /// The current subject's complete grant set for this request.
    func modelAuthorizations(for request: Request) async throws -> [Authorization]

    /// The identity of the subject whose grants this request carries, so a load within the
    /// subject scope refreshes live when that subject's grants change:
    ///
    /// ```swift
    /// func subjectIdentity(for request: Request) async throws -> ModelIdentity? {
    ///     try request.auth.require(SessionUser.self).modelIdentity
    /// }
    /// ```
    ///
    /// Declare your grant model as contained by the subject — `.children(\User.$grants)` — and a
    /// written grant nudges every live list within the subject scope for that subject. The default
    /// answers `nil`: grant changes then reach a client on its next fetch.
    func subjectIdentity(for request: Request) async throws -> ModelIdentity?

    /// The grant set under its former name. Conform with ``modelAuthorizations(for:)`` instead.
    @available(*, deprecated, renamed: "modelAuthorizations(for:)")
    func containerAuthorizations(for request: Request) async throws -> [Authorization]
}

public extension ModelAuthorizationProvider {
    func subjectIdentity(for _: Request) async throws -> ModelIdentity? {
        nil
    }

    /// Declare ``modelAuthorizations(for:)``. A provider still declaring the former
    /// `containerAuthorizations(for:)` answers through it; one declaring neither fails at its
    /// first request, by name.
    @available(*, deprecated, message: "declare modelAuthorizations(for:); this default forwards from the former containerAuthorizations(for:)")
    func modelAuthorizations(for request: Request) async throws -> [Authorization] {
        try await containerAuthorizations(for: request)
    }

    @available(*, deprecated, renamed: "modelAuthorizations(for:)")
    func containerAuthorizations(for _: Request) async throws -> [Authorization] {
        // Reached only by a provider declaring neither spelling — the trap is the compile error a
        // protocol cannot express for "one of two".
        preconditionFailure("\(Self.self) declares neither modelAuthorizations(for:) nor containerAuthorizations(for:) — declare modelAuthorizations(for:)")
    }
}

/// The former name of ``ModelAuthorizationProvider``.
@available(*, deprecated, renamed: "ModelAuthorizationProvider")
public typealias ContainerAuthorizationProvider = ModelAuthorizationProvider
