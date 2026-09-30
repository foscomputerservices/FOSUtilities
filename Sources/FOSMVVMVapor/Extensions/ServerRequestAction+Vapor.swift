// ServerRequestAction+Vapor.swift
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

import FOSMVVM
import Foundation
import Vapor

public extension ServerRequestAction {
    /// Maps the *HTTPMethod* and *URI* to a *ServerRequestAction*
    ///
    /// - Parameters:
    ///   - httpMethod: The *Request*'s *HTTPMethod*
    ///   - uri: The *Requests*'s *URI*
    ///
    /// - Throws: ``ServerRequestActionError`` if the request cannot be mapped
    init(httpMethod: HTTPMethod, uri: URI) throws {
        switch httpMethod {
        case .GET: self = .show
        case .POST: self = .create
        case .PUT: self = .replace
        case .PATCH: self = .update
        case .DELETE:
            // The destroy route names itself in a path component, and the request's identifying
            // arguments follow it (ControllerRouting.path(for:args:)), so the component is not
            // necessarily the last one.
            let components = uri.path.split(separator: "/", omittingEmptySubsequences: true)
            self = components.contains("destroy") ? .destroy : .archive
        default:
            throw ServerRequestActionError.unknownHTTPMethod(httpMethod)
        }
    }
}

public enum ServerRequestActionError: Error, CustomDebugStringConvertible {
    case unknownHTTPMethod(_ method: HTTPMethod)

    public var debugDescription: String {
        switch self {
        case .unknownHTTPMethod(let method):
            "Unknown HTTP method: \(method)"
        }
    }
}
