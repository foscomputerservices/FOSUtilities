// AfterCommitHookTests.swift
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

// The after-commit collector is an internal seam the lifecycle middleware calls; @testable use
// here is block coverage of that seam. Hooks record into a lock-guarded log; emission order is
// asserted with this directory's sentinel idiom, never through timing.

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

@Suite("After-commit hooks in liveTransaction (plan OQ3/OQ14, task group G6)")
struct AfterCommitHookTests {
    /// With live invalidation NOT enabled, a hook deferred inside `liveTransaction` still runs —
    /// exactly once, and only after the closure returns.
    @Test func hookRunsOnceAfterCommitWithoutLiveInvalidation() async throws {
        let log = HookLog()
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)

            try await app.liveTransaction { tx in
                let berth = try Berth(number: 100, dockName: dock1.name, dockId: dock1.requireId())
                try await berth.save(on: tx)
                #expect(await LiveTransactionState.deferUntilCommit(on: tx) { log.append("hook") })
                #expect(log.all.isEmpty)
            }

            #expect(log.all == ["hook"])

            // The write the hook rode with is durable.
            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 4)
        }
    }

    /// A hook deferred inside a `liveTransaction` whose closure throws never runs — the rollback
    /// discards the hooks with the identities.
    @Test func hookNeverRunsWhenTheTransactionThrows() async throws {
        let log = HookLog()
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)

            await #expect(throws: HookFailure.self) {
                try await app.liveTransaction { tx in
                    let berth = try Berth(number: 101, dockName: dock1.name, dockId: dock1.requireId())
                    try await berth.save(on: tx)
                    #expect(await LiveTransactionState.deferUntilCommit(on: tx) { log.append("hook") })
                    throw HookFailure()
                }
            }

            #expect(log.all.isEmpty)

            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 3) // rolled back to the seeded three
        }
    }

    /// Handed a database that is already in a transaction, a nested `liveTransaction` joins the
    /// enclosing one: Fluent runs the closure on that same connection with no savepoint
    /// (`FluentSQLiteDatabase.swift:92-95`, `guard !inTransaction`), one BEGIN/COMMIT spans both,
    /// and every hook runs once, after the OUTERMOST commit.
    ///
    /// The shared core is called directly because `req.db`/`app.db` never answer an in-transaction
    /// handle — this is the join branch's only reachable caller.
    @Test func nestedLiveTransactionOnTheSameConnectionDrainsAtTheOutermostCommit() async throws {
        let log = HookLog()
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)

            try await app.liveTransaction { outer in
                #expect(outer.inTransaction)
                #expect(await LiveTransactionState.deferUntilCommit(on: outer) { log.append("outer") })

                try await runLiveTransaction(hub: app.invalidationHub, db: outer) { inner in
                    let berth = try Berth(number: 102, dockName: dock1.name, dockId: dock1.requireId())
                    try await berth.save(on: inner)
                    #expect(await LiveTransactionState.deferUntilCommit(on: inner) { log.append("inner") })
                }

                // The inner call returned; it drained nothing.
                #expect(log.all.isEmpty)
            }

            #expect(log.all == ["outer", "inner"])

            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 4)
        }
    }

    /// Handed a fresh database — which is what `req.db` and `app.db` answer — a nested
    /// `liveTransaction` is a second, independent transaction: it drains its own hooks on its own
    /// commit, and what it wrote stands even when the enclosing transaction later throws.
    @Test func independentNestedLiveTransactionDrainsOnItsOwnCommit() async throws {
        let log = HookLog()
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let req = Vapor.Request(application: app, on: app.eventLoopGroup.next())

            await #expect(throws: HookFailure.self) {
                try await req.liveTransaction { outer in
                    try await app.liveTransaction { inner in
                        #expect(inner.inTransaction)
                        let berth = try Berth(number: 104, dockName: dock1.name, dockId: dock1.requireId())
                        try await berth.save(on: inner)
                        #expect(await LiveTransactionState.deferUntilCommit(on: inner) { log.append("inner") })
                    }

                    // The inner transaction committed and drained itself, before the outer's fate
                    // is known.
                    #expect(log.all == ["inner"])

                    #expect(await LiveTransactionState.deferUntilCommit(on: outer) { log.append("outer") })
                    throw HookFailure()
                }
            }

            // The outer rolled back, so its hook never ran; the inner's row is durable regardless.
            #expect(log.all == ["inner"])

            let count = try await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).count()
            #expect(count == 4)
        }
    }

    /// With live invalidation enabled the hooks run BEFORE the identity set reaches subscribers:
    /// a client nudged by the emit finds the hooks' work already done.
    ///
    /// Ordering is proven with the suite-wide sentinel idiom, not by watching two tasks race: the
    /// hook parks until the test has emitted a sentinel of its own, so the write's set can only
    /// reach the subscriber behind that sentinel if — and only if — the drain emits after the
    /// hooks have run.
    @Test func hooksRunBeforeTheEmit() async throws {
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
            try app.useLiveInvalidation(on: app.routes)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let (hookStarted, announceHookStarted) = AsyncStream<Void>.makeStream()
            let (hookMayFinish, releaseHook) = AsyncStream<Void>.makeStream()

            let berth = try Berth(number: 103, dockName: dock1.name, dockId: dock1.requireId())
            let write = Task {
                try await app.liveTransaction { tx in
                    _ = await LiveTransactionState.deferUntilCommit(on: tx) {
                        announceHookStarted.yield()
                        for await _ in hookMayFinish {
                            break
                        }
                    }
                    try await berth.save(on: tx)
                }
            }

            // The hook is mid-flight, so the transaction has committed …
            for await _ in hookStarted {
                break
            }
            let sentinel = try Set([harbor.modelIdentity])
            await hub.emit(sentinel)
            releaseHook.yield()
            try await write.value

            // … and the write's own set arrives only behind the sentinel.
            let written = try Set([berth.modelIdentity, dock1.modelIdentity])
            #expect(await events.next() == sentinel)
            #expect(await events.next() == written)
        }
    }

    /// The discriminator the lifecycle middleware routes on: collected inside `liveTransaction`,
    /// not collected inside a bare `database.transaction`, not collected on an auto-commit write —
    /// including a write made on an auto-commit handle while a `liveTransaction` is open.
    @Test func deferUntilCommitCollectsOnlyInsideLiveTransaction() async throws {
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
        } _: { app, db in
            #expect(await LiveTransactionState.deferUntilCommit(on: db) {} == false)

            try await db.transaction { tx in
                #expect(await LiveTransactionState.deferUntilCommit(on: tx) {} == false)
            }

            try await app.liveTransaction { tx in
                #expect(await LiveTransactionState.deferUntilCommit(on: tx) {})
                #expect(await LiveTransactionState.deferUntilCommit(on: app.db) {} == false)
            }
        }
    }

    /// The suppression warning is offered once per model type, and lives beside the live
    /// invalidation broadcaster rather than inside it — an application with no broadcaster still
    /// warns once.
    @Test func suppressionWarningIsOfferedOncePerModelType() async throws {
        try await withFluentTestApp { app in
            try registerHarborGraph(app)
        } _: { app, _ in
            #expect(app.shouldWarnSuppressedAfterCommit(for: Berth.self))
            #expect(app.shouldWarnSuppressedAfterCommit(for: Berth.self) == false)
            #expect(app.shouldWarnSuppressedAfterCommit(for: Dock.self))
        }
    }
}

private struct HookFailure: Error {}

/// Registers the harbor graph; live invalidation is left off unless the test enables it.
private func registerHarborGraph(_ app: Application) throws {
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
}

/// Lock-guarded ordered log shared between the deferred hooks, the subscriber and the assertions.
private final class HookLog: @unchecked Sendable {
    private let lock = NIOLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }

    var all: [String] {
        lock.withLock { entries }
    }
}
