// MockURLSession.swift
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

/// An implementation of **URLSessionProtocol** used for testing
///
/// ``MockURLSession`` implements the **URLSessionProtocol** to allow
/// testing of networking functions.  The mock session is initialized with one or more
/// of **data**, **error**, **response** and these values will immediately be sent
/// back to the *completionHandlers* of the two *dataTask()* functions.
///
/// A fetch through a ``MockURLSession`` never touches the network: the task it
/// returns does nothing when resumed.
///
/// ```swift
/// let session = try MockURLSession(model: Card.stub(), url: cardURL)
/// let dataFetch = DataFetch(urlSession: session)
/// let card: Card = try await dataFetch.fetch(cardURL)
/// ```
public final class MockURLSession: URLSessionProtocol {
    public let data: Data?
    public let error: Error?
    public let response: URLResponse?

    public func dataTask(
        with url: URL,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        completionHandler(data, response, error)
        return Self.inertSession.dataTask(with: url)
    }

    public func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, (any Error)?) -> Void
    ) -> URLSessionDataTask {
        completionHandler(data, response, error)
        return Self.inertSession.dataTask(with: request)
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

    /// URLSessionDataTask's own initializer is deprecated on Apple platforms, so the
    /// returned task comes from a session whose only loader answers without sending.
    private static let inertSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InertURLProtocol.self]
        return URLSession(configuration: config)
    }()
}

private final class InertURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
