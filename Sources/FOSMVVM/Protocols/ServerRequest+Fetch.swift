// ServerRequest+Fetch.swift
//
// Created by David Hunt on 9/4/24
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
import Foundation

public extension ServerRequest {
    func requestURL(baseURL: URL? = nil) throws -> URL {
        // URLComponents does *not* encode the = or the &
        let queryStr = try query?.toJSON()
            .replacingOccurrences(of: "=", with: "%3D")
            .replacingOccurrences(of: "&", with: "%26")
        let fragmentStr = try fragment?.toJSON()

        guard let urlOptComps = URLComponents(
            url: baseURL ?? URL(string: "/")!,
            resolvingAgainstBaseURL: true
        ) else {
            throw ServerRequestError.internalError(
                message: "Unable to build URLComponents?"
            )
        }

        var urlComps = urlOptComps
        urlComps.path = "/" + Self.path.trimmingCharacters(in: .init(charactersIn: "/"))
        urlComps.query = queryStr // URLComponents automatically % encodes the string
        urlComps.fragment = fragmentStr

        guard let result = urlComps.url else {
            throw ServerRequestError.internalError(
                message: "Unable to encode URL for type \(String(describing: Self.self))"
            )
        }

        return result
    }

//    func processRequest(baseURL: URL) async throws -> Self {
//        DataFetch.default.send(
//            data: <#T##Data#>,
//            to: requestURL(baseURL: baseURL),
//            httpMethod: action.httpMethod,
//            headers: <#T##[(field: String, value: String)]?#>,
//            errorType: <#T##(Decodable & Error).Protocol#>
//        )
//    }
}

public enum ServerRequestError: Error, CustomDebugStringConvertible {
    case internalError(message: String)

    public var debugDescription: String {
        switch self {
        case .internalError(message: let msg):
            "ServerRequestError: Internal Error: \(msg)"
        }
    }
}

private extension ServerRequestAction {
    var httpMethod: String {
        switch self {
        case .show: "GET"
        case .create: "POST"
        case .update: "PATCH"
        case .replace: "PUT"
        case .delete: "DELTE"
        }
    }
}
