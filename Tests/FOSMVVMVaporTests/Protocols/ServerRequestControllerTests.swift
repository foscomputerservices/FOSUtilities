// ServerRequestControllerTests.swift
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

// The general dispatch layer (C8a): a hand-written ServerRequestController serves each verb
// through the real route + middleware pipeline. Every assertion is made on the HTTP response —
// the processor never reaches into internals; it encodes what it saw into the response body.

import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("ServerRequestController general dispatch (C8a)", .serialized)
struct ServerRequestControllerTests {
    /// GET binds the query from the URL: the `.show` processor echoes `bound.query` into the
    /// response — the value survives the middleware's parse (the pre-C8a layer bound nil).
    @Test func showProcessorReceivesBoundQuery() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            let controller = EchoController<EchoShowRequest>(actions: [
                .show: { _, bound in EchoMarker(marker: bound.query?.text ?? "<nil>") }
            ])
            try app.routes.register(collection: controller)
        } _: { app, _ in
            let url = try requestURL(EchoShowRequest(query: EchoQuery(text: "ahoy")))
            let response = try await dispatch(app: app, method: .GET, url: url)

            #expect(response.status == .ok)
            #expect(try marker(response) == "ahoy")
        }
    }

    /// `.delete` maps to HTTP DELETE and reaches its processor: a bare DELETE returns the marker
    /// (the pre-C8a layer threw `invalidAction` at boot for `.delete`).
    @Test func deleteActionRegistersDELETE() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            let controller = EchoController<EchoDeleteRequest>(actions: [
                .delete: { _, _ in EchoMarker(marker: "deleted") }
            ])
            try app.routes.register(collection: controller)
        } _: { app, _ in
            let url = try requestURL(EchoDeleteRequest())
            let response = try await dispatch(app: app, method: .DELETE, url: url)

            #expect(response.status == .ok)
            #expect(try marker(response) == "deleted")
        }
    }

    /// PATCH: the `.update` processor decodes its own body from `req` — the framework no longer
    /// pre-populates `bound.requestBody` — while the middleware-parsed query survives on `bound`.
    /// The processor echoes both; the combined marker asserts the decoded body and the query.
    @Test func updateProcessorReceivesDecodedBody() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            let controller = EchoController<EchoUpdateRequest>(actions: [
                .update: { req, bound in
                    let body = try req.content.decode(EchoBody.self)
                    return EchoMarker(marker: "\(bound.query?.text ?? "<nil>")|\(body.field)")
                }
            ])
            try app.routes.register(collection: controller)
        } _: { app, _ in
            let url = try requestURL(EchoUpdateRequest(query: EchoQuery(text: "ahoy")))
            let body = try EchoBody(field: "payload").toJSONData()
            let response = try await dispatch(app: app, method: .PATCH, url: url, jsonBody: body)

            #expect(response.status == .ok)
            #expect(try marker(response) == "ahoy|payload")
        }
    }

    /// One URL carries one handler per method: a controller registering BOTH `.delete` and
    /// `.destroy` (both HTTP DELETE) fails fast at boot.
    @Test func deletePlusDestroyFailsFastAtBoot() async throws {
        await #expect(throws: ServerRequestControllerError.self) {
            try await withFluentTestApp { app in
                let controller = EchoController<EchoDeleteRequest>(actions: [
                    .delete: { _, _ in EchoMarker(marker: "deleted") },
                    .destroy: { _, _ in EchoMarker(marker: "destroyed") }
                ])
                try app.routes.register(collection: controller)
            } _: { _, _ in }
        }
    }

    /// An `EmptyBody` request decodes nothing: `.update` on such a request leaves `bound.requestBody`
    /// nil even with a body verb. The fact is encoded into the response and asserted there.
    @Test func emptyBodyVerbSkipsDecode() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            let controller = EchoController<EmptyBodyUpdateRequest>(actions: [
                .update: { _, bound in EchoMarker(marker: bound.requestBody == nil ? "nil-body" : "has-body") }
            ])
            try app.routes.register(collection: controller)
        } _: { app, _ in
            let url = try requestURL(EmptyBodyUpdateRequest())
            let response = try await dispatch(app: app, method: .PATCH, url: url)

            #expect(response.status == .ok)
            #expect(try marker(response) == "nil-body")
        }
    }

    // MARK: Test Support

    /// Encodes `request` onto the base URL via the production encoder (path + query blob).
    private func requestURL(_ request: some ServerRequest) throws -> URL {
        let base = try #require(URL(string: "http://localhost"))
        return try #require(try base.appending(serverRequest: request))
    }

    /// Dispatches an HTTP request through the booted application's real responder.
    private func dispatch(
        app: Application,
        method: HTTPMethod,
        url: URL,
        jsonBody: Data? = nil
    ) async throws -> Vapor.Response {
        var headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        if let jsonBody {
            headers.contentType = .json
            buffer.writeBytes(jsonBody)
        }
        let req = Request(
            application: app,
            method: method,
            url: URI(string: url.absoluteString),
            headers: headers,
            collectedBody: buffer,
            on: app.eventLoopGroup.next()
        )
        return try await app.responder.respond(to: req).get()
    }

    /// The `marker` field decoded from an `EchoMarker` response body.
    private func marker(_ response: Vapor.Response) throws -> String {
        let data = try #require(response.body.data)
        let body: EchoMarker = try data.fromJSON()
        return body.marker
    }
}

