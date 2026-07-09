// VaporResponseBodyFactoryTests.swift
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

// Grows from ServedRequestRouteTests: a served body asserted end-to-end through the real
// route + localization pipeline. Here the door is `register(request:)` (the C8 seam) and the
// body is a zero-data factory — no `ComposableFactory` trait, no plan.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("VaporResponseBodyFactory serving")
struct VaporResponseBodyFactoryTests {
    /// A zero-data screen — a factory-only body with NO ``ComposableFactory`` trait — serves
    /// through `register(request:)`: a localized body plus the `SystemVersion` response header.
    @Test func zeroDataScreenServesWithoutTrait() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
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
            #expect(response.headers[SystemVersion.httpHeader].first != nil)

            let data = try #require(response.body.data)
            let body: TestViewModel = try data.fromJSON()
            #expect(try body.aLocalizedString.localizedString != "")
        }
    }

    /// `X-FOS-Version` attaches exactly once. `buildResponse` and `buildJSONResponse` each stamp the
    /// version; before the `replaceOrAdd` fix the appending `add` left the header on the served
    /// response TWICE — a client reading `.first` was unaffected, but the duplicate was a latent
    /// wire defect. Assert the served header carries exactly one value.
    @Test func servedResponseCarriesExactlyOneVersionHeader() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
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
            #expect(response.headers[SystemVersion.httpHeader].count == 1)
        }
    }
}
