// Request+FOS.swift
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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

public extension Request {
    // MARK: Information Retrieval Routines

    /// Retrieves the *ServerRequestAction* from the Vapor Request
    ///
    /// The *Request*'s method and url are used to map to FOS's
    /// *ServerRequestAction*.
    ///
    /// - Throws: If the request cannot be mapped to a *ServerRequestAction*
    func requestAction() throws -> ServerRequestAction {
        try .init(httpMethod: method, uri: url)
    }

    /// Retrieves the *SystemVersion* from the Vapor Request
    func applicationVersion() throws -> SystemVersion {
        guard
            let versionHeaderData = headers[URLRequest.systemVersioningHeader].first,
            !versionHeaderData.isEmpty
        else {
            throw Abort(.badRequest)
        }

        return try versionHeaderData.fromJSON()
    }

    // MARK: Compatibility and Security Routines

    /// Require that the application's *SystemVersion*  is compatible with the server
    ///
    /// Checks the requests's headers for a *SystemVersion.systemVersioningHeader* and,
    /// if found, verifies that the SystemVersion encoded in that header's value is compatible
    /// with the server's version.
    func requireCompatibleAppVersion() throws {
        let appVersion = try applicationVersion()
        guard appVersion.isCompatible(with: .current) else {
            throw Abort(.notAcceptable)
        }
    }
}
