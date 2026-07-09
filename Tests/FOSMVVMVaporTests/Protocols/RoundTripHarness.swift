// RoundTripHarness.swift
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

// The live-server round-trip harness, shared by the suites that exercise the REAL client
// (`ServerRequest.processRequest` → `DataFetch` → a live `URLSession`) against a REAL server
// bound to an OS-assigned port (see `ServerRequestRoundTripTests` for why that gap matters).

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor

/// Boots a real listening `Application` on an OS-assigned port (`127.0.0.1:0`), registers routes
/// via `register`, yields the base URL (`http://127.0.0.1:<port>`) to `body`, then tears the
/// server down. Localization is initialized so `buildResponse`'s `localizingEncoder` resolves.
func withRunningServer(
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

/// A no-op `LocalizationStore` so `req.localizingEncoder` resolves on the live server; every key
/// falls back to its `default`.
private struct RoundTripLocalizationStore: LocalizationStore {
    func value(_ key: String, locale: Locale, default defaultValue: Any?, index: Int?) -> Any? {
        defaultValue
    }
}

/// A hand-written controller: one processor per action, over any `ServerRequest`.
final class RoundTripController<R: ServerRequest>: ServerRequestController, @unchecked Sendable {
    typealias TRequest = R

    let actions: [ServerRequestAction: ActionProcessor]

    init(actions: [ServerRequestAction: ActionProcessor]) {
        self.actions = actions
    }
}
