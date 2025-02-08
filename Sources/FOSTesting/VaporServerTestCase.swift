// VaporServerTestCase.swift
//
// Created by David Hunt on 9/11/24
// Copyright 2024 FOS Computer Services, LLC
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

#if canImport(Vapor) && DEBUG
import FOSFoundation
@testable import FOSMVVM
@testable import FOSMVVMVapor
import Foundation
import Testing
import Vapor

public final class VaporServerRequestTest<Request>: AnyObject, Sendable where Request: ServerRequest, Request.ResponseBody: VaporViewModelFactory {
    private let vaporApp: Vapor.Application

    public init(for request: Request.Type, bundle: Bundle, resourceDirectoryName: String = "Resources") throws {
        self.vaporApp = Application()
        try vaporApp.initYamlLocalization(
            bundle: bundle,
            resourceDirectoryName: resourceDirectoryName
        )
        try vaporApp.routes.register(
            collection: VaporServerRequestHost<Request>()
        )
        try vaporApp.start()
    }

    public func test(request: Request, locale: Locale, sourceLocation: SourceLocation = #_sourceLocation) async throws -> Request.ResponseBody {
        let response: Request.ResponseBody = try #require(
            try await vaporApp.process(
                request: request,
                locale: locale,
                sourceLocation: sourceLocation
            )
        ) as! Request.ResponseBody // swiftlint:disable:this force_cast
        return response
    }

    deinit {
        vaporApp.shutdown()
    }
}

private extension Application {
    func process<Request: ServerRequest>(request: Request, locale: Locale, sourceLocation: SourceLocation) async throws -> Request.RequestBody? {
        let prefix = "http://localhost"
        guard let url = try URL(string: prefix)?.appending(serverRequest: request) else {
            #expect(Bool(false), "Unable to derive URL", sourceLocation: sourceLocation)
            return nil
        }

        let headers = HTTPHeaders([
            (HTTPHeaders.Name.acceptLanguage.description, locale.identifier)
        ])

        let uriStr = url.absoluteString.trimmingPrefix(prefix)
        let request = Vapor.Request(
            application: self,
            method: .GET,
            url: URI(path: uriStr),
            headers: headers,
            collectedBody: .init(),
            on: eventLoopGroup.next()
        )

        let response = try await responder.respond(to: request).get()
        try #require(response.status == .ok, sourceLocation: sourceLocation)
        let data = try #require(response.body.data, sourceLocation: sourceLocation)

        return try data.fromJSON()
    }
}

#endif
