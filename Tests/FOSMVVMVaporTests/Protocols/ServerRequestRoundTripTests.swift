// ServerRequestRoundTripTests.swift
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

// End-to-end round-trip: the REAL client (`ServerRequest.processRequest` → `DataFetch` → a live
// `URLSession`) against a REAL server bound to an OS-assigned port. This is the contract the rest of
// the suite never exercises — `ServerRequestControllerTests` drives the server in-memory
// (`app.responder.respond`) and the client is only tested against mocked responses, so a client↔server
// *content-negotiation* mismatch is invisible to every other test. This harness closes that gap: it
// sends real bytes over a socket and decodes the real response, so the `Accept`/`Content-Type`
// contract between `processRequest` and `buildResponse` is actually verified.

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import Testing
import Vapor

@Suite("ServerRequest round-trip (real processRequest ↔ running server)", .serialized)
struct ServerRequestRoundTripTests {
    /// A response body carrying real content decodes through the live client — the control case that
    /// proves this harness drives `DataFetch`/`URLSession` end-to-end (not the in-memory responder).
    @Test func realBodyResponseRoundTrips() async throws {
        try await withRunningServer { app in
            let controller = RoundTripController<ShowMarkerRequest>(actions: [
                .show: { _, bound in RoundTripMarker(marker: bound.query?.text ?? "<nil>") }
            ])
            try app.routes.register(collection: controller)
        } _: { base in
            let request = ShowMarkerRequest(query: RoundTripQuery(text: "ahoy"))
            let response = try await request.processRequest(baseURL: base)
            #expect(response?.marker == "ahoy")
        }
    }

    /// An `EmptyBody` response must round-trip through the real client too. This drives the exact
    /// header `processRequest(mvvmEnv:)` injects for an `EmptyBody` response — `Accept: text/plain`
    /// (`ServerRequest+Fetch.swift:122`) — which is what a real consumer sends.
    ///
    /// It currently FAILS (`DataFetchError.badResponseMimeType`): `buildResponse` answers
    /// `application/json` (`EmptyBody` → `{}`) regardless of `Accept`, and `DataFetch.checkMimeType`
    /// rejects `application/json` against the expected `text/plain`. That is the content-negotiation
    /// gap (PL-8): one fixed `Accept` for `EmptyBody` cannot satisfy both a `text/plain` (plain REST)
    /// server and an `application/json` (`buildResponse`) server. The fix should make an `EmptyBody`
    /// response content-agnostic (on 2xx, decode to `EmptyBody()` without a MIME gate).
    @Test func emptyBodyResponseRoundTrips() async throws {
        try await withRunningServer { app in
            let controller = RoundTripController<EmptyAckRequest>(actions: [
                .create: { _, _ in EmptyBody() }
            ])
            try app.routes.register(collection: controller)
        } _: { base in
            let request = EmptyAckRequest(requestBody: EmptyBody())
            // The `Accept: text/plain` that `processRequest(mvvmEnv:)` adds for an EmptyBody response.
            try await request.processRequest(
                baseURL: base,
                headers: [(field: "Accept", value: "text/plain")]
            )
        }
    }

