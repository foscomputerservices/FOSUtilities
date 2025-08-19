// Response+FOS.swift
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
import Vapor

public extension ServerRequestBody {
    /// Converts the *ServerRequestBody* to a Vapor Response
    ///
    /// The processing of a *ServerRequest* by the web service might entail producing
    /// a response, which is a sub type of *ServerRequestBody*.  In order to send this
    /// response back, it needs to be encoded into a Vapor Response.
    ///
    /// Additionally, the *SystemVersion* header is added to the Vapor Response's
    /// headers.
    ///
    /// - Parameter req: The current Vapor Request
    /// - Returns: A Vapor Response including the ServerRequestBody
    func buildResponse(_ req: Vapor.Request) throws -> Response {
        try Response.buildJSONResponse(req, content: self)
            .addSystemVersion()
    }
}

public extension Response {
    /// Updates the headers of the *Response* to include the current
    /// *SystemVersion* of the web service
    ///
    /// The *SystemVersion* will be checked by the client to ensure version compatibility
    /// with the web service.
    @discardableResult func addJSONContentType() -> Response {
        // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type
        headers.replaceOrAdd(
            name: .contentType,
            value: "application/json; charset=utf-8"
        )

        return self
    }

    /// Updates the headers of the *Response* to include the current
    /// *SystemVersion* of the web service
    ///
    /// The *SystemVersion* will be checked by the client to ensure version compatibility
    /// with the web service.
    @discardableResult func addSystemVersion() throws -> Response {
        let version = try SystemVersion.current.toJSON()

        headers.add(name: SystemVersion.httpHeader, value: version)

        return self
    }
}

private extension Vapor.Response {
    static func buildJSONResponse(_ req: Vapor.Request, content: some Encodable) throws -> Vapor.Response {
        let response = Vapor.Response()

        // Add the version of the server for compatibility checks
        try response.addSystemVersion()

        // Add relevant HTTP Headers
        response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")

        // TODO: Add JavaScript cross-origin support

        try response.content.encode(content, using: req.viewModelEncoder)

        return response
    }
}
