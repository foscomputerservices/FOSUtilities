// EmitMiddlewareTests.swift
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

// Test-taxonomy discipline: emissions are observed by subscribing a test stream to the INTERNAL
// hub via `@testable import FOSMVVMVapor` (sanctioned — block coverage of an internal seam); the
// assertions themselves are contract assertions: SET equality of what arrives after each mutation.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("Invalidation emit middleware (spec §3.1, test group 1)")
struct EmitMiddlewareTests {
    /// An auto-commit save of an existing Berth (registered graph, live enabled) emits post-save
    /// with the containment-derived set {Berth, owning Dock}.
    @Test func autoCommitUpdateEmitsDerivedSet() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let berth = try #require(
                await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).first()
            )
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            berth.number += 100
            try await berth.save(on: db)

            let expected = try Set([berth.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// Creating a new Berth emits the membership change on its container: {new Berth, Dock}.
    @Test func createEmitsMembershipChangeOnContainer() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let berth = try Berth(number: 42, dockName: dock1.name, dockId: dock1.requireId())
            try await berth.save(on: db)

            let expected = try Set([berth.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// Deleting a Berth emits the membership change on its container: {deleted Berth, Dock}.
    @Test func deleteEmitsMembershipChangeOnContainer() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let berth = try #require(
                await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).first()
            )
            let expected = try Set([berth.modelIdentity, dock1.modelIdentity])
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            try await berth.delete(on: db)

            #expect(await events.next() == expected)
        }
    }

    /// Double-emit guard (T3 carry-forward): `Dock` enters the emit-middleware coverage set through
    /// TWO containment descriptors — its own registration AND `Harbor`'s contained side
    /// (`.children(\Harbor.$docks)`). The `ObjectIdentifier`-deduped coverage store must still wire
    /// exactly ONE middleware for it, so one save produces exactly ONE hub event, not two.
    ///
    /// Counted deterministically with a sentinel rather than a timeout: after the Dock save's event,
    /// a distinct Berth save is enqueued; the very next event MUST be the Berth's set. A duplicate
    /// Dock middleware would have enqueued a second `{Dock, Harbor}` ahead of it, failing the
    /// equality — pinning the count at one without racing an open, idle stream.
    @Test func doubleReachedModelEmitsExactlyOnce() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let dock = try #require(await Dock.find(dock1.requireId(), on: db))
            dock.name = "Renamed Dock"
            try await dock.save(on: db)

            // Exactly one Dock emit — its derived set, once.
            let expectedDock = try Set([dock.modelIdentity, harbor.modelIdentity])
            #expect(await events.next() == expectedDock)

            // Sentinel: a duplicate Dock middleware would surface a SECOND {Dock, Harbor} here.
            let berth = try #require(
                await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).first()
            )
            berth.number += 100
            try await berth.save(on: db)

            let expectedBerth = try Set([berth.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expectedBerth)
        }
    }

    /// `useLiveInvalidation` called BEFORE any registration: later `register(_:migration:)` calls
    /// wire the emit middleware themselves — the graph still emits.
    @Test func enableThenRegisterWiresMiddleware() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app, enableFirst: true)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let berth = try Berth(number: 7, dockName: dock1.name, dockId: dock1.requireId())
            try await berth.save(on: db)

            let expected = try Set([berth.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// `useLiveInvalidation` called AFTER the registrations: the boot switch sweeps the existing
    /// registry — the graph emits identically.
    @Test func registerThenEnableWiresMiddleware() async throws {
        try await withFluentTestApp { app in
            try configureLiveHarbor(app, enableFirst: false)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let dock1Refetched = try #require(await Dock.find(dock1.requireId(), on: db))
            dock1Refetched.name = "Renamed Dock"
            try await dock1Refetched.save(on: db)

            let harbor = try #require(await Harbor.query(on: db).first())
            let expected = try Set([dock1Refetched.modelIdentity, harbor.modelIdentity])
            #expect(await events.next() == expected)
        }
    }
}

/// Registers the harbor graph and enables live invalidation, in either order (spec §3.1: both
/// call orders work).
private func configureLiveHarbor(_ app: Application, enableFirst: Bool = false) throws {
    if enableFirst {
        try app.useLiveInvalidation(on: app.routes)
    }
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    if !enableFirst {
        try app.useLiveInvalidation(on: app.routes)
    }
}
