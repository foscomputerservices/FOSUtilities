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
//     with FOS `ErrorMiddleware.default` installed, a rejection surfaces as
//     `DataFetchError.badStatus(httpStatusCode: 401)` — requestErrorHandler bypassed —
//     PROVIDED the request's `ResponseError` does not decode from the rejection body;
//     `EmptyError` always decodes (no-op synthesized decode), swallowing the 401 into
//     a contentless typed error — the known limitation, pinned by its own test.

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

    @Test("On a FOSMVVM client, a rejection surfaces as DataFetchError.badStatus(401)")
    func rejectionSurfacesAsBadStatus401ToTheClient() async throws {
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
                Issue.record("Expected DataFetchError.badStatus(401), but the request succeeded")
            } catch DataFetchError.badStatus(httpStatusCode: let code) {
                // NOT a ServerRequestError — requestErrorHandler is bypassed; this is
                // the error downstream consumers branch on.
                #expect(code == 401)
            } catch {
                Issue.record("Expected DataFetchError.badStatus(401), got \(error)")
            }

            #expect(request.responseBody == nil)
        }
    }

    @Test("Known limitation: an EmptyError ResponseError swallows the 401 into a contentless typed error")
    func emptyErrorResponseSwallowsThe401() async throws {
        try await withRunningServer { app in
            try Self.registerRejectingClientContractRoutes(app)
        } _: { base in
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { "revoked-token" }
            )

            // EmptyError's synthesized decode is a no-op, so it decodes from ANY
            // valid-JSON rejection body — the 401 never reaches the caller. Pinned
            // here so a DataFetch behavior change surfaces as a test delta.
            let request = ShowGrantedReplyRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected EmptyError, but the request succeeded")
            } catch is EmptyError {
                // The documented swallow — a contentless typed error, no status visible
            } catch {
                Issue.record("Expected EmptyError, got \(error)")
            }

            #expect(request.responseBody == nil)
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

    // MARK: - Fixtures

    /// Registers `GET /protected` behind a ``ClientCredentialMiddleware`` running the stock
    /// bearer verifier over `isValid`.
    private static func registerProtectedRoute(
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
    private static func registerRejectingClientContractRoutes(_ app: Application) throws {
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
    }

    /// Performs `GET <base>/protected` with the given headers and yields the raw
    /// status + body + challenge header the server sent — no client-side error
    /// mapping in the way.
    private static func send(
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
    private static func environment(
        base: URL,
        provider: any ClientCredentialProvider
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
            requestErrorHandler: nil
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

/// The response body a protected route grants — the client-contract test never
/// receives one (the middleware rejects first).
private struct GrantedReply: ServerRequestBody {
    let message: String
}

/// A typed error with a required field — it does NOT decode from a rejection body,
/// so the middleware's 401 stays visible to the caller as `DataFetchError.badStatus`.
private struct StrictContractError: ServerRequestError {
    let errorCode: Int
}

/// `.show` fixture behind the protected group — drives the REAL client
/// (`processRequest(mvvmEnv:)`) against the middleware. Its `EmptyError`
/// `ResponseError` is the known-limitation fixture: it decodes from any
/// valid-JSON rejection body, swallowing the 401.
private final class ShowGrantedReplyRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .show
    }

    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}

/// The 401-visibility fixture: same `.show` shape, but its `ResponseError` cannot
/// decode from a rejection body, so `DataFetchError.badStatus(401)` surfaces.
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