    /// Probes what `checkReceivedMimeType: false` alone buys us, directly against `DataFetch` (no
    /// `processRequest`), so the two gates are visible separately:
    ///   • gate 1 — `checkMimeType`: the flag skips it (no more `badResponseMimeType` at the check).
    ///   • gate 2 — the decode ladder: still can't turn the server's `{}` body into an `EmptyBody`
    ///     (no branch yields it), so it throws at the `else`. The flag is necessary, not sufficient.
    ///   • Requesting `String` (the first decode branch, which decodes ANY 2xx body) closes gate 2.
    @Test func checkReceivedMimeTypeFalseIsNecessaryButNotSufficientForEmptyBody() async throws {
        try await withRunningServer { app in
            let controller = RoundTripController<EmptyAckRequest>(actions: [
                .create: { _, _ in EmptyBody() }
            ])
            try app.routes.register(collection: controller)
        } _: { base in
            let url = try EmptyAckRequest(requestBody: EmptyBody()).requestURL(baseURL: base)
            let fetch = DataFetch<URLSession>.default

            // Flag off the MIME check, but ask for `EmptyBody` → gate 2 still throws.
            await #expect(throws: (any Error).self) {
                let _: EmptyBody = try await fetch.send(
                    data: Data(), to: url, httpMethod: "POST",
                    headers: [(field: "Accept", value: "text/plain")], locale: nil,
                    checkReceivedMimeType: false
                )
            }

            // Same call, but ask for `String` (decodes any body) → succeeds; the caller would map
            // the discarded body to `EmptyBody()`.
            let body: String = try await fetch.send(
                data: Data(), to: url, httpMethod: "POST",
                headers: [(field: "Accept", value: "text/plain")], locale: nil,
                checkReceivedMimeType: false
            )
            #expect(body == "{}")
        }
    }

    // MARK: - Harness

    /// Boots a real listening `Application` on an OS-assigned port (`127.0.0.1:0`), registers routes
    /// via `register`, yields the base URL (`http://127.0.0.1:<port>`) to `body`, then tears the
    /// server down. Localization is initialized so `buildResponse`'s `localizingEncoder` resolves.
    private func withRunningServer(
        register: (Application) throws -> Void,
        _ body: (URL) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            // A stub store so `buildResponse`'s `localizingEncoder` resolves (keys fall back to
            // default). The live server needs this; the round-trip asserts transport, not localization.
            app.localizationStore = RoundTripLocalizationStore()
            try register(app)

            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try #require(
                app.http.server.shared.localAddress?.port,
                "Failed to read OS-assigned port after server.start"
            )
            let base = try #require(URL(string: "http://127.0.0.1:\(port)"))

            try await body(base)

            await app.server.shutdown()
            try await app.asyncShutdown()
        } catch {
            await app.server.shutdown()
            try await app.asyncShutdown()
            throw error
        }
    }
}

// MARK: - Fixtures

/// A no-op `LocalizationStore` so `req.localizingEncoder` resolves on the live server; every key
/// falls back to its `default`.
private struct RoundTripLocalizationStore: LocalizationStore {
    func value(_ key: String, locale: Locale, default defaultValue: Any?, index: Int?) -> Any? {
        defaultValue
    }
}

/// A query carrying a single string, so a `.show` processor can echo it back over the wire.
private struct RoundTripQuery: ServerRequestQuery {
    let text: String
}

/// A marker response body — the processor writes what it observed; the client decodes it off the wire.
private struct RoundTripMarker: ServerRequestBody {
    let marker: String
}

/// A hand-written controller: one processor per action, over any `ServerRequest`.
private final class RoundTripController<R: ServerRequest>: ServerRequestController, @unchecked Sendable {
    typealias TRequest = R

    let actions: [ServerRequestAction: ActionProcessor]

    init(actions: [ServerRequestAction: ActionProcessor]) {
        self.actions = actions
    }
}

/// `.show` fixture with a real (`RoundTripMarker`) response body — the control case.
private final class ShowMarkerRequest: ServerRequest, @unchecked Sendable {
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = RoundTripMarker
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .show
    }

    let query: RoundTripQuery?
    var responseBody: RoundTripMarker?

    init(query: RoundTripQuery?, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: RoundTripMarker? = nil) {
        self.query = query
        self.responseBody = responseBody
    }
}

/// `.create` fixture whose `ResponseBody == EmptyBody`: an ack-shaped write (mirrors Harbor's
/// `AgentTokenRevokeRequest` / `SecretReplaceRequest`), the case the content-negotiation gap breaks.
private final class EmptyAckRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = EmptyBody
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .create
    }

    let requestBody: EmptyBody?
    var responseBody: EmptyBody?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: EmptyBody? = nil) {
        self.requestBody = requestBody
        self.responseBody = responseBody
    }
}
