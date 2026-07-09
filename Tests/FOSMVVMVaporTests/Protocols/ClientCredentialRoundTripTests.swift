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

    // MARK: - Fixtures

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

/// A mutable token source — models an app session whose credential rotates between requests.
/// (Mirrors the helper in `ClientCredentialProviderTests` — separate test targets, same shape.)
private actor TokenVault {
    var token: String?

    init(token: String?) {
        self.token = token
    }

    func rotate(to newToken: String?) {
        token = newToken
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

/// Counts the requests the server actually served.
private actor RequestTally {
    private(set) var count = 0

    func increment() {
        count += 1
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
