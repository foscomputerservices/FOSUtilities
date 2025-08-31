// VaporServerTestCase.swift
//
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

#if canImport(FOSMVVMVapor) && DEBUG
import FOSFoundation
@testable import FOSMVVM
@testable import FOSMVVMVapor
import Foundation
import Vapor

public final class VaporServerRequestTest<Request>: AnyObject, Sendable where Request: ServerRequest, Request.ResponseBody: VaporViewModelFactory {
    private let vaporApp: Vapor.Application

    public init(for request: Request.Type, bundle: Bundle, resourceDirectoryName: String = "Resources") async throws {
        self.vaporApp = try await Application.make()
        try vaporApp.initYamlLocalization(
            bundle: bundle,
            resourceDirectoryName: resourceDirectoryName
        )
        try vaporApp.routes.register(
            collection: VaporServerRequestHost<Request>()
        )
        try await vaporApp.startup()
    }

    public func test(request: Request, locale: Locale) async throws -> Request.ResponseBody {
        guard let response: Request.ResponseBody = try await vaporApp.process(
            request: request,
            locale: locale
        ) as? Request.ResponseBody
        else {
            throw FOSVaporServerError.error("Unable to process request ResponseBody")
        }
        return response
    }

    deinit {
        vaporApp.shutdown()
    }
}

private extension Application {
    func process<Request: ServerRequest>(request: Request, locale: Locale) async throws -> Request.RequestBody? {
        let prefix = "http://localhost"
        guard let url = try URL(string: prefix)?.appending(serverRequest: request) else {
            throw FOSVaporServerError.error("Unable to derive URL")
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
        guard response.status == .ok else {
            throw FOSVaporServerError.error("Received invalid response staus: \(response.status); expected ok")
        }

        guard let data = response.body.data else {
            throw FOSVaporServerError.error("Respone body empty")
        }

        return try data.fromJSON()
    }
}

public enum FOSVaporServerError: Error, CustomDebugStringConvertible {
    case error(_ message: String)

    public var debugDescription: String {
        switch self {
        case .error(let message): "FOSLocalizableError: \(message)"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}

#endif
