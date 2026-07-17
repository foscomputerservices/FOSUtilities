// VaporServerRequestMiddleware.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

enum VaporServerRequestMiddlewareError: Error, CustomDebugStringConvertible {
    case missingRequest

    var debugDescription: String {
        switch self {
        case .missingRequest:
            "requireServerRequest() found no bound ServerRequest on this Vapor.Request. The typed request is bound during routing by VaporServerRequestMiddleware, which is installed only when the route is registered through the FOS path — register(request:app:), or routes.register(collection:) on a ServerRequestController. A hand-rolled route that calls requireServerRequest() without that middleware always lands here; register it through one of those instead."
        }
    }
}

final class VaporServerRequestMiddleware<R: ServerRequest>: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // The URL is parsed exactly ONCE — here. The bound instance carries query AND sort,
        // and everything downstream (plan resolution, projection) reads the instance; nothing
        // re-parses the URL (no second source of truth).
        let query = try req.serverRequestQuery(ofType: R.Query.self)
        let sort = try req.serverRequestSort(ofType: R.Sort.self)
        req.serverRequest_set(R(
            query: query,
            sort: sort,
            fragment: nil,
            requestBody: nil,
            responseBody: nil
        ))

        return try await next.respond(to: req)
    }
}

extension Vapor.Request {
    func requireServerRequest<R: ServerRequest>() throws -> R {
        guard let request: R = serverRequest() else {
            throw VaporServerRequestMiddlewareError.missingRequest
        }

        return request
    }

    func serverRequest<R: ServerRequest>() -> R? {
        storage[ServerRequestStorageKey<R>.self]
    }

    fileprivate func serverRequest_set<R: ServerRequest>(_ newValue: R) {
        storage[ServerRequestStorageKey<R>.self] = newValue
    }

    private struct ServerRequestStorageKey<R: ServerRequest>: StorageKey {
        typealias Value = R
    }
}
