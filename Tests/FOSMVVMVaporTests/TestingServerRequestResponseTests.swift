// TestingServerRequestResponseTests.swift
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

// `TestingServerRequestResponse` gives server tests the SAME typed visibility the
// real client has: a rejection surfaces as `credentialRejection` (decoded FIRST,
// same order as the client), gating `error` so a permissive `ResponseError` can't
// swallow the 401 — while an operation's own `ResponseError` still populates `error`.

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Vapor
import VaporTesting

@Suite("TestingServerRequestResponse credential rejection", .serialized)
struct TestingServerRequestResponseTests {
    @Test("A rejection populates credentialRejection; error stays nil")
    func rejectionIsTyped() async throws {
        try await withTestingApp { app in
            let protected = app.grouped(
                ClientCredentialMiddleware(verifier: BearerCredentialVerifier { _ in false })
            )
            try protected.register(collection: RoundTripController<ShowGrantedReplyRequest>(actions: [
                .show: { _, _ in GrantedReply(message: "granted") }
            ]))
        } _: { app in
            // An invalid bearer token is present, so the verifier rejects with `.invalid`
            // (a missing header would be `.missing`).
            try await app.testing().test(
                ShowGrantedReplyRequest(),
                headers: ["Authorization": "Bearer nope"]
            ) { response in
                #expect(response.status == .unauthorized) // transport contract
                #expect(response.credentialRejection?.code == .invalid) // the semantics
                #expect(response.error == nil) // EmptyError does NOT swallow
                #expect(response.body == nil)
            }
        }
    }

    @Test("An operation error populates error; credentialRejection stays nil")
    func operationErrorIsTyped() async throws {
        try await withTestingApp { app in
            // No credential middleware — the operation runs, then throws its own
            // `ResponseError` (a required-field type the rejection envelope can't pun into).
            try app.register(collection: RoundTripController<ShowOperationFailureRequest>(actions: [
                .show: { _, _ in throw StrictContractError(errorCode: 99) }
            ]))
        } _: { app in
            try await app.testing().test(ShowOperationFailureRequest()) { response in
                #expect(response.credentialRejection == nil) // the rejection gate is closed
                #expect(response.error?.errorCode == 99) // the operation error still lands
                #expect(response.body == nil)
            }
        }
    }
}

/// Boots an in-process `.testing` Application with the localization store and FOS
/// `ErrorMiddleware.default` installed, runs `configure` then `body`, and shuts the
/// app down on both the success and failure paths.
private func withTestingApp(
    configure: (Application) throws -> Void,
    _ body: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        app.localizationStore = RoundTripLocalizationStore()
        app.middleware = .init()
        app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
        try configure(app)
        try await body(app)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
