// ServerRequest+Fetch.swift
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
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension ServerRequest {
    /// Creates a unique URL for the ``ServerRequest``
    ///
    /// - Parameter baseURL: The base *URL* of the web service (e.g., "https://my.server.com")
    /// - Returns: A *URL* that can be used to process the ``ServerRequest``
    /// - Throws: ``ServerRequestProcessingError`` if unable to create the URL
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
            throw ServerRequestProcessingError.internalError(
                message: "Unable to build URLComponents?"
            )
        }

        var urlComps = urlOptComps
        urlComps.path = "/" + Self.path.trimmingCharacters(in: .init(charactersIn: "/"))
        urlComps.query = queryStr // URLComponents automatically % encodes the string
        urlComps.fragment = fragmentStr

        guard let result = urlComps.url else {
            throw ServerRequestProcessingError.internalError(
                message: "Unable to encode URL for type \(String(describing: Self.self))"
            )
        }

        return result
    }

    /// Send the ``ServerRequest`` to the web service and wait for a response
    ///
    /// Upon receipt of a response from the server, ``responseBody`` will be updated with
    /// the response from the server.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let serverRequest = MyServerRequest(/* .. params */)
    /// let response = try await serverRequest.processRequest(
    ///     baseURL: URL(string: "https://my.webservice.com")!
    /// )
    ///
    /// assert(response == serverRequest.response)
    /// ```
    ///
    /// - Parameters:
    ///   - baseURL: The baseURL for the web service
    ///   - headers: Any additional HTTP headers to send to the request
    ///   - session: An optional *URLSession* to use to process the request (default: *DataFetch.urlSessionConfiguration()*)
    /// - Returns: ``ServerRequest/ResponseBody``
    @discardableResult
    func processRequest(baseURL: URL, headers: [(field: String, value: String)]? = nil, session: URLSession? = nil) async throws -> ResponseBody? {
        let dataFetch: DataFetch<URLSession> = if let session {
            DataFetch(urlSession: session)
        } else {
            .default
        }

        var requestHeaders = SystemVersion.current.versioningHeaders
        if let headers {
            requestHeaders += headers
        }

        responseBody = try await dataFetch.send(
            data: requestBody?.toJSONData() ?? Data(),
            to: requestURL(baseURL: baseURL),
            httpMethod: action.httpMethod,
            headers: requestHeaders,
            locale: Locale.current,
            errorType: Self.ResponseError.self
        )

        return responseBody
    }

    #if canImport(SwiftUI)
    /// Send the ``ServerRequest`` to the web service and wait for a response
    ///
    /// Upon receipt of a response from the server, ``responseBody`` will be updated with
    /// the response from the server.
    ///
    /// - Parameter mvvmEnv: The current ``MVVMEnvironment`` for the client application
    func processRequest(mvvmEnv: MVVMEnvironment) async throws {
        try await processRequest(
            baseURL: mvvmEnv.serverBaseURL,
            headers: mvvmEnv.requestHeaders.map { key, value in
                (field: key, value: value)
            }
        )
    }
    #endif
}

public enum ServerRequestProcessingError: Error, CustomDebugStringConvertible {
    case internalError(message: String)

    public var debugDescription: String {
        switch self {
        case .internalError(message: let msg):
            "ServerRequestProcessingError: Internal Error: \(msg)"
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
        case .delete, .destroy: "DELETE"
        }
    }
}
