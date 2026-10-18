// InvalidationRouteTests.swift
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

// SSE endpoint + frozen wire framing (spec §3.2/§6, test group 4). The endpoint is internal
// infrastructure; the assertions are CONTRACT assertions on the wire the client channel will
// consume: a `data:`-only frame whose JSON array round-trips through `defaultDecoder` to the
// emitted identity set. Overflow termination is proven at the internal hub-subscription seam
// (deterministic, @testable) and separately observed as a clean client-side EOF.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Invalidation SSE endpoint (spec §3.2/§6, test group 4)")
struct InvalidationRouteTests {
    /// A connected client receives one framed `data:` event whose JSON array round-trips (via
    /// `defaultDecoder`) to the containment-derived set of a real save: {Card, owning Board}.
    @Test func framedEventRoundTrip() async throws {
        try await withServedFluentTestApp { app in
            // Short heartbeat so the pump notices the client's disconnect promptly at teardown.
            app.invalidationHeartbeatInterval = .milliseconds(200)
            try configureLiveWorkspace(app, on: app.routes)
        } _: { app, baseURL in
            let (dock1, _) = try await seedWorkspace(on: app.db)

            // openStream throws unless the answer is text/event-stream.
            let chunks = try await openInvalidations(at: baseURL.appending(path: "invalidations"))

            // Headers have arrived ⇒ the route handler already ran hub.subscribe(); the save below
            // therefore reaches a connected subscriber.
            let card = try Card(number: 555, boardName: dock1.name, boardId: dock1.requireId())
            try await card.save(on: app.db)
            let expected = try Set([card.modelIdentity, dock1.modelIdentity])

            let received = try await withTimeout(.seconds(10)) {
                guard let line = try await firstLine(of: chunks, where: { $0.hasPrefix("data:") }) else {
                    return [ModelIdentity]()
                }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                return try JSONDecoder.defaultDecoder.decode([ModelIdentity].self, from: Data(payload.utf8))
            }
            #expect(Set(received) == expected)
        }
    }

    /// With a shortened heartbeat interval, a comment line (`:`-prefixed) arrives on an idle stream.
    @Test func heartbeatsFlow() async throws {
        try await withServedFluentTestApp { app in
            app.invalidationHeartbeatInterval = .milliseconds(100)
            try configureLiveWorkspace(app, on: app.routes)
        } _: { _, baseURL in
            let chunks = try await openInvalidations(at: baseURL.appending(path: "invalidations"))

            // Match the periodic heartbeat specifically — NOT the one-shot `: open` preamble that
            // flushes the response head.
            let sawHeartbeat = try await withTimeout(.seconds(10)) {
                try await firstLine(of: chunks, where: { $0.contains("keep-alive") }) != nil
            }
            #expect(sawHeartbeat)
        }
    }

    /// Overflow closes — proven at the internal hub-subscription seam (deterministic): emitting past
    /// the buffer limit without consuming terminates the subscriber's stream.
    @Test func overflowTerminatesSubscriptionAtHub() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app, on: app.routes)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let identity = try Set([dock1.modelIdentity])
            let hub = try #require(app.invalidationHub)
            let subscription = await hub.subscribe()

            // Flood past the per-subscriber buffer without draining: the overflow emit finishes
            // this subscriber (InvalidationHub.subscriberBufferLimit).
            for _ in 0...(InvalidationHub.subscriberBufferLimit + 8) {
                await hub.emit(identity)
            }

            // The stream terminates: draining reaches the end (nil) within a bounded count.
            let terminated = try await withTimeout(.seconds(10)) {
                var seen = 0
                for await _ in subscription {
                    seen += 1
                    if seen > InvalidationHub.subscriberBufferLimit + 64 {
                        return false // never ended — would have hung without the guard
                    }
                }
                return true
            }
            #expect(terminated)
        }
    }

    /// Overflow closes — observed at the client: while the client reads nothing, a burst large
    /// enough to fill the OS socket buffer makes the server pump block, so the hub overflows and
    /// finishes the subscription. When the client then drains, it reaches a clean EOF (the line
    /// stream completes) rather than hanging. Burst sized to defeat any reasonable socket buffer so
    /// the pump is guaranteed to block; a smaller burst that the fast pump drains into TCP would not
    /// deterministically overflow (see `overflowTerminatesSubscriptionAtHub` for the deterministic
    /// hub-level proof).
    @Test func overflowClosesObservedByClient() async throws {
        try await withServedFluentTestApp { app in
            try configureLiveWorkspace(app, on: app.routes)
        } _: { app, baseURL in
            let (dock1, _) = try await seedWorkspace(on: app.db)
            let identity = try Set([dock1.modelIdentity])

            let chunks = try await openInvalidations(at: baseURL.appending(path: "invalidations"))
            let hub = try #require(app.invalidationHub)

            // Client reads nothing during the burst: the pump fills the socket buffer, blocks, and
            // the continuing emits overflow the 64-slot subscription ⇒ the hub finishes it.
            for _ in 0..<200000 {
                await hub.emit(identity)
            }

            let endedCleanly = try await withTimeout(.seconds(15)) {
                for try await _ in chunks {} // drain to EOF, unthrottled
                return true // the stream completed ⇒ server ended the response, no hang
            }
            #expect(endedCleanly)
        }
    }

    /// The endpoint answers on the passed group and NOT at the root.
    @Test func mountedGroupIsHonored() async throws {
        try await withServedFluentTestApp { app in
            app.invalidationHeartbeatInterval = .milliseconds(200)
            let api = app.grouped("api")
            try configureLiveWorkspace(app, on: api)
        } _: { _, baseURL in
            let grouped = try await status(of: baseURL.appending(path: "api/invalidations"))
            #expect(grouped == 200)

            let root = try await status(of: baseURL.appending(path: "invalidations"))
            #expect(root == 404)
        }
    }
}

// MARK: - Helpers

/// Registers the workspace graph and enables live invalidation, mounting the SSE endpoint on `routes`.
private func configureLiveWorkspace(_ app: Application, on routes: any RoutesBuilder) throws {
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useLiveInvalidation(on: routes)
}

/// Opens the invalidation stream through `openStream`, as the client channel does, without its
/// version and credential headers. Ending iteration of the returned stream closes the request, so
/// server teardown is prompt.
private func openInvalidations(at url: URL) async throws -> AsyncThrowingStream<Data, any Error> {
    try await DataFetch<URLSession>.default.openStream(
        from: url,
        headers: [(field: "Accept", value: "text/event-stream")],
        locale: nil
    )
}

/// Returns 200 when the stream opens, or the non-2xx status it was refused with; other failures
/// throw. The (possibly streaming) body is closed on return.
private func status(of url: URL) async throws -> Int {
    try await withTimeout(.seconds(10)) {
        do {
            _ = try await openInvalidations(at: url)
            return 200
        } catch DataFetchError.badStatus(let httpStatusCode) {
            return httpStatusCode
        }
    }
}

/// The first complete line of `chunks` that satisfies `predicate`, or `nil` when the stream ends.
private func firstLine(
    of chunks: AsyncThrowingStream<Data, any Error>,
    where predicate: (String) -> Bool
) async throws -> String? {
    var pending = Data()
    for try await chunk in chunks {
        pending.append(chunk)
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            // swiftlint:disable:next optional_data_string_conversion
            let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
            pending = Data(pending[pending.index(after: newline)...])
            if predicate(line) {
                return line
            }
        }
    }
    return nil
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
