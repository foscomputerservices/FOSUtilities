// DataFetch.swift
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

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A simplified interface for performing asynchronous REST-Style requests
///
/// This interface is expected to be used with **Codable** types.  This provides
/// for type-safe communication between the application and the server.
///
/// # URL Extension Methods
///
/// While ``DataFetch`` can be used directly, it is expected that the
/// extension methods on **URL** are used more often.  Those methods provide
/// the same power as calling ``DataFetch`` directly, but provide
/// a more concise API.
///
/// ## URL Example
///
/// ```swift
/// struct MyServerError: Decodable, Error { ... }
/// string MyType: Decodable { ... }
/// let url = URL(string: "https://myServer/myType")!
/// let myType: MyType = try await url.fetch(errorType: MyServerError.self)
/// ```
///
/// ## DataFetch Example
///
/// ```swift
/// struct MyServerError: Decodable, Error { ... }
/// string MyType: Decodable { ... }
/// let url = URL(string: "https://myServer/myType")!
/// let dataFetch = DataFetch<URLSession>.default
/// let myType: MyType = try await dataFetch.fetch(url, errorType: MyServerError.self)
/// ```
///
/// # Request Methods
///
/// The interface models itself after REST methodology:
///
///  - **fetch**: Performs a **GET** request
///  - **post**: Performs a **POST** request -- TODO: Change to create
///  - **update**: Performs a **PUT** request
///  - **delete**: Performs a **DELETE** request
///
///  # Error Handling
///
///  Each of the API functions has an overload that allows an **error type** to be specified.
///  This type should conform to **Decodable** and to **Error**.  When the response is
///  received from the server cannot be decoded, the an attempt is made to decode the
///  response using the error type and will throw that error if successful.
///
///  ## HTTP Status Codes
///
///  Not all server APIs indicate an error through [HTTP Status Codes](https://w.wiki/XeK).
///  Some APis will return a 200 code, but a result that contains information as to whether the
///  request was successful.  Using **error type** will allow these errors to be surfaced.
///  During response processing and attempt will be made to decode the response to the
///  expected **ResultValue** type.  If that fails, then an attempt will be made to decode
///  the response to the **error type** type.  If the **error type** decoding succeeds,
///  that resulting error will be thrown.
///
/// - Note: Typically **Session** is of type **URLSession**, however during testing
///    **FOSTesting/MockURLSession** can be used.  For most cases, use
///     **DataFetch<URLSession>.default** to create an instance.
public final class DataFetch<Session: URLSessionProtocol>: Sendable {
    private let urlSession: Session

    /// Returns an instance that uses **DataFetch.urlSessionConfiguration**
    ///
    /// ## Example
    ///
    /// ```swift
    /// let dataFetch = DataFetch<URLSession>.default
    /// ```
    public static var `default`: DataFetch<Session> {
        .init(
            urlSession: .session(
                config: DataFetch.urlSessionConfiguration()
            )
        )
    }

    /// Fetches the given data of type **ResultValue** from the given **URL**
    ///
    /// The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    ///  | Accept-Language | <provided locale> |
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyServerData: Decodable {
    ///   let value1: String
    ///   let value2: String
    /// }
    ///
    /// let serverUrl = URL(string: "https://myserver.com/myServerData")!
    /// let dataFetch = DataFetch<URLSession>.default
    /// let myServerData: MyServerData = try await dataFetch.fetch(serverUrl)
    /// ```
    ///
    /// - Parameters:
    ///   - url: The **URL** that identifies the source of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - locale: An optional [Locale](https://developer.apple.com/documentation/foundation/locale) specification
    public func fetch<ResultValue: Decodable>(_ url: URL, headers: [(field: String, value: String)]? = nil, locale: Locale? = nil) async throws -> ResultValue {
        try await send(
            to: url.absoluteString,
            httpMethod: "GET",
            headers: headers,
            locale: locale
        )
    }

    /// Fetches the given data of type **ResultValue** from the given **URL**
    ///
    /// The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    ///  | Accept-Language | <provided locale> |
    ///
    /// - Parameters:
    ///   - url: The **URL** that identifies the source of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - locale: An optional [Locale](https://developer.apple.com/documentation/foundation/locale) specification
    ///   - errorType: An **Error** type to attempt to decode returned data as an error if unable to decode as **ResultValue**
    public func fetch<ResultValue: Decodable>(_ url: URL, headers: [(field: String, value: String)]? = nil, locale: Locale? = nil, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await send(
            to: url.absoluteString,
            httpMethod: "GET",
            headers: headers,
            locale: locale,
            errorType: errorType
        )
    }

    /// Sends **Data** to  the given **URL**
    ///
    /// The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    ///
    /// - Parameters:
    ///   - data: The **Data** to **POST** to *url*
    ///   - url: The **URL** that identifies the destination of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    public func post<ResultValue: Decodable>(data: some Encodable, to url: URL, headers: [(field: String, value: String)]? = nil) async throws -> ResultValue {
        let jsonData: Data
        do {
            jsonData = try data.toJSONData()
        } catch let jsonError as JSONError {
            throw DataFetchError.fromJSONError(jsonError)
        } catch let e {
            throw e
        }

        return try await send(
            data: jsonData,
            to: url.absoluteString,
            httpMethod: "POST",
            headers: headers,
            locale: nil
        )
    }

