// ClientCredentialMiddlewareTests.swift
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

// Behavior contract of `ClientCredentialMiddleware` — the server half of the credential
// pair (`ClientCredentialProvider` attaches; this verifies) — against a REAL running
// server so the observed status codes are exactly what a client sees on the wire:
//   • a valid bearer credential admits the request — the route runs,
//   • a missing or invalid credential is rejected 401, WITHOUT echoing the
//     presented token back to the caller,
//   • any custom `ServerCredentialVerifier` conformance is honored (the protocol
//     seam, not just the stock bearer verifier),
//   • the verifier is consulted PER REQUEST, so a credential revoked between two
//     requests admits the first and rejects the second (rotation semantics,
//     mirroring the client side),
//   • rejections carry `WWW-Authenticate: Bearer` (RFC 7235) on the wire,
//   • the Authorization parse edges are pinned: a lowercase `bearer` scheme admits;
//     an empty token (`Bearer `) rejects,
//   • the CLIENT-SIDE contract: through the REAL client (`processRequest(mvvmEnv:)`)
//     with FOS `ErrorMiddleware.default` installed, a rejection surfaces TYPED as
//     `CredentialRejectedError` (`.invalid`) — the wrapper claims the rejection body
//     before the request's own `ResponseError` decode runs, so:
//       - an `EmptyError` `ResponseError` no longer swallows the 401 (the retired
//         gotcha) — the typed rejection wins,
//       - a permissive custom `ResponseError` (an all-optional shape that decodes
//         from any JSON object) likewise cannot swallow it,
//   • the rejection THROWS PAST `requestErrorHandler` — recovery (refresh, retry) is a
//     call-site decision — while an operation's own `ResponseError` still routes to the
//     handler (the positive half),
//   • skew fallback: a plain 401 WITHOUT the self-identifying envelope (an old server,
//     Vapor's stock middleware) still surfaces as `DataFetchError.badStatus(401)`,
//     unchanged.

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

@Suite("ClientCredentialMiddleware (verifier ↔ running server)", .serialized)
struct ClientCredentialMiddlewareTests {
    @Test("A valid bearer credential admits the request — the route runs")
    func validBearerAdmits() async throws {
        try await withRunningServer { app in
            Self.registerProtectedRoute(app, isValid: { $0 == "current-token" })
        } _: { base in
            let reply = try await Self.send(
                to: base,
                headers: ["Authorization": "Bearer current-token"]
            )

            #expect(reply.status == 200)
            #expect(reply.body == "granted")
        }
    }

    @Test("A missing Authorization header is rejected 401 — the route never runs")
    func missingAuthorizationRejects() async throws {
        try await withRunningServer { app in
            Self.registerProtectedRoute(app, isValid: { _ in true })
        } _: { base in
            let reply = try await Self.send(to: base, headers: [:])

            #expect(reply.status == 401)
            #expect(reply.body != "granted")
            // RFC 7235: the challenge header reaches the wire
            #expect(reply.wwwAuthenticate == "Bearer")
        }
    }

    @Test("An invalid token is rejected 401 and the response never echoes the token")
    func invalidTokenRejectsWithoutEchoingToken() async throws {
        let presentedToken = "stolen-or-expired-token"

        try await withRunningServer { app in
            Self.registerProtectedRoute(app, isValid: { _ in false })
        } _: { base in
            let reply = try await Self.send(
                to: base,
                headers: ["Authorization": "Bearer \(presentedToken)"]
            )

            #expect(reply.status == 401)
            #expect(!reply.body.contains(presentedToken))
            // RFC 7235: the challenge header reaches the wire
            #expect(reply.wwwAuthenticate == "Bearer")
        }
    }

    @Test("A lowercase bearer scheme admits — the Authorization parse is scheme-case-insensitive")
    func lowercaseBearerSchemeAdmits() async throws {
        try await withRunningServer { app in
            Self.registerProtectedRoute(app, isValid: { $0 == "current-token" })
        } _: { base in
            let reply = try await Self.send(
                to: base,
                headers: ["Authorization": "bearer current-token"]
            )

            #expect(reply.status == 200)
            #expect(reply.body == "granted")
        }
    }

