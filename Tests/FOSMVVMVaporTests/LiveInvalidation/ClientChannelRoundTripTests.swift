// ClientChannelRoundTripTests.swift
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

// End-to-end: the default SSE client channel (FOSMVVM) against the real served endpoint
// (FOSMVVMVapor), locking the frozen §6 wire across the module boundary (spec §3.2, test group 6).
#if canImport(Darwin) || canImport(FoundationNetworking)
import Fluent
import FluentKit
import FOSFoundation
@testable import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Default SSE channel — end-to-end round-trip (spec §3.2, test group 6)")
struct ClientChannelRoundTripTests {
    /// The default channel opens against the served endpoint, signals `.connected`, and — after a
    /// real Fluent save — delivers `.invalidated` with the containment-derived set {Berth, Dock}.
    @Test func connectsThenReceivesInvalidation() async throws {
        try await withServedFluentTestApp { app in
            app.invalidationHeartbeatInterval = .milliseconds(200)
            try configureLiveHarbor(app, on: app.routes)
        } _: { app, baseURL in
            let (dock1, _) = try await seedHarbor(on: app.db)
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }

            let channel = SSEInvalidationChannel(
                baseURL: { baseURL },
                credentialProvider: nil,
                session: session
            )

            let (received, expected) = try await withTimeout(.seconds(15)) {
                var iterator = channel.events().makeAsyncIterator()

                // The stream is open once `.connected` arrives ⇒ the server has already subscribed
                // this client to the hub, so the save below reaches a connected subscriber.
                guard case .connected = await iterator.next() else {
                    throw RoundTripError.expectedConnected
                }

                let berth = try Berth(number: 777, dockName: dock1.name, dockId: dock1.requireId())
                try await berth.save(on: app.db)
                let expected = try Set([berth.modelIdentity, dock1.modelIdentity])

                while let event = await iterator.next() {
                    if case .invalidated(let identities) = event {
                        return (identities, expected)
                    }
                }
                throw RoundTripError.streamEndedBeforeInvalidation
            }
            #expect(received == expected)
        }
    }

    /// The channel attaches `ClientCredentialProvider.credentialHeaders()` at stream-open: a group
    /// middleware captures the `Authorization` header the served request carried.
    @Test func attachesCredentialHeadersAtOpen() async throws {
        let capture = HeaderCapture()
        try await withServedFluentTestApp { app in
            app.invalidationHeartbeatInterval = .milliseconds(200)
            let secured = app.grouped(CapturingMiddleware(capture))
            try configureLiveHarbor(app, on: secured)
        } _: { _, baseURL in
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }

            let channel = SSEInvalidationChannel(
                baseURL: { baseURL },
                credentialProvider: BearerCredentialProvider { "round-trip-token" },
                session: session
            )

            try await withTimeout(.seconds(15)) {
                var iterator = channel.events().makeAsyncIterator()
                guard case .connected = await iterator.next() else {
                    throw RoundTripError.expectedConnected
                }
            }
            // `.connected` fired ⇒ the request reached the server ⇒ the middleware already recorded.
            #expect(await capture.value == "Bearer round-trip-token")
        }
    }

    /// A non-2xx open (here a 401 group) is a drop, not a connection: no `.connected` is ever
    /// emitted (no false dispatcher sweep) and back-off GROWS across the retries instead of
    /// resetting into a hot spin.
    @Test func non2xxOpenBacksOffWithoutConnected() async throws {
        try await withServedFluentTestApp { app in
            app.invalidationHeartbeatInterval = .milliseconds(200)
            let denied = app.grouped(DenyAllMiddleware())
            try configureLiveHarbor(app, on: denied)
        } _: { _, baseURL in
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }

            let sleeps = SleepRecorder()
            let channel = SSEInvalidationChannel(
                baseURL: { baseURL },
                credentialProvider: nil,
                session: session,
                sleep: { await sleeps.record($0) },
                initialBackoff: .milliseconds(1),
                maxBackoff: .milliseconds(8)
            )

            let log = EventLog()
            let consumer = Task {
                for await event in channel.events() {
                    await log.record(event)
                }
            }

            // Each retry re-opens against the live 401 endpoint; wait until four real attempts
            // have backed off, then tear the channel down.
            try await withTimeout(.seconds(15)) {
                while await sleeps.durations.count < 4 {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            consumer.cancel()

            let durations = await sleeps.durations
            #expect(Array(durations.prefix(4)) == [
                .milliseconds(1), .milliseconds(2), .milliseconds(4), .milliseconds(8)
            ])
            #expect(await log.events.isEmpty)
        }
    }
}

// MARK: - Helpers

private enum RoundTripError: Error {
    case expectedConnected
    case streamEndedBeforeInvalidation
}

/// Records the `Authorization` header of the request that reached the SSE endpoint.
private actor HeaderCapture {
    private(set) var value: String?
    func record(_ header: String?) {
        value = header
    }
}

private struct CapturingMiddleware: AsyncMiddleware {
    let capture: HeaderCapture
    init(_ capture: HeaderCapture) {
        self.capture = capture
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        await capture.record(request.headers.first(name: .authorization))
        return try await next.respond(to: request)
    }
}

/// Answers every request 401 — an expired-credential / misconfigured-auth stand-in.
private struct DenyAllMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        Response(status: .unauthorized)
    }
}

/// Records the back-off durations the channel requested (injected as its `sleep`; never sleeps).
private actor SleepRecorder {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) {
        durations.append(duration)
    }
}

/// Records every event the channel yielded.
private actor EventLog {
    private(set) var events: [InvalidationEvent] = []
    func record(_ event: InvalidationEvent) {
        events.append(event)
    }
}

/// Registers the harbor graph and enables live invalidation, mounting the SSE endpoint on `routes`.
private func configureLiveHarbor(_ app: Application, on routes: any RoutesBuilder) throws {
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useLiveInvalidation(on: routes)
}

private struct TimeoutError: Error {}

/// Races `operation` against a deadline so no stream read can hang the suite.
private func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
#endif
