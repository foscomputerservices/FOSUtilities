// URL+DataFetch.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Services, LLC
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

public extension URL {
    /// Fetches the given data of type **ResultValue** from the given **URL**
    ///
    /// - Parameters:
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - locale: An optional [Locale](https://developer.apple.com/documentation/foundation/locale) specification
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Language | <provided locale> |
    func fetch<ResultValue: Decodable>(headers: [(field: String, value: String)]? = nil, locale: Locale? = nil) async throws -> ResultValue {
        try await DataFetch<URLSession>.default
            .fetch(self, headers: headers, locale: locale)
    }

    /// Fetches the given data of type **ResultValue** from the given **URL**
    /// 
    /// - Parameters:
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - locale: An optional [Locale](https://developer.apple.com/documentation/foundation/locale) specification
    ///   - errorType: An **Error** type to attempt to decode returned data as an error if unable to decode as **ResultValue**
    ///
    /// - Note: The following headers are automatically sent to all requests:
    /// 
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    ///  | Accept-Language | <provided locale> |
    func fetch<ResultValue: Decodable>(headers: [(field: String, value: String)]? = nil, locale: Locale? = nil, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await DataFetch<URLSession>.default
            .fetch(self, headers: headers, locale: locale, errorType: errorType)
    }

    /// Sends **Data** to, and process the return of type **ResultValue** from, the given **URL**
    ///
    /// - Parameters:
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - data: The **Encodable** to send to the URL as the body of a POST request
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    func send<ResultValue: Decodable>(headers: [(field: String, value: String)]? = nil, data: some Encodable) async throws -> ResultValue {
        let sendData: Data
        if let str = data as? String {
            sendData = str.data(using: .utf8) ?? Data()
        } else {
            do {
                sendData = try data.toJSONData()
            } catch let jsonError as JSONError {
                throw DataFetchError.fromJSONError(jsonError)
            } catch let e {
                throw e
            }
        }

        return try await DataFetch<URLSession>.default
            .post(data: sendData, to: self, headers: headers)
    }

    /// Sends **Data** to, and process the return of type **ResultValue** from, the given **URL**
    ///
    /// - Parameters:
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - data: The **Encodable** to send to the URL as the body of a POST request
    ///   - errorType: An **Error** type to attempt to decode returned data as an error if unable to decode as **ResultValue**
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    func send<ResultValue: Decodable>(headers: [(field: String, value: String)]? = nil, data: some Encodable, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await DataFetch<URLSession>.default
            .post(
                data: data.toJSONData(),
                to: self,
                headers: headers,
                errorType: errorType
            )
    }

    /// Sends **Data** to, and process the return of type **ResultValue** from, the given **URL** with the HTTPMethod = "DELETE"
    ///
    /// - Parameters:
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - data: The **Encodable** to send to the URL as the body of a POST request
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    func delete<ResultValue: Decodable>(headers: [(field: String, value: String)]? = nil, data: some Encodable) async throws -> ResultValue {
        let sendData: Data
        if let str = data as? String {
            sendData = str.data(using: .utf8) ?? Data()
        } else {
            do {
                sendData = try data.toJSONData()
            } catch let jsonError as JSONError {
                throw DataFetchError.fromJSONError(jsonError)
            } catch let e {
                throw e
            }
        }

        return try await DataFetch<URLSession>.default
            .delete(data: sendData, at: self, headers: headers)
    }

    /// Sends **Data** to, and process the return of type **ResultValue** from, the given **URL** with the HTTPMethod = "DELETE"
    ///
    /// - Parameters:
    ///   - headers: Any extra HTTP headers that need to be sent with the request
    ///   - data: The **Encodable** to send to the URL as the body of a POST request
    ///   - errorType: An **Error** type to attempt to decode returned data as an error if unable to decode as **ResultValue**
    ///
    /// - Note: The following headers are automatically sent to all requests:
    ///
    ///  | Key | Value |
    ///  | ---------------------- | ---------------------------------- |
    ///  | Accept | application/json;charset=utf-8 |
    ///  | Accept-Encoding | application/json;charset=utf-8 |
    ///  | Content-Type | application/json;charset=utf-8 |
    func delete<ResultValue: Decodable>(headers: [(field: String, value: String)]? = nil, data: some Encodable, errorType: (some Decodable & Error).Type) async throws -> ResultValue {
        try await DataFetch<URLSession>.default
            .delete(
                data: data.toJSONData(),
                at: self,
                headers: headers,
                errorType: errorType
            )
    }
}