    @Test("An empty bearer token is rejected 401 — even against an always-true validity rule")
    func emptyBearerTokenRejects() async throws {
        try await withRunningServer { app in
            Self.registerProtectedRoute(app, isValid: { _ in true })
        } _: { base in
            let reply = try await Self.send(
                to: base,
                headers: ["Authorization": "Bearer "]
            )

            #expect(reply.status == 401)
            #expect(reply.body != "granted")
        }
    }

    @Test("On a FOSMVVM client, a rejection surfaces as the typed CredentialRejectedError")
    func rejectionSurfacesTypedToTheClient() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowStrictErrorReplyRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError, but the request succeeded")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }

            #expect(request.responseBody == nil)
        }
    }

    @Test("With no credential provider configured, a rejection surfaces typed as .missing")
    func missingCredentialSurfacesTypedToTheClient() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
        } _: { base in
            let env = Self.environment(base: base) // no clientCredentialProvider

            let request = ShowStrictErrorReplyRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .missing)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }
        }
    }

    @Test("EmptyError no longer swallows a rejection — the typed error wins")
    func emptyErrorNoLongerSwallowsRejections() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowGrantedReplyRequest() // ResponseError == EmptyError
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError, but the request succeeded")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error) — the swallow is back")
            }
        }
    }

    @Test("A rejection bypasses requestErrorHandler; operation errors still route to it")
    func rejectionBypassesRequestErrorHandler() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
            // ADMITTED route whose controller throws an operation error — the
            // positive half: ordinary ResponseErrors still route to the handler.
            try Self.registerAdmittedThrowingRoute(app)
        } _: { base in
            let handled = ErrorSink() // synchronous, lock-guarded — see support code
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" },
                requestErrorHandler: { _, error in handled.record(error) }
            )

            // (a) A rejection THROWS to the caller — never reaches the handler
            let rejected = ShowStrictErrorReplyRequest()
            do {
                try await rejected.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError")
            } catch is CredentialRejectedError {
                // thrown to the caller — NOT swallowed into the handler
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }
            #expect(handled.count == 0)

            // (b) An operation's own ResponseError still routes to the handler
            // (handler swallows: no throw, responseBody stays nil)
            let admittedEnv = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "valid-token" },
                requestErrorHandler: { _, error in handled.record(error) }
            )
            let failing = ShowOperationFailureRequest()
            try await failing.processRequest(mvvmEnv: admittedEnv)
            #expect(handled.count == 1)
            #expect(handled.last is StrictContractError)
            #expect(failing.responseBody == nil)
        }
    }

    @Test("Precedence: a permissive custom ResponseError does not swallow a rejection")
    func permissiveCustomResponseErrorDoesNotSwallow() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app) // also registers the permissive fixture
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowPermissiveErrorReplyRequest() // ResponseError decodes loose JSON
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected CredentialRejectedError")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }
        }
    }

    @Test("Skew fallback: a plain 401 without the envelope behaves as today")
    func plain401WithoutEnvelopeFallsBack() async throws {
        try await withRunningServer { app in
            // Vapor's STOCK middleware — the old-server wire shape (no envelope)
            let protected = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { _ in false })
            )
            try protected.register(collection: RoundTripController<ShowStrictErrorReplyRequest>(actions: [
                .show: { _, _ in GrantedReply(message: "granted") }
            ]))
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            let request = ShowStrictErrorReplyRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected a failure")
            } catch DataFetchError.badStatus(httpStatusCode: let code) {
                #expect(code == 401) // pre-envelope fallback, unchanged
            } catch {
                Issue.record("Expected badStatus(401) fallback, got \(error)")
            }
        }
    }

    @Test("Under FOS ErrorMiddleware, a rejection body IS the typed CredentialRejectedError")
    func rejectionBodyIsTypedUnderFOSErrorMiddleware() async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
            Self.registerProtectedRoute(app, isValid: { _ in false })
        } _: { base in
            let rejected = try await Self.send(
                to: base,
                headers: ["Authorization": "Bearer nope"]
            )

            #expect(rejected.status == 401) // transport dressing
            #expect(rejected.wwwAuthenticate == "Bearer") // RFC 7235 preserved
            let typed: CredentialRejectedError = try rejected.body.fromJSON()
            #expect(typed.code == .invalid) // the semantics

            let missing = try await Self.send(to: base, headers: [:])
            let missingTyped: CredentialRejectedError = try missing.body.fromJSON()
            #expect(missingTyped.code == .missing)
        }
    }

    @Test("A custom ServerCredentialVerifier conformance is honored — the protocol seam")
    func customVerifierIsHonored() async throws {
        try await withRunningServer { app in
            let protected = app.grouped(
                ClientCredentialMiddleware(verifier: ApiKeyVerifier(expectedKey: "the-key"))
            )
            protected.get("protected") { _ in "granted" }
        } _: { base in
            let admitted = try await Self.send(
                to: base,
                headers: ["X-Api-Key": "the-key"]
            )
            #expect(admitted.status == 200)
            #expect(admitted.body == "granted")

            let rejected = try await Self.send(
                to: base,
                headers: ["X-Api-Key": "the-wrong-key"]
            )
            #expect(rejected.status == 401)
        }
    }

    @Test("The verifier is consulted per request — a revoked token admits, then rejects")
    func verifierConsultedPerRequest() async throws {
        let registry = TokenRegistry(currentToken: "rotating-token")

        try await withRunningServer { app in
            Self.registerProtectedRoute(app, isValid: { token in
                await registry.isCurrent(token)
            })
        } _: { base in
            let headers = ["Authorization": "Bearer rotating-token"]

            let beforeRevocation = try await Self.send(to: base, headers: headers)
            #expect(beforeRevocation.status == 200)

            await registry.revoke()

            let afterRevocation = try await Self.send(to: base, headers: headers)
            #expect(afterRevocation.status == 401)
        }
    }
}

