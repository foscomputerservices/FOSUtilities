// MockURLSession.swift
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

import FOSFoundation
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An implementation of **URLSessionProtocol** used for testing
///
/// ``MockURLSession`` implements the **URLSessionProtocol** to allow
/// testing of networking functions.  The mock session is initialized with one or more
/// of **data**, **error**, **response** and these values will immediately be sent
/// back to the *completionHandlers* of the two *dataTask()* functions.
public final class MockURLSession: URLSessionProtocol {
    public let data: Data?
    public let error: Error?
    public let response: URLResponse?

    public func dataTask(
        with url: URL,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        completionHandler(data, response, error)
        return URLSession.shared.dataTask(with: url)
    }

    public func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, (any Error)?) -> Void
    ) -> URLSessionDataTask {
        completionHandler(data, response, error)
        return URLSession.shared.dataTask(with: request)
    }

    public static func session(config: URLSessionConfiguration) -> Self {
        fatalError("NYI for MOCK, use init(data:error:response)")
    }

    public init(data: Data?, error: Error?, response: URLResponse?) {
        self.data = data
        self.error = error
        self.response = response
    }

    public init(model: some Codable, url: URL) throws {
        self.data = try model.toJSONData()
        self.error = nil
        self.response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/json;charset=utf-8"
            ]
        )
    }
}
