// LiveTransactionTests.swift
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

// Test-taxonomy discipline: emission ABSENCE is asserted with a sentinel — the hub is emitted a
// known identity set directly after the exercised writes, and the FIRST event the test subscriber
// sees must be that sentinel (every middleware emission completes before its save returns, so the
// buffer is final by then). The internal hub/@testable use is block coverage of an internal seam.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import NIOConcurrencyHelpers
import Testing
import Vapor

@Suite("liveTransaction + bare-transaction suppression (spec §3.1/D-L2-1, test group 2)")
struct LiveTransactionTests {
    /// A save inside a bare `db.transaction { }` emits NOTHING — FOSMVVM cannot see whether the
    /// transaction commits — and warns exactly once per model type, naming the type.
    @Test func bareTransactionEmitsNothingAndWarnsOnce() async throws {
        let captured = CapturedWarnings()
        try await withFluentTestApp { app in
            captureWarnings(of: app, into: captured)
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            try await db.transaction { tx in
                let berthA = try Berth(number: 60, dockName: dock1.name, dockId: dock1.requireId())
                let berthB = try Berth(number: 61, dockName: dock1.name, dockId: dock1.requireId())
                try await berthA.save(on: tx)
                try await berthB.save(on: tx)
            }

            // The transaction committed (writes landed) …
            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 5) // 3 seeded + 2

            // … but nothing was emitted: the first event the subscriber sees is the sentinel.
            let sentinel = try Set([harbor.modelIdentity])
            await hub.emit(sentinel)
            #expect(await events.next() == sentinel)

            // Warned once for Berth (two suppressed saves, one warning), naming type + remedy.
            #expect(captured.all.count(where: { $0.contains("Berth") }) == 1)
            #expect(captured.contains(allOf: "Berth", "liveTransaction"))
        }
    }

    /// `Application.liveTransaction` collects every write's derived set and flushes exactly the
    /// UNION to the hub — one event — after the transaction commits.
    @Test func liveTransactionFlushesUnionOnCommit() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let berthA = try Berth(number: 70, dockName: dock1.name, dockId: dock1.requireId())
            let berthB = try Berth(number: 71, dockName: dock2.name, dockId: dock2.requireId())
            let value = try await app.liveTransaction { tx in
                try await berthA.save(on: tx)
                try await berthB.save(on: tx)
                return 7
            }
            #expect(value == 7)

            let expected = try Set([
                berthA.modelIdentity,
                dock1.modelIdentity,
                berthB.modelIdentity,
                dock2.modelIdentity
            ])
            #expect(await events.next() == expected)

            // Exactly one flush: the next event is the sentinel, not a second emission.
            let sentinel = try Set([harbor.modelIdentity])
            await hub.emit(sentinel)
            #expect(await events.next() == sentinel)
        }
    }

    /// `Request.liveTransaction` — the request-side door — flushes the same way.
    @Test func requestLiveTransactionFlushesOnCommit() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let req = Request(
                application: app,
                method: .GET,
                url: URI(string: "/"),
                on: app.eventLoopGroup.next()
            )
            let berth = try Berth(number: 80, dockName: dock1.name, dockId: dock1.requireId())
            try await req.liveTransaction { tx in
                try await berth.save(on: tx)
            }

            let expected = try Set([berth.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// A THROWING `liveTransaction` rolls back and emits nothing — the collected sets are discarded.
    @Test func throwingLiveTransactionEmitsNothing() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let berth = try Berth(number: 90, dockName: dock1.name, dockId: dock1.requireId())
            await #expect(throws: Boom.self) {
                try await app.liveTransaction { tx in
                    try await berth.save(on: tx)
                    throw Boom()
                }
            }

            // Rolled back …
            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 3) // the seeded three only

            // … and nothing was emitted.
            let sentinel = try Set([harbor.modelIdentity])
            await hub.emit(sentinel)
            #expect(await events.next() == sentinel)
        }
    }

    /// With live invalidation NOT enabled, `liveTransaction` is still a correct transaction —
    /// the wrapper degrades to `db.transaction` (no hub, no flush, no crash).
    @Test func liveTransactionWithoutHubRunsTransaction() async throws {
        try await withFluentTestApp { app in
            // Registered graph, live NOT enabled.
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)

            let berth = try Berth(number: 95, dockName: dock1.name, dockId: dock1.requireId())
            let value = try await app.liveTransaction { tx in
                try await berth.save(on: tx)
                return "committed"
            }
            #expect(value == "committed")

            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 4)
        }
    }
}

private struct Boom: Error {}

/// Registers the harbor graph and enables live invalidation.
private func configureLiveHarbor(_ app: Application) throws {
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useLiveInvalidation(on: app.routes)
}

// MARK: - Warning capture (mirrors the PlanRegistrationTests idiom)

/// Lock-guarded warning sink shared between the handler (inside the app) and the assertion.
private final class CapturedWarnings: @unchecked Sendable {
    private let lock = NIOLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var all: [String] {
        lock.withLock { messages }
    }

    func contains(allOf fragments: String...) -> Bool {
        all.contains { message in fragments.allSatisfy { message.contains($0) } }
    }
}

/// Captures `.warning`+ messages; forwards nothing (tests stay quiet).
private struct CapturingLogHandler: LogHandler {
    let captured: CapturedWarnings

    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .warning

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level >= .warning else {
            return
        }
        captured.append(message.description)
    }
}

/// Rebinds the app's logger to the capturing sink — the emit middleware warns through the
/// database's logger, which Fluent derives from `Application.logger`.
private func captureWarnings(of app: Application, into captured: CapturedWarnings) {
    app.logger = Logger(label: "live-transaction-tests") { _ in
        CapturingLogHandler(captured: captured)
    }
}