// MARK: - Fixtures

private extension ClientCredentialMiddlewareTests {
    /// Registers `GET /protected` behind a ``ClientCredentialMiddleware`` running the stock
    /// bearer verifier over `isValid`.
    static func registerProtectedRoute(
        _ app: Application,
        isValid: @Sendable @escaping (String) async -> Bool
    ) {
        let protected = app.grouped(
            ClientCredentialMiddleware(verifier: BearerCredentialVerifier(isValid: isValid))
        )
        protected.get("protected") { _ in "granted" }
    }

    /// Registers both client-contract fixtures behind an always-rejecting bearer verifier,
    /// with FOS `ErrorMiddleware.default` replacing Vapor's stock error serializer — the
    /// configuration the DocC's Client-Side Contract describes.
    static func registerRejectingClientContractRoutes(_ app: Application) throws {
        app.middleware = .init()
        app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

        let protected = app.grouped(
            ClientCredentialMiddleware(verifier: BearerCredentialVerifier { _ in false })
        )
        try protected.register(collection: RoundTripController<ShowStrictErrorReplyRequest>(actions: [
            .show: { _, _ in GrantedReply(message: "granted") }
        ]))
        try protected.register(collection: RoundTripController<ShowGrantedReplyRequest>(actions: [
            .show: { _, _ in GrantedReply(message: "granted") }
        ]))
        try protected.register(collection: RoundTripController<ShowPermissiveErrorReplyRequest>(actions: [
            .show: { _, _ in GrantedReply(message: "granted") }
        ]))
    }

    /// Adds a SECOND protected group (admitting `"valid-token"`) whose `.show`
    /// controller throws `StrictContractError` — an operation's own
    /// `ResponseError`, which must still route to `requestErrorHandler`. Assumes
    /// FOS `ErrorMiddleware.default` is already installed by
    /// ``registerRejectingClientContractRoutes(_:)`` (called first in the same
    /// fixture).
    static func registerAdmittedThrowingRoute(_ app: Application) throws {
        let admitted = app.grouped(
            ClientCredentialMiddleware(verifier: BearerCredentialVerifier { $0 == "valid-token" })
        )
        try admitted.register(collection: RoundTripController<ShowOperationFailureRequest>(actions: [
            .show: { _, _ in throw StrictContractError(errorCode: 99) }
        ]))
    }

