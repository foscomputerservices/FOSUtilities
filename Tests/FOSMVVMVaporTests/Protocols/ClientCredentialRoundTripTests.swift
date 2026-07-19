// ClientCredentialRoundTripTests.swift
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

// End-to-end proof that a `ClientCredentialProvider` registered on `MVVMEnvironment` puts its
// headers ON THE WIRE: the REAL client (`processRequest(mvvmEnv:)`) against a REAL server that
// echoes back the header values it observed. The contract under test:
//   • the provider's headers ARRIVE at the server,
//   • the provider is consulted PER CALL (a rotated credential rides the next request),
//   • provider headers append AFTER the static `requestHeaders`, so the per-request
//     credential wins on a duplicate field while other static headers still flow,
//   • a THROWING provider propagates to the caller and no request reaches the server.

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

@Suite("ClientCredentialProvider round-trip (processRequest(mvvmEnv:) ↔ running server)", .serialized)
struct ClientCredentialRoundTripTests {
    @Test("Provider headers arrive at the server, and rotation is reflected per call")
    func providerHeaderArrivesAndRotates() async throws {
        try await withRunningServer { app in
            try app.routes.register(collection: Self.headerEchoController())
        } _: { base in
            let vault = TokenVault(token: "first")
            let env = Self.environment(
                base: base,
                provider: BearerCredentialProvider { await vault.token }
            )

            let firstRequest = ShowObservedHeadersRequest()
            try await firstRequest.processRequest(mvvmEnv: env)
            #expect(firstRequest.responseBody?.authorization == "Bearer first")

            await vault.rotate(to: "second")

            let secondRequest = ShowObservedHeadersRequest()
            try await secondRequest.processRequest(mvvmEnv: env)
            #expect(secondRequest.responseBody?.authorization == "Bearer second")
        }
    }

    @Test("Provider headers append after static requestHeaders — provider wins on a duplicate field")
    func providerHeadersWinOverStaticRequestHeaders() async throws {
        try await withRunningServer { app in
            try app.routes.register(collection: Self.headerEchoController())
        } _: { base in
            let env = Self.environment(
                base: base,
                requestHeaders: [
                    "Authorization": "Bearer stale-static",
                    "X-Client-Marker": "static-value"
                ],
                provider: BearerCredentialProvider { "fresh" }
            )

            let request = ShowObservedHeadersRequest()
            try await request.processRequest(mvvmEnv: env)

            // The duplicate field: the provider's per-request credential wins
            #expect(request.responseBody?.authorization == "Bearer fresh")
            // The non-duplicate static header still arrives
            #expect(request.responseBody?.clientMarker == "static-value")
        }
    }