    /// Sends **Data** to  the given **URL**
    ///
    /// The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    ///
    /// - Parameters:
    ///   - data: The **Data** to **POST** to *url*
    ///   - url: The **URL** that identifies the destination of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - errorType: An **Error** type to attempt to decode returned data as an error if unable to decode as **ResultValue**
    public func post<ResultValue: Decodable>(data: some Encodable, to url: URL, headers: [(field: String, value: String)]? = nil, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        let jsonData: Data
        do {
            jsonData = try data.toJSONData()
        } catch let jsonError as JSONError {
            throw DataFetchError.fromJSONError(jsonError)
        } catch let e {
            throw e
        }

        return try await send(
            data: jsonData,
            to: url.absoluteString,
            httpMethod: "DELETE",
            headers: headers,
            locale: nil,
            errorType: errorType
        )
    }

    /// Sends **Data** to  the given **URL** with the HTTPMethod "DELETE"
    ///
    /// The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    ///
    /// - Parameters:
    ///   - data: The **Data** to send with the **DELETE** request to *url*
    ///   - url: The **URL** that identifies the location of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    public func delete<ResultValue: Decodable>(data: some Encodable, at url: URL, headers: [(field: String, value: String)]? = nil) async throws -> ResultValue {
        let jsonData: Data
        do {
            jsonData = try data.toJSONData()
        } catch let jsonError as JSONError {
            throw DataFetchError.fromJSONError(jsonError)
        } catch let e {
            throw e
        }

        return try await send(
            data: jsonData,
            to: url.absoluteString,
            httpMethod: "DELETE",
            headers: headers,
            locale: nil
        )
    }

    /// Sends **Data** to  the given **URL**
    ///
    /// The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    ///
    /// - Parameters:
    ///   - data: The **Data** to send with the **DELETE** request to *url*
    ///   - url: The **URL** that identifies the location of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - errorType: An **Error** type to attempt to decode returned data as an error if unable to decode as **ResultValue**
    public func delete<ResultValue: Decodable>(data: some Encodable, at url: URL, headers: [(field: String, value: String)]? = nil, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        let jsonData: Data
        do {
            jsonData = try data.toJSONData()
        } catch let jsonError as JSONError {
            throw DataFetchError.fromJSONError(jsonError)
        } catch let e {
            throw e
        }

        return try await send(
            data: jsonData,
            to: url.absoluteString,
            httpMethod: "DELETE",
            headers: headers,
            locale: nil,
            errorType: errorType
        )
    }

    // MARK: Initialization Methods

    public init(urlSession: Session) {
        self.urlSession = urlSession
    }

    /// Returns a 'standard' **URLSessionConfiguration**
    ///
    /// - Parameters:
    ///   - userToken: A *Bearer* token that is sent in the *Authorization* HTTP header
    ///   - allowCellular: Allow requests to be made over cellular connections (default: true)
    public static func urlSessionConfiguration(forUserToken userToken: String? = nil, allowCellular: Bool = true) -> URLSessionConfiguration {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.allowsCellularAccess = allowCellular
        sessionConfig.isDiscretionary = false
        if let userToken {
            sessionConfig.httpAdditionalHeaders = [
                "Authorization": "Bearer \(userToken)"
            ]
        }

        return sessionConfig
    }
}

private extension DataFetch {
    /// - Throws: ``DataFetchError`` or **errorType**
    func send<ResultValue: Decodable>(data: Data? = nil, to urlStr: String, httpMethod: String, headers: [(field: String, value: String)]?, locale: Locale?) async throws -> ResultValue {
        do {
            return try await send(
                data: data,
                to: urlStr,
                httpMethod: httpMethod,
                headers: headers,
                locale: locale,
                errorType: DummyError.self
            )
        } catch let error as DataFetchError {
            throw error
        } catch let e {
            // This shouldn't happen as the only real two possibilities
            // are DataFetchError or DummyError, but DummyError should
            // never occur
            throw e
        }
    }

