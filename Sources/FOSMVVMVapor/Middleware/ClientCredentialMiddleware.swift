// ClientCredentialMiddleware.swift
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
import Vapor

/// Decides whether a request's presented credential admits it
///
/// A ``ServerCredentialVerifier`` is the validity rule that ``ClientCredentialMiddleware``
/// runs before each route in a protected group: return to admit the request, throw to
/// reject it — throw ``CredentialRejectedError`` (carrying its code + challenge) to
/// reject; any other thrown error is wrapped by the middleware into
/// `CredentialRejectedError(code: .invalid)`. Rejection reasons must **never** echo
/// the presented credential back to the caller.
///
/// The verifier is consulted **per request**, so a credential revoked or rotated on the
/// server side takes effect on the very next call — mirroring how the client's
/// `ClientCredentialProvider` resolves its credential per request.
///
/// Use the stock ``BearerCredentialVerifier`` for standard `Authorization: Bearer`
/// authentication, or conform your own type for any other credential scheme.
public protocol ServerCredentialVerifier: Sendable {
    /// Admits or rejects the request presenting these headers
    ///
    /// Called once per request before the route runs.
    ///
    /// - Parameter headers: The HTTP headers the request presented
    /// - Throws: To reject the request — throw ``CredentialRejectedError``
    ///     (carrying code + challenge); any other thrown error is wrapped by
    ///     the middleware into `CredentialRejectedError(code: .invalid)`. The
    ///     rejection reason must not contain the presented credential
    func verify(headers: HTTPHeaders) async throws
}

/// A Vapor *Middleware* implementation that runs a ``ServerCredentialVerifier``
/// before the route
///
/// ``ClientCredentialMiddleware`` is the server half of the credential pair: the client
/// attaches its credential to every *ServerRequest* through a `ClientCredentialProvider`
/// registered on `MVVMEnvironment`, and this middleware verifies that credential before
/// any route in the protected group runs. The validity rule itself — which credentials
/// are currently good — is supplied by the application through the verifier.
///
/// ## Client-Side Contract
///
/// On a FOSMVVM client, a rejection surfaces from
/// `processRequest(mvvmEnv:)` as `CredentialRejectedError` — the same typed
/// error whether the request's own `ResponseError` is `EmptyError` or a
/// custom type. Catch it to recover; see ``CredentialRejectedError``.
///
/// ## Example
///
/// ```swift
/// func routes(_ app: Application) throws {
///     // MARK: Credentialed Routes
///
///     let protectedGroup = app.grouped(
///         ClientCredentialMiddleware(verifier: BearerCredentialVerifier { token in
///             await tokens.isCurrent(token)
///         })
///     )
///     try protectedGroup.register(collection: MyController())
/// }
/// ```
public struct ClientCredentialMiddleware: AsyncMiddleware {
    private let verifier: any ServerCredentialVerifier

    // MARK: Middleware Protocol

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Ensure that the presented credential admits the request
        do {
            try await verifier.verify(headers: request.headers)
        } catch let rejection as CredentialRejectedError {
            throw rejection
        } catch is CancellationError {
            // Cancellation is a control-flow signal, not a domain rejection —
            // the "throw to reject" contract covers domain failures.
            throw CancellationError()
        } catch {
            // The verifier contract is "throw to reject" — any throw is a
            // rejection; custom verifiers throw CredentialRejectedError
            // directly to carry richer intent (code, challenge).
            throw CredentialRejectedError(code: .invalid)
        }

        return try await next.respond(to: request)
    }

    // MARK: Initialization Methods

    /// Create a new ``ClientCredentialMiddleware``
    ///
    /// - Parameter verifier: The validity rule run against each request's
    ///     presented credential
    public init(verifier: any ServerCredentialVerifier) {
        self.verifier = verifier
    }
}

/// The stock ``ServerCredentialVerifier`` for `Authorization: Bearer` authentication
///
/// ``BearerCredentialVerifier`` is the matched pair of the client's
/// `BearerCredentialProvider`: the provider attaches `Authorization: Bearer <token>`
/// to every request; this verifier extracts that token and asks the application
/// whether it is currently valid. A missing `Authorization` header or an invalid
/// token rejects the request with `401 Unauthorized` carrying
/// `WWW-Authenticate: Bearer` (RFC 7235) — never echoing the presented token.
///
/// The `isValid` closure is consulted on **every** request, so answer from wherever
/// the application keeps its live token set (a session store, a database, a
/// revocation list) and rotation is handled automatically.
///
/// ## Example
///
/// ```swift
/// let verifier = BearerCredentialVerifier { token in
///     await tokens.isCurrent(token)
/// }
/// ```
public struct BearerCredentialVerifier: ServerCredentialVerifier {
    private static let challenge = "Bearer"

    private let isValid: @Sendable (String) async -> Bool

    // MARK: ServerCredentialVerifier Protocol

    public func verify(headers: HTTPHeaders) async throws {
        guard let token = headers.bearerAuthorization?.token else {
            throw CredentialRejectedError(code: .missing, challenge: Self.challenge)
        }

        guard await isValid(token) else {
            throw CredentialRejectedError(code: .invalid, challenge: Self.challenge)
        }
    }

    // MARK: Initialization Methods

    /// Initializes the ``BearerCredentialVerifier``
    ///
    /// - Parameter isValid: Answers whether the presented bearer token is currently
    ///     valid; called once per request. When comparing against stored secret
    ///     material, compare in constant time or compare digests — a plain `==`
    ///     on secrets leaks timing
    public init(isValid: @Sendable @escaping (String) async -> Bool) {
        self.isValid = isValid
    }
}
