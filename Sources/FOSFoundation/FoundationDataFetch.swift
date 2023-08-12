// FoundationDataFetch.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DataFetchError: Error {
    case message(_ message: String, responseData: Data? = nil)
    case decoding(error: DecodingError, responseData: Data)
    case badStatus(httpStatusCode: Int)
    case noDataReceived
    case badResponseMimeType(_ mimeType: String)

    public var localizedDescription: String {
        switch self {
        case .message(let message, let responseData):
            if let responseData, let responseStr = String(data: responseData, encoding: .utf8) {
                return "\(message) - \(responseStr)"
            } else {
                return message
            }
        case .decoding(let error, let responseData):
            if let responseStr = String(data: responseData, encoding: .utf8) {
                return "\(error.localizedDescription) - \(responseStr)"
            } else {
                return error.localizedDescription
            }
        case .badStatus(let code):
            return "Status code: \(code)"
        case .noDataReceived:
            return "No data received"
        case .badResponseMimeType(let mimeTime):
            return "Received unexpected mime type: '\(mimeTime)'"
        }
    }
}

/// A simplified  interface for performing REST-Style requests
public final class FoundationDataFetch {
    private let urlSession: URLSession

    /// Returns an instance that uses ``FoundationDataFetch.UrlSessionConfiguration``
    public static let `default`: FoundationDataFetch = .init(
        urlSession: .init(configuration: FoundationDataFetch.urlSessionConfiguration())
    )

    /// Fetches the given data of type ``ResultValue`` from the given ``URL``
    ///
    /// - Parameters:
    ///   - url: The ``URL`` that identifies the source of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///
    /// - Note: The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    public func fetch<ResultValue: Decodable>(_ url: URL, headers: [(field: String, value: String)]?) async throws -> ResultValue {
        try await send(
            to: url.absoluteString,
            httpMethod: "GET",
            headers: headers,
            errorType: DummyError.self
        )
    }

    /// Fetches the given data of type ``ResultValue`` from the given ``URL``
    ///
    /// - Parameters:
    ///   - url: The ``URL`` that identifies the source of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - errorType: An ``Error`` type to attempt to decode returned data as an error if unable to decode as ``ResultValue``
    ///
    /// - Note: The following headers are automatically sent to all requests unless they are provided in *headers*:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    public func fetch<ResultValue: Decodable>(_ url: URL, headers: [(field: String, value: String)]?, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await send(
            to: url.absoluteString,
            httpMethod: "GET",
            headers: headers,
            errorType: errorType
        )
    }

//    public func send<ResultValue: Decodable>(data: Data, to url: URL, httpMethod: String, headers: [(field: String, value: String)]?, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
//        try await send(
//            data: data,
//            to: url.absoluteString,
//            httpMethod: httpMethod,
//            headers: headers,
//            errorType: errorType
//        )
//    }

    // MARK: Initialization Methods

    public init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    /// Returns a 'standard' ``URLSessionConfiguration``
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

private extension FoundationDataFetch {
    func send<ResultValue: Decodable>(data: Data? = nil, to urlStr: String, httpMethod: String, headers: [(field: String, value: String)]?, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        guard let url = URL(string: urlStr) else {
            throw DataFetchError.message("Unable to convert \(urlStr) to URL???")
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
            try Self.checkResponse(
                response: response,
                error: error,
                expectedMimeType: expectedMimeType
            )

            if let responseData {
                let result: ResultValue

                if ResultValue.self is String.Type || ResultValue.self is String?.Type {
                    result = String(data: responseData, encoding: .utf8) as! ResultValue
                } else {
                    result = try responseData.fromJSON()
                }

                return result
            } else {
                throw DataFetchError.noDataReceived
            }
        } catch let e as DecodingError {
            // We couldn't convert the data to the expected success type, so
            // attempt to convert the server's response to ResultError type
            if errorType != DummyError.self, let responseData, let resultError: ResultError = try? responseData.fromJSON() {
                throw resultError
            } else if let responseData {
                // We couldn't convert to to ResultError, so surface the DecodingError
                throw DataFetchError.decoding(error: e, responseData: responseData)
            } else {
                throw DataFetchError.message("Unable to retrieve data, unknown error")
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

            throw DataFetchError.message(e.localizedDescription, responseData: responseData)
        }
    }

    @discardableResult private static func checkResponse(response: URLResponse?, error: Swift.Error?, expectedMimeType: String?) throws -> HTTPURLResponse {
        if let error {
            throw DataFetchError.message(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DataFetchError.message("Expected to receive an 'HTTPURLResponse', but received '\(String(describing: type(of: response.self)))'")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DataFetchError.badStatus(httpStatusCode: httpResponse.statusCode)
        }

        try checkMimeType(response: httpResponse, expectedMimeType: expectedMimeType)

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
