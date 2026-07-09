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

import Vapor

/// Decides whether a request's presented credential admits it
///
/// A ``ServerCredentialVerifier`` is the validity rule that ``ClientCredentialMiddleware``
/// runs before each route in a protected group: return to admit the request, throw to
/// reject it — typically `Abort(.unauthorized)`. Rejection reasons must **never** echo
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
    /// - Throws: To reject the request — typically `Abort(.unauthorized)`; the
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
/// On a FOSMVVM client, a rejection surfaces from `processRequest(mvvmEnv:)` as
/// FOSFoundation's `DataFetchError.badStatus(httpStatusCode: 401)` — not as the
/// request's typed `ResponseError` — so `MVVMEnvironment.requestErrorHandler` is
/// bypassed and the error propagates directly to the caller. This contract requires
/// an installed error serializer that forwards the `Abort`'s status and headers;
/// FOS ``ErrorMiddleware`` (`.default(environment:)`) does.
///
/// Known limitation: a request whose `ResponseError` decodes from the rejection body
/// swallows the 401 into a typed error instead. `EmptyError` **always** does — an
/// empty struct's synthesized decode is a no-op, so it decodes from ANY valid-JSON
/// rejection body (FOS ``ErrorMiddleware``'s JSON string and Vapor's stock JSON
/// object alike). A pre-existing `DataFetch` property, noted here because this
/// middleware is the first consumer depending on 401 visibility: a request that must
/// observe the 401 needs a `ResponseError` with at least one required field absent
/// from rejection bodies.
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
        try await verifier.verify(headers: request.headers)

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
    private let isValid: @Sendable (String) async -> Bool

    // MARK: ServerCredentialVerifier Protocol

    public func verify(headers: HTTPHeaders) async throws {
        guard let token = headers.bearerAuthorization?.token else {
            throw Abort(
                .unauthorized,
                headers: ["WWW-Authenticate": "Bearer"],
                reason: "Missing bearer credential"
            )
        }

        guard await isValid(token) else {
            throw Abort(
                .unauthorized,
                headers: ["WWW-Authenticate": "Bearer"],
                reason: "Invalid bearer credential"
            )
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