    /// - Throws: ``DataFetchError`` or **errorType**
    func send<ResultValue: Decodable>(data: Data? = nil, to urlStr: String, httpMethod: String, headers: [(field: String, value: String)]?, locale: Locale?, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        let urlStr = urlStr.trimmingSuffix("?")
        guard let url = URL(string: urlStr) else {
            throw DataFetchError.badURL("Unable to convert \(urlStr) to URL???")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = httpMethod

        var acceptSpecified = false
        var contentTypeSpecified = false
        var acceptEncodingSpecified = false

        var expectedMimeType: String?

        if let headers {
            for header in headers {
                urlRequest.setValue(header.value, forHTTPHeaderField: header.field)

                switch header.field.lowercased() {
                case "accept":
                    acceptSpecified = true
                    expectedMimeType = header.value
                case "content-type": contentTypeSpecified = true
                case "accept-encoding": acceptEncodingSpecified = true
                default: continue
                }
            }
        }

        if let locale {
            urlRequest.setValue(
                locale.identifier,
                forHTTPHeaderField: "Accept-Language"
            )
        }

        if !acceptSpecified {
            urlRequest.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Accept")
            expectedMimeType = "application/json"
        }
        if !contentTypeSpecified {
            urlRequest.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if !acceptEncodingSpecified {
            urlRequest.setValue("deflate, gzip, *", forHTTPHeaderField: "Accept-Encoding")
        }

        if let data {
            urlRequest.httpBody = data
        }

        let mimeType = expectedMimeType // Remove mutability

        return try await withCheckedThrowingContinuation { continuation in
            urlSession
                .dataTask(with: urlRequest) { data, response, e in
                    do {
                        let result: ResultValue = try Self.completionHandler(
                            responseData: data,
                            response: response,
                            error: e,
                            expectedMimeType: mimeType,
                            errorType: errorType
                        )

                        continuation.resume(returning: result)
                    } catch let e {
                        continuation.resume(throwing: e)
                    }
                }
                .resume()
        }
    }

    private static func completionHandler<ResultValue: Decodable, ResultError: Decodable & Error>(responseData: Data?, response: URLResponse?, error: Error?, expectedMimeType: String?, errorType: ResultError.Type) throws -> ResultValue {
        do {
            try checkResponse( // DataFetchError
                response: response,
                error: error,
                expectedMimeType: expectedMimeType
            )

            if let responseData {
                do {
                    let result: ResultValue = if ResultValue.self is String.Type || ResultValue.self is String?.Type {
                        // swiftlint:disable force_cast
                        // swiftlint:disable optional_data_string_conversion
                        String(decoding: responseData, as: UTF8.self) as! ResultValue
                        // swiftlint:enable force_cast
                        // swiftlint:enable optional_data_string_conversion
                    } else {
                        try responseData.fromJSON()
                    }

                    return result
                } catch let jsonError as JSONError {
                    throw DataFetchError.fromJSONError(jsonError)
                } catch let e {
                    throw e
                }
            } else {
                throw DataFetchError.noDataReceived
            }
        } catch let e as DecodingError {
            // We couldn't convert the data to the expected success type, so
            // attempt to convert the server's response to ResultError type
            if errorType != DummyError.self, let responseData, let resultError: ResultError = try? responseData.fromJSON() { // ResultError
                throw resultError
            } else if let responseData {
                // We couldn't convert to to ResultError, so surface the DecodingError
                throw DataFetchError.decoding(error: e, responseData: responseData)
            } else {
                throw e
            }
        } catch let e as DataFetchError {
            if errorType != DummyError.self, let responseData, let resultError: ResultError = try? responseData.fromJSON() {
                throw resultError
            }

            throw e
        } catch let e {
            if errorType != DummyError.self, let responseData, let resultError: ResultError = try? responseData.fromJSON() {
                throw resultError
            }

            throw e
        }
    }

    @discardableResult private static func checkResponse(response: URLResponse?, error: Swift.Error?, expectedMimeType: String?) throws -> HTTPURLResponse {
        if let error {
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            fatalError("Expected to receive an 'HTTPURLResponse', but received '\(String(describing: type(of: response.self)))'")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DataFetchError.badStatus(httpStatusCode: httpResponse.statusCode)
        }

        try checkMimeType(
            response: httpResponse,
            expectedMimeType: expectedMimeType
        )

        return httpResponse
    }

    private static func checkMimeType(response: HTTPURLResponse, expectedMimeType: String?) throws {
        guard let expectedMimeType else { return }

        guard let mimeType = response.mimeType else {
            throw DataFetchError.badResponseMimeType("<None Received>")
        }

        guard mimeType.lowercased().starts(with: expectedMimeType.lowercased()) else {
            throw DataFetchError.badResponseMimeType(mimeType)
        }
    }
}

private struct DummyError: Decodable, Error {}
