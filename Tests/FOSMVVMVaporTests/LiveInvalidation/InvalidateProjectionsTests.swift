// InvalidateProjectionsTests.swift
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

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// The internal hub subscribe is block coverage of an internal seam (same note as
// LiveTransactionTests); every asserted identity is minted/compared via public API.

/// Neutral non-Fluent fixture: an Application-hosted source's state snapshot.
/// FOSMVVM.Model only — deliberately NOT a FluentKit.Model.
private struct StatusSnapshot: FOSMVVM.Model {
    let id: ModelIdType?
    var activeSessions: Int = 0
}

/// The stable identity the request-forwarding route nudges (minted once, file-private).
private let pokeId = ModelIdType()

@Suite("invalidateProjections(of:) — public write-side entry for non-Fluent sources")
struct InvalidateProjectionsTests {
    /// Outside any transaction, the call emits exactly the model's own identity.
    @Test func emitsOwnIdentityImmediately() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, _ in
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let status = StatusSnapshot(id: ModelIdType(), activeSessions: 3)
            try await app.invalidateProjections(of: status)

            #expect(try await events.next() == Set([status.modelIdentity]))
        }
    }

    /// Inside liveTransaction, the nudge joins the collector: ONE union event after
    /// commit, containing the actor identity AND the SQL write's derived set.
    @Test func joinsLiveTransactionUnionOnCommit() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let status = StatusSnapshot(id: ModelIdType(), activeSessions: 1)
            let berth = try Berth(number: 42, dockName: dock1.name, dockId: dock1.requireId())
            try await app.liveTransaction { tx in
                try await berth.save(on: tx)
                try await app.invalidateProjections(of: status)
            }

            let expected = try Set([
                status.modelIdentity,
                berth.modelIdentity,
                dock1.modelIdentity
            ])
            #expect(try await events.next() == expected)

            // Exactly one flush: the next event is the sentinel, not a second emission.
            let sentinel = try Set([harbor.modelIdentity])
            await hub.emit(sentinel)
            #expect(try await events.next() == sentinel)
        }
    }

    /// A thrown liveTransaction discards the collected nudge — sentinel-first.
    @Test func rolledBackTransactionEmitsNothing() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let status = StatusSnapshot(id: ModelIdType(), activeSessions: 5)
            await #expect(throws: Boom.self) {
                try await app.liveTransaction { _ in
                    try await app.invalidateProjections(of: status)
                    throw Boom()
                }
            }

            // Nothing was emitted: the first event the subscriber sees is the sentinel.
            let sentinel = try Set([harbor.modelIdentity])
            await hub.emit(sentinel)
            #expect(try await events.next() == sentinel)
        }
    }

    /// With live invalidation not enabled, the call is a no-op — no throw, no trap.
    @Test func disabledIsNoOp() async throws {
        try await withFluentTestApp { _ in
            // Live invalidation NOT enabled.
        } _: { app, _ in
            let status = StatusSnapshot(id: ModelIdType())
            try await app.invalidateProjections(of: status)
            #expect(app.invalidationHub == nil)
        }
    }

    /// An unpersisted model (nil id) throws ModelError.missingId — never a silent skip.
    @Test func nilIdThrowsMissingId() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, _ in
            await #expect(throws: ModelError.self) {
                try await app.invalidateProjections(of: StatusSnapshot(id: nil))
            }
        }
    }

    /// Request forwarding reaches the same hub.
    @Test func requestForwardingEmits() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
            app.get("poke") { req async throws -> HTTPStatus in
                try await req.invalidateProjections(of: StatusSnapshot(id: pokeId))
                return .ok
            }
        } _: { app, _ in
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let httpReq = Request(
                application: app,
                method: .GET,
                url: URI(string: "/poke"),
                on: app.eventLoopGroup.next()
            )
            let response = try await app.responder.respond(to: httpReq).get()
            #expect(response.status == .ok)

            #expect(try await events.next() == Set([StatusSnapshot(id: pokeId).modelIdentity]))
        }
    }
}

private struct Boom: Error {}

/// Registers the harbor graph and enables live invalidation.
/// (File-private and duplicated per test file with differing signatures — copied from
/// LiveTransactionTests; not callable across files.)
private func configureLiveHarbor(_ app: Application) throws {
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useLiveInvalidation(on: app.routes)
}
