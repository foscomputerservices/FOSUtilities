// ClientCredentialProvider.swift
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

/// Supplies the authentication headers that accompany every ``ServerRequest``
///
/// Register a ``ClientCredentialProvider`` on ``MVVMEnvironment`` and every
/// `processRequest(mvvmEnv:)` call attaches the provider's headers automatically —
/// no per-request plumbing in application code.
///
/// The provider is consulted **per request**, so a credential that rotates (a
/// refreshed access token, a re-issued session) is picked up on the very next
/// call. When the client is unauthenticated, return an empty array and the
/// request proceeds without authentication headers.
///
/// ``ClientCredentialProvider`` is the *dynamic* sibling of the static
/// ``MVVMEnvironment/requestHeaders``: use `requestHeaders` for values fixed for
/// the life of the application, and a credential provider for values that must be
/// resolved at request time. On a duplicate header field, the provider's value wins.
///
/// Use the stock ``BearerCredentialProvider`` for standard `Authorization: Bearer`
/// authentication, or conform your own type for any other credential scheme.
///
/// ## Example
///
/// ```swift
/// let environment = MVVMEnvironment(
///     appBundle: Bundle.main,
///     clientCredentialProvider: BearerCredentialProvider {
///         await SessionStore.shared.accessToken
///     },
///     deploymentURLs: [
///         .production: URL(string: "https://api.mywebserver.com")!,
///         .debug: URL(string: "http://localhost:8080")!
///     ]
/// )
/// ```
public protocol ClientCredentialProvider: Sendable {
    /// The authentication headers for the next request; empty when unauthenticated
    ///
    /// Called once per ``ServerRequest`` immediately before the request is sent,
    /// so the returned headers always reflect the current credential.
    ///
    /// - Returns: HTTP header fields to attach to the request; an empty array
    ///     sends the request unauthenticated
    /// - Throws: When the credential cannot be resolved; no request is sent and the
    ///     error propagates from `processRequest` to the caller —
    ///     ``MVVMEnvironment/requestErrorHandler`` handles only typed
    ///     `ServerRequestError`s
    func credentialHeaders() async throws -> [(field: String, value: String)]

    /// The replacement headers to retry with after the server refused the last set
    ///
    /// Called when a request fails with ``CredentialRejectedError``. Refresh your
    /// credential and return its headers to have the request retried once with
    /// them; return `nil` — the default — and the rejection throws to the caller
    /// unchanged.
    ///
    /// ```swift
    /// func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
    ///     guard afterRejection.code == .invalid else { return nil }
    ///     guard let token = await SessionStore.shared.refreshAccessToken() else { return nil }
    ///     return [(field: "Authorization", value: "Bearer \(token)")]
    /// }
    /// ```
    ///
    /// - Important: **Persist the refreshed credential** — returning it is not enough.
    ///     The returned headers are used for this one retry; every later request, and
    ///     every live-channel reconnect, calls ``credentialHeaders()`` instead. A
    ///     provider that returns a fresh credential without storing it keeps handing
    ///     out the refused one.
    /// - Important: Several screens can be refused at once — each bound ViewModel
    ///     issues its own request and is refused independently. Coalesce concurrent
    ///     refreshes (single-flight) inside your provider; this method may be called
    ///     several times in quick succession with the same rejection.
    /// - Parameter afterRejection: The rejection the server returned, so a provider
    ///     can distinguish a missing credential from an invalid one. A refused
    ///     ServerRequest carries the server's actual code; a refused live-channel
    ///     reconnect cannot read it and always presents `.invalid`, and may call
    ///     this once per failed reconnect rather than only once.
    /// - Returns: Headers to retry the request with once, or `nil` when no fresh
    ///     credential is available — the rejection then throws to the caller
    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]?
}

public extension ClientCredentialProvider {
    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        // A *requirement* with a default, not an extension-only method: `MVVMEnvironment`
        // holds the provider as `(any ClientCredentialProvider)?`, and an extension-only
        // method binds to the default through the existential — the override would never run.
        nil
    }
}

/// The stock ``ClientCredentialProvider`` for `Authorization: Bearer` authentication
///
/// Supply a closure that yields the current token; the provider formats the
/// `Authorization` header for you. The closure is consulted on **every** request,
/// so return the token from wherever your application keeps it current (a session
/// store, a keychain, a refresh flow) and rotation is handled automatically.
///
/// When the closure yields `nil` — the user is signed out, no token has been
/// issued yet — no headers are produced and the request proceeds unauthenticated.
///
/// This provider never refreshes on rejection: a refused credential throws to the
/// caller. To recover from server-side rotation, conform your own type and implement
/// ``ClientCredentialProvider/credentialHeaders(afterRejection:)``.
///
/// ## Example
///
/// ```swift
/// let provider = BearerCredentialProvider {
///     await SessionStore.shared.accessToken
/// }
/// ```
public struct BearerCredentialProvider: ClientCredentialProvider {
    private let token: @Sendable () async -> String?

    /// Initializes the ``BearerCredentialProvider``
    ///
    /// - Parameter token: Yields the current bearer token, or `nil` when
    ///     unauthenticated; called once per request
    public init(token: @Sendable @escaping () async -> String?) {
        self.token = token
    }

    public func credentialHeaders() async throws -> [(field: String, value: String)] {
        guard let token = await token() else {
            return []
        }

        return [(field: "Authorization", value: "Bearer \(token)")]
    }
}
