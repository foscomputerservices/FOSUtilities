// MockURLSessionOfflineTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
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
import FOSTesting
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite(.tags(.networking))
struct MockURLSessionOfflineTests {
    @Test func mockedFetchNeverReachesTheNetwork() async throws {
        // Each run watches its own URL, so the globally registered observer
        // never claims another test's requests.
        let url = try #require(URL(string: "https://\(NetworkObserver.host)/\(UUID().uuidString)"))
        let model = Card(title: "Plan the board")
        let dataFetch = try DataFetch(urlSession: MockURLSession(model: model, url: url))

        _ = URLProtocol.registerClass(NetworkObserver.self)
        defer { URLProtocol.unregisterClass(NetworkObserver.self) }

        let fetched: Card = try await dataFetch.fetch(url)
        #expect(fetched == model)

        // A request the old mock leaked reaches the observer within
        // milliseconds; allow a generous window before calling it quiet.
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline, !NetworkObserver.saw(url) {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!NetworkObserver.saw(url), "A fetch through MockURLSession sent its request to the network")
    }
}

private struct Card: Codable, Equatable {
    let title: String
}

/// Stands in for the network: any request to ``host`` that a URL session
/// actually loads is recorded here and answered with a failure, so even a
/// leaking mock sends nothing off the machine.
private final class NetworkObserver: URLProtocol {
    static let host = "mock-url-session-offline.invalid"

    static func saw(_ url: URL) -> Bool {
        lock.withLock { seen.contains(url) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let url = request.url {
            Self.lock.withLock { _ = Self.seen.insert(url) }
        }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}

    private static let lock = NSLock()
    private nonisolated(unsafe) static var seen: Set<URL> = []
}
