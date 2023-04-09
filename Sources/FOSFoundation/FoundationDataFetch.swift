// FoundationDataFetch.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DataFetchError: Error {
    case message(_ message: String)
    case badStatus(_ httpStatusCode: Int)

    public var localizedDescription: String {
        switch self {
        case .message(let message): return message
        case .badStatus(let code): return "Status code: \(code)"
        }
    }
}

private struct DummyError: Decodable, Error {}

public final class FoundationDataFetch {
    private let urlSession: URLSession

    public static let `default`: FoundationDataFetch = .init(urlSession: FoundationDataFetch.UrlSession())

    /// Fetches the given data of type ``ResultValue`` from the given ``URL``
    ///
    /// - Parameters:
    ///   - url: The ``URL`` that identifies the source of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    public func fetch<ResultValue: Decodable>(_ url: URL, headers: [(field: String, value: String)]?) async throws -> ResultValue {
        try await fetch(url.absoluteString, headers: headers, errorType: DummyError.self)
    }

    /// Fetches the given data of type ``ResultValue`` from the given ``URL``
    ///
    /// - Parameters:
    ///   - url: The ``URL`` that identifies the source of the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - errorType: An ``Error`` type to attempt to decode returned data as an error if unable to decode as ``ResultValue``
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Encoding | deflate, gzip |
    public func fetch<ResultValue: Decodable>(_ url: URL, headers: [(field: String, value: String)]?, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await fetch(url.absoluteString, headers: headers, errorType: errorType)
    }

    public func send<ResultValue: Decodable>(data: Data, to urlStr: String, httpMethod: String, headers: [(field: String, value: String)]?, callback: @escaping (Result<ResultValue, DataFetchError>) -> Void) {
        guard let url = URL(string: urlStr) else {
            callback(.failure(.message("Unable to convert \(urlStr) to URL???")))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = httpMethod
        urlRequest.httpBody = data
        urlRequest.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("deflate, gzip", forHTTPHeaderField: "Accept-Encoding")

        if let headers {
            for header in headers {
                urlRequest.setValue(header.value, forHTTPHeaderField: header.field)
            }
        }

        urlSession
            .dataTask(with: urlRequest) { data, response, error in
                Self.completionHandler(
                    responseData: data,
                    response: response,
                    error: error,
                    callback: callback
                )
            }
            .resume()
    }

    // MARK: Initialization Methods

    public init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    public static func UrlSession(forUserToken: String? = nil) -> URLSession {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.allowsCellularAccess = true
        sessionConfig.isDiscretionary = false

        return URLSession(configuration: sessionConfig)
    }
}

private extension FoundationDataFetch {
    func fetch<ResultValue: Decodable, ResultError: Decodable & Error>(_ urlStr: String, headers: [(field: String, value: String)]?, errorType: ResultError.Type) async throws -> ResultValue {
        guard let url = URL(string: urlStr) else {
            throw DataFetchError.message("Unable to convert \(urlStr) to URL???")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "Get"
        urlRequest.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("deflate, gzip", forHTTPHeaderField: "Accept-Encoding")

        if let headers {
            for header in headers {
                urlRequest.setValue(header.value, forHTTPHeaderField: header.field)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            urlSession
                .dataTask(with: urlRequest) { data, _, e in
                    var result: ResultValue?
                    var error: Error?

                    if let data {
                        do {
                            if ResultValue.self is String.Type {
                                result = String(data: data, encoding: .utf8) as? ResultValue
                            } else if ResultValue.self is String?.Type {
                                result = String(data: data, encoding: .utf8) as? ResultValue
                            } else {
                                result = try data.fromJSON()
                            }
                        } catch let e as DecodingError {
                            guard errorType != DummyError.self, let errorResult: ResultError? = try? data.fromJSON() else {
                                continuation.resume(throwing: DataFetchError.message(e.localizedDescription))
                                return
                            }

                            error = errorResult
                        } catch let e {
                            error = DataFetchError.message(e.localizedDescription)
                        }
                    } else if let e {
                        error = DataFetchError.message(e.localizedDescription)
                    } else {
                        error = DataFetchError.message("Unable to retrieve data, unknown error")
                    }

                    if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: error!)
                    }
                }
                .resume()
        }
    }

    static func completionHandler<ResultValue: Decodable>(responseData: Data?, response: URLResponse?, error: Error?, callback: (Result<ResultValue, DataFetchError>) -> Void) {
        let httpResponse: HTTPURLResponse
        let checkedResponse = Self.checkResponse(response: response, error: error)

        if let error = checkedResponse.1 {
            callback(.failure(error))
            return
        } else if let resp = checkedResponse.0 {
            httpResponse = resp
        } else {
            callback(.failure(.message("One of response or error should have been set!")))
            return
        }

        if let mimeType = httpResponse.mimeType, mimeType == "application/json" {
            if let data = responseData {
                do {
                    try callback(.success(data.fromJSON()))
                } catch let e {
                    callback(.failure(.message(e.localizedDescription)))
                }
            } else {
                callback(.failure(.message("Response data was nil")))
            }
        } else {
            callback(.failure(.message("Unknown mime type: \(String(describing: httpResponse.mimeType))")))
        }
    }

    static func checkResponse(response: URLResponse?, error: Swift.Error?) -> (HTTPURLResponse?, DataFetchError?) {
        if let error {
            return (nil, .message(error.localizedDescription))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return (nil, .message("Expected to receive an 'HTTPURLResponse', but received '\(String(describing: type(of: response.self)))'"))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            return (nil, .badStatus(httpResponse.statusCode))
        }

        return (httpResponse, nil)
    }
}