// MARK: - Fixtures

/// A query carrying a single string, so a `.show` processor can prove the URL was parsed.
private struct EchoQuery: ServerRequestQuery {
    let text: String
}

/// A decodable request body carrying a single field.
private struct EchoBody: ServerRequestBody {
    let field: String
}

/// A marker response body: the processor writes what it observed here; tests read it off the wire.
private struct EchoMarker: ServerRequestBody {
    let marker: String
}

/// A hand-written controller: one processor per action, over any `ServerRequest`.
private final class EchoController<R: ServerRequest>: ServerRequestController, @unchecked Sendable {
    typealias TRequest = R

    let actions: [ServerRequestAction: ActionProcessor]

    init(actions: [ServerRequestAction: ActionProcessor]) {
        self.actions = actions
    }
}

/// `.show` fixture: a `Query` carrying a string, an `EchoMarker` response.
private final class EchoShowRequest: ServerRequest, @unchecked Sendable {
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = EchoMarker
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .show
    }

    let query: EchoQuery?
    var responseBody: EchoMarker?

    init(query: EchoQuery?, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EchoMarker? = nil) {
        self.query = query
        self.responseBody = responseBody
    }
}

/// `.delete` fixture: no query, no body, an `EchoMarker` response.
private final class EchoDeleteRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = EchoMarker
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .delete
    }

    var responseBody: EchoMarker?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EchoMarker? = nil) {
        self.responseBody = responseBody
    }
}

/// `.update` fixture: an `EchoQuery` AND a decodable `EchoBody`, so one PATCH proves the
/// processor sees both the middleware-parsed query (on `bound`) and the body it decodes from `req`.
private final class EchoUpdateRequest: ServerRequest, @unchecked Sendable {
    typealias Fragment = EmptyFragment
    typealias RequestBody = EchoBody
    typealias ResponseBody = EchoMarker
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .update
    }

    let query: EchoQuery?
    let requestBody: EchoBody?
    var responseBody: EchoMarker?

    init(query: EchoQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EchoBody? = nil, responseBody: EchoMarker? = nil) {
        self.query = query
        self.requestBody = requestBody
        self.responseBody = responseBody
    }
}

/// `.update` fixture whose `RequestBody == EmptyBody`: a body verb that decodes nothing.
private final class EmptyBodyUpdateRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = EchoMarker
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .update
    }

    var responseBody: EchoMarker?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EchoMarker? = nil) {
        self.responseBody = responseBody
    }
}
