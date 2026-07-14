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
        try await processRequestCapturingRegistrations(baseURL: baseURL, headers: headers, session: session).body
    }

    /// Internal live-delivery seam: the same fetch as `processRequest(baseURL:headers:session:)`, also
    /// returning the ViewModel's server-derived live registration set decoded from the
    /// `X-FOS-Registrations` response header (spec §3.4). The public overload delegates here and drops
    /// the registrations, so its observable behavior is byte-identical. Absent header ⇒ empty set; a
    /// malformed value ⇒ empty set (decided: a broken registration header must never fail the fetch —
    /// the screen simply degrades to fetch-once).
    ///
    /// Explicitly `internal` — this sits in a `public extension`, whose default would silently
    /// publish the wire seam onto ``ServerRequest``'s public surface.
    internal func processRequestCapturingRegistrations(baseURL: URL, headers: [(field: String, value: String)]? = nil, session: URLSession? = nil) async throws -> (body: ResponseBody?, registrations: [ModelIdentity]) {
        let dataFetch: DataFetch<URLSession> = if let session {
            DataFetch(urlSession: session)
        } else {
            .default
        }

        var requestHeaders = SystemVersion.current.versioningHeaders
        if let headers {
            requestHeaders += headers
        }

        let requestData: Data = if RequestBody.self == EmptyBody.self {
            Data()
        } else {
            try requestBody?.toJSONData() ?? Data()
        }

        let headerValue: String?
        // WireError is decode plumbing — unwrap so callers catch the payload
        // (the surface rejection or the request's typed ResponseError).
        do {
            if ResponseBody.self == EmptyBody.self {
                // An `EmptyBody` response carries no meaningful content, so its media type is irrelevant.
                // Fetch it as `String` (the one decode path that accepts ANY 2xx body) with the
                // received-MIME check disabled, discard the body, and synthesize the empty response. This
                // round-trips against a server that answers `application/json` `{}` (`buildResponse`) AND
                // one that answers `text/plain`/empty (a plain REST API) — neither type is
                // enforced, because there is nothing to type. A non-2xx still decodes the typed
                // `ResponseError` via `errorType`, unchanged.
                let (_, captured): (String, String?) = try await dataFetch.send(
                    data: requestData,
                    to: requestURL(baseURL: baseURL),
                    httpMethod: action.httpMethod,
                    headers: requestHeaders,
                    locale: Locale.current,
                    checkReceivedMimeType: false,
                    errorType: WireError<Self.ResponseError>.self,
                    capturingResponseHeader: ModelIdentity.registrationsHeader
                )
                responseBody = EmptyBody() as? ResponseBody
                headerValue = captured
            } else {
                let (body, captured): (ResponseBody, String?) = try await dataFetch.send(
                    data: requestData,
                    to: requestURL(baseURL: baseURL),
                    httpMethod: action.httpMethod,
                    headers: requestHeaders,
                    locale: Locale.current,
                    errorType: WireError<Self.ResponseError>.self,
                    capturingResponseHeader: ModelIdentity.registrationsHeader
                )
                responseBody = body
                headerValue = captured
            }
        } catch let wire as WireError<Self.ResponseError> {
            switch wire {
            case .surface(let rejection): throw rejection
            case .response(let error): throw error
            }
        }

        return (responseBody, LiveRegistrations.decode(headerValue))
    }

    /// Send the ``ServerRequest`` to the web service and wait for a response
    ///
    /// Upon receipt of a response from the server, ``responseBody`` will be updated with
    /// the response from the server.
    ///
    /// - Parameters
    ///   - mvvmEnv: The current ``MVVMEnvironment`` for the client application
    ///   - session: An optional *URLSession* to use to process the request (default: *DataFetch.urlSessionConfiguration()*)
    func processRequest(mvvmEnv: MVVMEnvironment) async throws {
        _ = try await processRequestCapturingRegistrations(mvvmEnv: mvvmEnv)
    }

    /// Internal live-delivery seam: the `mvvmEnv` fetch, additionally returning the response's live
    /// registration set (spec §3.4). Error handling matches `processRequest(mvvmEnv:)`; the bind
    /// resolver drives every server-hosted request through it — a non-live ViewModel simply ignores
    /// the returned set.
    ///
    /// Explicitly `internal` — this sits in a `public extension`, whose default would silently
    /// publish the wire seam onto ``ServerRequest``'s public surface.
    @discardableResult
    internal func processRequestCapturingRegistrations(mvvmEnv: MVVMEnvironment) async throws -> [ModelIdentity] {
        do {
            var headers = [(field: String, value: String)]()
            if ResponseBody.self == EmptyBody.self {
                headers.append((field: "Accept", value: "text/plain"))
            }
            for (key, value) in mvvmEnv.requestHeaders {
                headers.append((field: key, value: value))
            }

            // Credential headers append AFTER the static requestHeaders: headers apply to the
            // URLRequest in order (setValue), so on a duplicate field the per-request
            // credential wins.
            if let credentialProvider = mvvmEnv.clientCredentialProvider {
                headers += try await credentialProvider.credentialHeaders()
            }

            return try await processRequestCapturingRegistrations(
                baseURL: mvvmEnv.serverBaseURL,
                headers: headers,
                session: mvvmEnv.session
            ).registrations
        } catch let rejection as CredentialRejectedError {
            // A surface rejection always reaches the caller — recovery
            // (refresh credential, retry) is a call-site decision.
            throw rejection
        } catch let error as ServerRequestError {
            if let errorHandler = mvvmEnv.requestErrorHandler {
                errorHandler(self, error)
                return []
            } else {
                throw error
            }
        }
    }
}

/// Decodes the `X-FOS-Registrations` response header into a live-invalidation registration set.
enum LiveRegistrations {
    /// An absent or empty header ⇒ empty set. A malformed value also ⇒ empty set: a broken
    /// registration header must never fail the fetch (spec §3.4) — the screen degrades to
    /// fetch-once rather than surfacing an error the user cannot act on.
    static func decode(_ headerValue: String?) -> [ModelIdentity] {
        guard let headerValue, !headerValue.isEmpty else { return [] }
        return (try? headerValue.fromJSON()) ?? []
    }
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

/// The action→HTTP-method bijection, stated once. Consumed by both the client fetch path
/// (`processRequest`, above) and the server dispatch (`ServerRequestController.boot`), so it
/// is package-visible rather than restated per module.
package extension ServerRequestAction {
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
