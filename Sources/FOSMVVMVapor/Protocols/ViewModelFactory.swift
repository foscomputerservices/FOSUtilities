// ViewModelFactory.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

public struct VaporModelFactoryContext<Request: ViewModelRequest>: ViewModelFactoryContext {
    public let req: Vapor.Request
    public let vmRequest: Request

    public var appVersion: SystemVersion {
        get throws {
            try req.applicationVersion()
        }
    }

    public init(req: Vapor.Request, vmRequest: Request) {
        self.req = req
        self.vmRequest = vmRequest
    }
}

public protocol VaporViewModelFactory: ViewModelFactory & Vapor.AsyncResponseEncodable
    where Self: RequestableViewModel, Context == VaporModelFactoryContext<Request> {}

public extension VaporViewModelFactory {
    static func model(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
        try await model(context: .init(req: req, vmRequest: vmRequest))
    }

    /// Default `AsyncResponseEncodable` conformance that serves the ``ViewModel``
    /// *localized to the request's* [Accept-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language).
    ///
    /// The server route (``VaporServerRequestHost``) returns the *unlocalized*
    /// ``ViewModel`` straight from the handler and relies on Vapor's
    /// `AsyncResponseEncodable` to build the HTTP `Response`. That is the single
    /// point where localization-on-serve must happen — the request-binding
    /// `VaporServerRequestMiddleware` only parses the query into the `ServerRequest`
    /// and does no response post-processing.
    ///
    /// **SRP:** encoding-with-localization has exactly one home — the shared
    /// ``ServerRequestBody/buildResponse(_:)`` (which encodes through
    /// `req.localizingEncoder` and stamps the `SystemVersion` header). This default
    /// delegates there so no conformer re-implements it. **OCP:** a
    /// ``VaporViewModelFactory`` therefore supplies only `model(context:)`; adding
    /// per-type `encodeResponse` boilerplate would be a red flag that localization
    /// leaked out of its single owner.
    func encodeResponse(for request: Vapor.Request) async throws -> Vapor.Response {
        try buildResponse(request)
    }
}
