// AppStateTests.swift
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

// The useAppState(_:builder:) load-phase slot (C8 T5). The builder runs with full request power
// in the load phase; the projection sees only the value it returns. Boot validation is exercised
// through register(request:); the value's visibility is asserted end-to-end through the genuine
// GET pipeline (a non-VM ServerRequestBody keeps the fixture's appState value observable in JSON,
// unlike a localized ViewModel field).

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// MARK: - Fixtures

/// A session-derived value the builder computes in the load phase — the projection receives it as
/// a plain value.
private struct SessionBanner: Sendable {
    let userName: String
}

/// A non-VM ResponseBody so the projected `appState`-derived value survives as observable JSON.
private struct BannerBody: ServerRequestBody {
    let signedInAs: String
}

extension BannerBody: VaporResponseBodyFactory {
    typealias AppState = SessionBanner

    static func body<R: ServerRequest>(context: ProjectionContext<R, SessionBanner>) throws -> Self where R.ResponseBody == Self {
        .init(signedInAs: context.appState.userName)
    }
}

private final class BannerRequest: ShowRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError
    typealias ResponseBody = BannerBody

    let id: String
    let query: EmptyQuery?
    var responseBody: BannerBody?

    init(
        query: EmptyQuery? = nil,
        sort: EmptySort? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: BannerBody? = nil
    ) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

private let signedInHeader = "X-Signed-In-As"

/// Serves a `BannerRequest` GET through the genuine pipeline, sending `signedInAs` as a header, and
/// returns the projected `signedInAs` value from the response body.
private func serveBanner(on app: Application, signedInAs: String) async throws -> String {
    let prefix = "http://localhost"
    let base = try #require(URL(string: prefix))
    let url = try #require(try base.appending(serverRequest: BannerRequest()))
    let uriStr = String(url.absoluteString.trimmingPrefix(prefix))
    let headers = HTTPHeaders([
        (HTTPHeaders.Name.acceptLanguage.description, "en"),
        (signedInHeader, signedInAs)
    ])
    let req = Request(
        application: app,
        method: .GET,
        url: URI(path: uriStr),
        headers: headers,
        collectedBody: .init(),
        on: app.eventLoopGroup.next()
    )

    let response = try await app.responder.respond(to: req).get()
    guard response.status == .ok else {
        throw Abort(.internalServerError, reason: "banner GET failed: \(response.status)")
    }
    let data = try #require(response.body.data)
    let body: BannerBody = try data.fromJSON()
    return body.signedInAs
}

// MARK: - Tests (spec Task 5 / test group 4)

@Suite("useAppState — load-phase app state")
struct AppStateTests {
    /// The builder runs per request in the LOAD phase: it reads the `Vapor.Request` (here, a
    /// header), and the value it derives lands in `context.appState` in the projection. Two
    /// requests with different headers prove it runs per request, not once.
    @Test func builderReadsRequestPerRequestAndLandsInProjection() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try app.useAppState(SessionBanner.self) { req in
                SessionBanner(userName: req.headers.first(name: signedInHeader) ?? "anonymous")
            }
            try app.register(request: BannerRequest.self)
        } _: { app, _ in
            let first = try await serveBanner(on: app, signedInAs: "Captain Ahab")
            #expect(first == "Captain Ahab")

            let second = try await serveBanner(on: app, signedInAs: "First Mate")
            #expect(second == "First Mate")
        }
    }

    /// A `Void` AppState needs no registration — the existing zero-data screen serves with no
    /// `useAppState` call anywhere. The explicit pin that the default path stays zero-ceremony.
    @Test func voidAppStateNeedsNoRegistration() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            // No useAppState call — TestViewModel's AppState is Void.
            try app.register(request: TestViewModelRequest.self)
        } _: { app, _ in
            let prefix = "http://localhost"
            let base = try #require(URL(string: prefix))
            let url = try #require(try base.appending(serverRequest: TestViewModelRequest()))
            let uriStr = String(url.absoluteString.trimmingPrefix(prefix))
            let headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            let req = Request(
                application: app,
                method: .GET,
                url: URI(path: uriStr),
                headers: headers,
                collectedBody: .init(),
                on: app.eventLoopGroup.next()
            )

            let response = try await app.responder.respond(to: req).get()
            #expect(response.status == .ok)
        }
    }

    /// A request whose `ResponseBody.AppState` is non-`Void`, registered with NO prior
    /// `useAppState` for that type, fails at `register(request:)` — a boot error, not a
    /// first-request surprise. The message names the AppState type and points at `useAppState`.
    @Test func nonVoidAppStateWithoutBuilderFailsAtBoot() async throws {
        do {
            try await withFluentTestApp { app in
                try app.register(request: BannerRequest.self) // no useAppState registered
            } _: { _, _ in }
            Issue.record("expected register(request:) to throw at boot for a non-Void AppState with no builder")
        } catch let error as ContainmentError {
            guard case .missingAppStateBuilder = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("SessionBanner"))
            #expect(error.debugDescription.contains("useAppState"))
        }
    }

    /// Registering the same AppState type twice is a boot error — silent last-wins would hide the
    /// duplicate. The message names the AppState type.
    @Test func duplicateUseAppStateThrowsAtBoot() async throws {
        do {
            try await withFluentTestApp { app in
                try app.useAppState(SessionBanner.self) { _ in SessionBanner(userName: "first") }
                try app.useAppState(SessionBanner.self) { _ in SessionBanner(userName: "second") }
            } _: { _, _ in }
            Issue.record("expected the second useAppState(SessionBanner.self) to throw")
        } catch let error as ContainmentError {
            guard case .duplicateAppStateBuilder = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("SessionBanner"))
        }
    }

    /// End-to-end: the AppState value the builder produced is visible in the projection through a
    /// genuine GET. The builder ignores the request here and returns a constant, so the asserted
    /// value can only have arrived via `context.appState`.
    @Test func appStateVisibleInProjectionThroughGet() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try app.useAppState(SessionBanner.self) { _ in SessionBanner(userName: "David") }
            try app.register(request: BannerRequest.self)
        } _: { app, _ in
            let signedInAs = try await serveBanner(on: app, signedInAs: "ignored-header")
            #expect(signedInAs == "David")
        }
    }
}