    @Test("A throwing provider surfaces to the caller and no request reaches the server")
    func throwingProviderSurfacesAndSendsNothing() async throws {
        let tally = RequestTally()

        try await withRunningServer { app in
            let controller = RoundTripController<ShowObservedHeadersRequest>(actions: [
                .show: { req, _ in
                    await tally.increment()
                    return ObservedHeaders(
                        authorization: req.headers.first(name: "Authorization") ?? "<none>",
                        clientMarker: req.headers.first(name: "X-Client-Marker") ?? "<none>"
                    )
                }
            ])
            try app.routes.register(collection: controller)
        } _: { base in
            let env = Self.environment(base: base, provider: FailingCredentialProvider())

            let request = ShowObservedHeadersRequest()
            await #expect(throws: CredentialResolutionFailure.self) {
                try await request.processRequest(mvvmEnv: env)
            }

            // The failure pre-empted the request — the server served nothing
            #expect(await tally.count == 0)
            #expect(request.responseBody == nil)
        }
    }

    @Test("A refreshed credential retries once and succeeds")
    func refreshRetriesOnceAndSucceeds() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let attempts = RequestTally()
        let refreshes = RequestTally()

        try await Self.withProtectedServer { token in
            await attempts.increment()
            return await serverCredential.isCurrent(token)
        } register: { group in
            try group.register(collection: Self.headerEchoController())
        } body: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "rotated",
                    refreshTally: refreshes
                )
            )

            let request = ShowObservedHeadersRequest()
            try await request.processRequest(mvvmEnv: env)

            #expect(request.responseBody?.authorization == "Bearer rotated")
            #expect(await attempts.count == 2)
            #expect(await refreshes.count == 1)
        }
    }

    @Test("A provider that declines to refresh rethrows the original rejection, unretried")
    func decliningProviderRethrowsUnretried() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let attempts = RequestTally()
        let refreshes = RequestTally()

        try await Self.withProtectedServer { token in
            await attempts.increment()
            return await serverCredential.isCurrent(token)
        } register: { group in
            try group.register(collection: Self.headerEchoController())
        } body: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: nil,
                    refreshTally: refreshes
                )
            )

            let request = ShowObservedHeadersRequest()
            do {
                try await request.processRequest(mvvmEnv: env)
                Issue.record("Expected the original rejection to be rethrown")
            } catch let rejection as CredentialRejectedError {
                #expect(rejection.code == .invalid)
            } catch {
                Issue.record("Expected CredentialRejectedError, got \(error)")
            }

            #expect(await attempts.count == 1)
            #expect(await refreshes.count == 1)
        }
    }

    @Test("A second rejection throws — the retry is never recursive")
    func secondRejectionThrowsWithoutFurtherRetry() async throws {
        let serverCredential = ServerCredential(current: "never-matches")
        let attempts = RequestTally()
        let refreshes = RequestTally()

        try await Self.withProtectedServer { token in
            await attempts.increment()
            return await serverCredential.isCurrent(token)
        } register: { group in
            try group.register(collection: Self.headerEchoController())
        } body: { base in
            let env = Self.environment(
                base: base,
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "also-wrong",
                    refreshTally: refreshes
                )
            )

            let request = ShowObservedHeadersRequest()
            await #expect(throws: CredentialRejectedError.self) {
                try await request.processRequest(mvvmEnv: env)
            }

            #expect(await attempts.count == 2)
            #expect(await refreshes.count == 1)
        }
    }

    @Test("The retry preserves static requestHeaders, and the refreshed credential still wins")
    func retryPreservesStaticHeaders() async throws {
        let serverCredential = ServerCredential(current: "rotated")

        try await Self.withProtectedServer { token in
            await serverCredential.isCurrent(token)
        } register: { group in
            try group.register(collection: Self.headerEchoController())
        } body: { base in
            let env = Self.environment(
                base: base,
                requestHeaders: [
                    "Authorization": "Bearer stale-static",
                    "X-Client-Marker": "static-value"
                ],
                provider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "rotated",
                    refreshTally: RequestTally()
                )
            )

            let request = ShowObservedHeadersRequest()
            try await request.processRequest(mvvmEnv: env)

            #expect(request.responseBody?.authorization == "Bearer rotated")
            #expect(request.responseBody?.clientMarker == "static-value")
        }
    }

    @Test("A rejection thrown by the provider itself does not open the refresh seam")
    func providerThrownRejectionDoesNotOpenSeam() async throws {
        let refreshes = RequestTally()
        let attempts = RequestTally()

        try await Self.withProtectedServer { _ in
            await attempts.increment()
            return true
        } register: { group in
            try group.register(collection: Self.headerEchoController())
        } body: { base in
            let env = Self.environment(
                base: base,
                provider: RejectingCredentialProvider(refreshTally: refreshes)
            )

            let request = ShowObservedHeadersRequest()
            await #expect(throws: CredentialRejectedError.self) {
                try await request.processRequest(mvvmEnv: env)
            }

            #expect(await attempts.count == 0)
            #expect(await refreshes.count == 0)
        }
    }

    @Test("A non-rejection error on the retry still reaches requestErrorHandler")
    func retryOperationErrorReachesHandler() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let handled = ErrorSink()

        try await Self.withProtectedServer { token in
            await serverCredential.isCurrent(token)
        } register: { group in
            try group.register(collection: RoundTripController<ShowOperationFailureRequest>(actions: [
                .show: { _, _ in throw StrictContractError(errorCode: 42) }
            ]))
        } body: { base in
            let env = MVVMEnvironment(
                currentVersion: SystemVersion.current,
                appBundle: Bundle.main,
                requestHeaders: [:],
                clientCredentialProvider: RefreshingCredentialProvider(
                    vault: TokenVault(token: "stale"),
                    refreshedTo: "rotated",
                    refreshTally: RequestTally()
                ),
                deploymentURLs: [
                    .production: base, .staging: base, .debug: base, .test: base
                ],
                session: nil,
                requestErrorHandler: { _, error in handled.record(error) }
            )

            let request = ShowOperationFailureRequest()
            try await request.processRequest(mvvmEnv: env)

            #expect(handled.count == 1)
            #expect(handled.last is StrictContractError)
        }
    }

    @Test("Concurrent refused requests each consult the seam")
    func concurrentRejectionsEachConsultTheSeam() async throws {
        let serverCredential = ServerCredential(current: "rotated")
        let refreshes = RequestTally()

        try await Self.withProtectedServer { token in
            await serverCredential.isCurrent(token)
        } register: { group in
            try group.register(collection: Self.headerEchoController())
        } body: { base in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        // Each task carries its OWN stale vault, so every first-send is refused
                        // and every task must consult the seam — not just whichever wins the
                        // race to rotate a shared vault. All 4 then retry with "rotated".
                        let env = Self.environment(
                            base: base,
                            provider: RefreshingCredentialProvider(
                                vault: TokenVault(token: "stale"),
                                refreshedTo: "rotated",
                                refreshTally: refreshes
                            )
                        )

                        let request = ShowObservedHeadersRequest()
                        try await request.processRequest(mvvmEnv: env)
                        #expect(request.responseBody?.authorization == "Bearer rotated")
                    }
                }
                try await group.waitForAll()
            }

            #expect(await refreshes.count == 4)
        }
    }

    // MARK: - Fixtures

    /// Boots `withRunningServer` with the stock error serializer replaced by FOS
    /// `ErrorMiddleware` — without which a rejection reaches the client as
    /// `DataFetchError.badStatus(401)` rather than a typed `CredentialRejectedError` — and mounts
    /// `register`'s routes behind a `ClientCredentialMiddleware(verifier:)`. Centralizing the
    /// middleware install here means an individual test can never forget it.
    private static func withProtectedServer(
        verifier: @escaping @Sendable (String) async -> Bool,
        register: (any RoutesBuilder) throws -> Void,
        body: (URL) async throws -> Void
    ) async throws {
        try await withRunningServer { app in
            app.middleware = .init()
            app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))

            let protectedGroup = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier(isValid: verifier))
            )
            try register(protectedGroup)
        } _: { base in
            try await body(base)
        }
    }

    /// Echoes the request headers the server observed back over the wire.
    private static func headerEchoController() -> RoundTripController<ShowObservedHeadersRequest> {
        RoundTripController(actions: [
            .show: { req, _ in
                ObservedHeaders(
                    authorization: req.headers.first(name: "Authorization") ?? "<none>",
                    clientMarker: req.headers.first(name: "X-Client-Marker") ?? "<none>"
                )
            }
        ])
    }

    /// An `MVVMEnvironment` pointed at the live server for every `Deployment`, so the test
    /// holds regardless of how the test process resolves `Deployment.current`. The explicit
    /// `session:`-before-`requestErrorHandler:` label order selects the non-SwiftUI initializer
    /// (no bundle-version compatibility gate).
    private static func environment(
        base: URL,
        requestHeaders: [String: String] = [:],
        provider: any ClientCredentialProvider
    ) -> MVVMEnvironment {
        MVVMEnvironment(
            currentVersion: SystemVersion.current,
            appBundle: Bundle.main,
            requestHeaders: requestHeaders,
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

/// The failure a credential provider raises when its credential cannot be resolved.
private struct CredentialResolutionFailure: Error {}

/// A provider whose credential resolution always fails — drives the propagation contract.
private struct FailingCredentialProvider: ClientCredentialProvider {
    func credentialHeaders() async throws -> [(field: String, value: String)] {
        throw CredentialResolutionFailure()
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

/// A provider whose own header composition throws a rejection — models a client-side
/// credential failure, which must NOT be treated as a server refusal (spec §5.1).
private struct RejectingCredentialProvider: ClientCredentialProvider {
    let refreshTally: RequestTally

    func credentialHeaders() async throws -> [(field: String, value: String)] {
        throw CredentialRejectedError(code: .missing)
    }

    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        await refreshTally.increment()
        return [(field: "Authorization", value: "Bearer anything")]
    }
}

/// The header values the server observed — the processor writes them; the client decodes them
/// off the wire.
private struct ObservedHeaders: ServerRequestBody {
    let authorization: String
    let clientMarker: String
}

/// `.show` fixture whose response body carries the observed headers.
private final class ShowObservedHeadersRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = ObservedHeaders
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .show
    }

    var responseBody: ObservedHeaders?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: ObservedHeaders? = nil) {
        self.responseBody = responseBody
    }
}
