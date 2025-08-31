// VaporServerRequestMiddleware.swift
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

enum VaporServerRequestMiddlewareError: Error, CustomDebugStringConvertible {
    case missingQuery
    case missingRequest

    var debugDescription: String {
        switch self {
        case .missingQuery:
            "VaporServerRequestMiddlewareError: Required Query missing"
        case .missingRequest:
            "VaporServerRequestMiddlewareError: Required Request missing"
        }
    }
}

final class VaporServerRequestMiddleware<R: ServerRequest>: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let query = try req.serverRequestQuery(ofType: R.Query.self)
        req.serverRequest_set(R(
            query: query,
            fragment: nil,
            requestBody: nil,
            responseBody: nil
        ))

        return try await next.respond(to: req)
    }
}

extension Request {
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
