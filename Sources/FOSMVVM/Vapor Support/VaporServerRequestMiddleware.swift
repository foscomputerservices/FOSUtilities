// VaporServerRequestMiddleware.swift
//
// Created by David Hunt on 9/11/24
// Copyright 2024 FOS Services, LLC
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

#if canImport(Vapor)
import FOSFoundation
import Foundation
import Vapor

enum VaporServerRequestMiddlewareError: Error {
    case missingQuery
    case missingRequest
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

    fileprivate func serverRequestQuery<Q: ServerRequestQuery>(ofType queryType: Q.Type) throws -> Q? {
        guard queryType != EmptyQuery.self else { return nil }
        guard
            let urlQueryStr = url.query,
            !urlQueryStr.isEmpty,
            let queryStr = urlQueryStr.removingPercentEncoding
        else {
            return nil
        }

        return try queryStr.fromJSON()
    }
}
#endif
