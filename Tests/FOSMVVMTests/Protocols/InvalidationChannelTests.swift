// InvalidationChannelTests.swift
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
import FOSMVVM
import Foundation
import Testing

@Suite("InvalidationChannel")
struct InvalidationChannelTests {
    @Test("A channel yields .connected then .invalidated through events()")
    func channelYieldsEvents() async {
        let channel = TestInvalidationChannel()

        var received: [InvalidationEvent] = []
        for await event in channel.events() {
            received.append(event)
        }

        #expect(received.count == 2)

        guard case .connected = received.first else {
            Issue.record("Expected the first event to be .connected")
            return
        }

        guard case .invalidated(let identities) = received.last else {
            Issue.record("Expected the second event to be .invalidated")
            return
        }
        #expect(identities.isEmpty)
    }

    @Test("URLPackage.invalidationBaseURL defaults to serverBaseURL")
    func invalidationBaseURLDefaultsToServer() throws {
        let server = try #require(URL(string: "https://api.example.com"))

        let package = MVVMEnvironment.URLPackage(serverBaseURL: server)

        #expect(package.invalidationBaseURL == server)
    }

    @Test("URLPackage.invalidationBaseURL honors an explicit override")
    func invalidationBaseURLHonorsOverride() throws {
        let server = try #require(URL(string: "https://api.example.com"))
        let invalidation = try #require(URL(string: "wss://live.example.com"))

        let package = MVVMEnvironment.URLPackage(
            serverBaseURL: server,
            invalidationBaseURL: invalidation
        )

        #expect(package.invalidationBaseURL == invalidation)
    }

    @Test("MVVMEnvironment stores the supplied invalidation channel")
    func environmentStoresChannel() async throws {
        let url = try #require(URL(string: "http://localhost:8080"))

        let environment = MVVMEnvironment(
            appBundle: .module,
            invalidationChannel: TestInvalidationChannel(),
            deploymentURLs: [.debug: url],
            session: nil,
            requestErrorHandler: nil
        )

        let stored = try #require(environment.invalidationChannel as? TestInvalidationChannel)

        var sawConnected = false
        for await event in stored.events() {
            if case .connected = event { sawConnected = true }
        }
        #expect(sawConnected)
    }

    @Test("MVVMEnvironment leaves the invalidation channel nil by default")
    func environmentChannelNilByDefault() throws {
        let url = try #require(URL(string: "http://localhost:8080"))

        let environment = MVVMEnvironment(
            appBundle: .module,
            deploymentURLs: [.debug: url],
            session: nil,
            requestErrorHandler: nil
        )

        #expect(environment.invalidationChannel == nil)
    }
}

/// A channel that replays a fixed script — models a transport that reconnects and then
/// reports one (empty) invalidation before closing.
private struct TestInvalidationChannel: InvalidationChannel {
    func events() -> AsyncStream<InvalidationEvent> {
        AsyncStream { continuation in
            continuation.yield(.connected)
            continuation.yield(.invalidated([]))
            continuation.finish()
        }
    }
}
