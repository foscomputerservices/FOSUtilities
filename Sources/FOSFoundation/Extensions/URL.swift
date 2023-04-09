// URL.swift
//
// Copyright © 2023 FOS Services, LLC. All rights reserved.
//

import Foundation

public extension URL {
    /// Fetches the given data of type ``ResultValue`` from the given ``URL``
    ///
    /// - Parameters:
    ///   - dataFetch: An optional implementation of ``FoundationDataFetch`` to use to retrieve the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    func fetch<ResultValue: Decodable>(_ dataFetch: FoundationDataFetch? = nil, headers: [(field: String, value: String)]? = nil) async throws -> ResultValue {
        try await (dataFetch ?? FoundationDataFetch.default).fetch(self, headers: headers)
    }

    /// Fetches the given data of type ``ResultValue`` from the given ``URL``
    ///
    /// - Parameters:
    ///   - dataFetch: An optional implementation of ``FoundationDataFetch`` to use to retrieve the data
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - errorType: An ``Error`` type to attempt to decode returned data as an error if unable to decode as ``ResultValue``
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    func fetch<ResultValue: Decodable>(_ dataFetch: FoundationDataFetch? = nil, headers: [(field: String, value: String)]? = nil, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await (dataFetch ?? FoundationDataFetch.default).fetch(self, headers: headers, errorType: errorType)
    }

    // These are replacements for the macOS 13 only api
    func appending(queryItems: [URLQueryItem]) -> URL {
        URL(string: absoluteString + queryItems.queryStr)!
    }

    func appending(path: some StringProtocol) -> URL {
        appendingPathComponent(String(path))
    }
}

private extension Collection<URLQueryItem> {
    var queryStr: String {
        reduce("") { result, next in
            var result = result

            result += result.isEmpty ? "?" : "&"
            result += next.name
            result += "="
            result += next.value!

            return result
        }
    }
}