    /// Performs `GET <base>/protected` with the given headers and yields the raw
    /// status + body + challenge header the server sent — no client-side error
    /// mapping in the way.
    static func send(
        to base: URL,
        headers: [String: String]
    ) async throws -> (status: Int, body: String, wwwAuthenticate: String?) {
        var urlRequest = URLRequest(url: base.appendingPathComponent("protected"))
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: NonHTTPResponseFailure())
                    return
                }

                continuation.resume(returning: (
                    status: http.statusCode,
                    body: String(data: data ?? Data(), encoding: .utf8) ?? "",
                    wwwAuthenticate: http.value(forHTTPHeaderField: "WWW-Authenticate")
                ))
            }.resume()
        }
    }

    /// An `MVVMEnvironment` pointed at the live server for every `Deployment`, so the test
    /// holds regardless of how the test process resolves `Deployment.current`. The explicit
    /// `session:`-before-`requestErrorHandler:` label order selects the non-SwiftUI
    /// initializer (no bundle-version compatibility gate).
    static func environment(
        base: URL,
        provider: (any ClientCredentialProvider)? = nil,
        requestErrorHandler: (@Sendable (any ServerRequest, any ServerRequestError) -> Void)? = nil
    ) -> MVVMEnvironment {
        MVVMEnvironment(
            currentVersion: SystemVersion.current,
            appBundle: Bundle.main,
            clientCredentialProvider: provider,
            deploymentURLs: [
                .production: base,
                .staging: base,
                .debug: base,
                .test: base
            ],
            session: nil,
            requestErrorHandler: requestErrorHandler
        )
    }
}

/// The server replied with something other than HTTP — never expected against the harness.
private struct NonHTTPResponseFailure: Error {}

/// A custom verifier over a different credential scheme entirely (`X-Api-Key`) —
/// proves the middleware honors any ``ServerCredentialVerifier`` conformance.
private struct ApiKeyVerifier: ServerCredentialVerifier {
    let expectedKey: String

    func verify(headers: HTTPHeaders) async throws {
        guard headers.first(name: "X-Api-Key") == expectedKey else {
            throw Abort(.unauthorized, reason: "Invalid API key")
        }
    }
}

/// A revocable token source — models a server-side session store whose set of
/// currently-valid tokens changes between requests.
private actor TokenRegistry {
    private var currentToken: String?

    init(currentToken: String?) {
        self.currentToken = currentToken
    }

    func isCurrent(_ token: String) -> Bool {
        token == currentToken
    }

    func revoke() {
        currentToken = nil
    }
}

/// Same `.show` shape; its `ResponseError` cannot decode from a rejection body,
/// so under stock (non-FOS) middleware the raw 401 surfaces
/// (`plain401WithoutEnvelopeFallsBack`), and under FOS `ErrorMiddleware` the
/// typed rejection wins.
private final class ShowStrictErrorReplyRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = StrictContractError

    var action: ServerRequestAction {
        .show
    }

    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}

/// Synchronous, lock-guarded error sink — the handler is a plain @Sendable
/// closure; an actor + Task would make the count assertion racy on the
/// failure path this test exists to catch.
private final class ErrorSink: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []

    func record(_ error: any Error) {
        lock.withLock { errors.append(error) }
    }

    var count: Int {
        lock.withLock { errors.count }
    }

    var last: (any Error)? {
        lock.withLock { errors.last }
    }
}

/// A permissive error — its single optional field decodes from ANY JSON
/// object, like EmptyError but user-defined (spec §6 test 7).
private struct PermissiveContractError: ServerRequestError {
    let note: String?
}

/// Same .show shape as the other fixtures; ResponseError is permissive.
private final class ShowPermissiveErrorReplyRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = PermissiveContractError

    var action: ServerRequestAction {
        .show
    }

    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}
