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
    /// An auto-commit save of an existing Card (registered graph, live enabled) emits post-save
    /// with the containment-derived set {Card, owning Board}.
    @Test func autoCommitUpdateEmitsDerivedSet() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let card = try #require(
                await Card.query(on: db).filter(\.$board.$id == dock1.requireId()).first()
            )
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            card.number += 100
            try await card.save(on: db)

            let expected = try Set([card.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// Creating a new Card emits the membership change on its container: {new Card, Board}.
    @Test func createEmitsMembershipChangeOnContainer() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let card = try Card(number: 42, boardName: dock1.name, boardId: dock1.requireId())
            try await card.save(on: db)

            let expected = try Set([card.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// Deleting a Card emits the membership change on its container: {deleted Card, Board}.
    @Test func deleteEmitsMembershipChangeOnContainer() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let card = try #require(
                await Card.query(on: db).filter(\.$board.$id == dock1.requireId()).first()
            )
            let expected = try Set([card.modelIdentity, dock1.modelIdentity])
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            try await card.delete(on: db)

            #expect(await events.next() == expected)
        }
    }

    /// Double-emit guard (T3 carry-forward): `Board` enters the emit-middleware coverage set through
    /// TWO containment descriptors — its own registration AND `Workspace`'s contained side
    /// (`.children(\Workspace.$boards)`). The `ObjectIdentifier`-deduped coverage store must still wire
    /// exactly ONE middleware for it, so one save produces exactly ONE hub event, not two.
    ///
    /// Counted deterministically with a sentinel rather than a timeout: after the Board save's event,
    /// a distinct Card save is enqueued; the very next event MUST be the Card's set. A duplicate
    /// Board middleware would have enqueued a second `{Board, Workspace}` ahead of it, failing the
    /// equality — pinning the count at one without racing an open, idle stream.
    @Test func doubleReachedModelEmitsExactlyOnce() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let workspace = try #require(await Workspace.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let board = try #require(await Board.find(dock1.requireId(), on: db))
            board.name = "Renamed Board"
            try await board.save(on: db)

            // Exactly one Board emit — its derived set, once.
            let expectedBoard = try Set([board.modelIdentity, workspace.modelIdentity])
            #expect(await events.next() == expectedBoard)

            // Sentinel: a duplicate Board middleware would surface a SECOND {Board, Workspace} here.
            let card = try #require(
                await Card.query(on: db).filter(\.$board.$id == dock1.requireId()).first()
            )
            card.number += 100
            try await card.save(on: db)

            let expectedCard = try Set([card.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expectedCard)
        }
    }

    /// `useLiveInvalidation` called BEFORE any registration: later `register(_:migration:)` calls
    /// wire the emit middleware themselves — the graph still emits.
    @Test func enableThenRegisterWiresMiddleware() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app, enableFirst: true)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let card = try Card(number: 7, boardName: dock1.name, boardId: dock1.requireId())
            try await card.save(on: db)

            let expected = try Set([card.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// `useLiveInvalidation` called AFTER the registrations: the boot switch sweeps the existing
    /// registry — the graph emits identically.
    @Test func registerThenEnableWiresMiddleware() async throws {
        try await withFluentTestApp { app in
            try configureLiveWorkspace(app, enableFirst: false)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let dock1Refetched = try #require(await Board.find(dock1.requireId(), on: db))
            dock1Refetched.name = "Renamed Board"
            try await dock1Refetched.save(on: db)

            let workspace = try #require(await Workspace.query(on: db).first())
            let expected = try Set([dock1Refetched.modelIdentity, workspace.modelIdentity])
            #expect(await events.next() == expected)
        }
    }
}

/// Registers the workspace graph and enables live invalidation, in either order (spec §3.1: both
/// call orders work).
private func configureLiveWorkspace(_ app: Application, enableFirst: Bool = false) throws {
    if enableFirst {
        try app.useLiveInvalidation(on: app.routes)
    }
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    if !enableFirst {
        try app.useLiveInvalidation(on: app.routes)
    }
}
