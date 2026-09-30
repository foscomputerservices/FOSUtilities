// LifecycleWiringTests.swift
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

// Which types the registration sweep covers, observed through the hooks each one runs. The last
// test subscribes to the INTERNAL broadcaster through @testable — block coverage of that seam,
// the way EmitMiddlewareTests does.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("Lifecycle middleware wiring (plan 1.9, OQ19)")
struct LifecycleWiringTests {
    /// A type a registered container declares runs its hooks without a registration of its own.
    @Test func aContainedTypeRunsItsHooks() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)
            try await Entry(label: "contained", ledgerId: ledger.requireId(), vaultId: vault.requireId())
                .save(on: db)

            #expect(app.lifecycleEvents.all.contains("Entry.willWrite:create"))
        }
    }

    /// A membership change is a pivot write, and the pivot's hooks run on it.
    @Test func aPivotRunsItsHooks() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, _) = try await seedLedger(on: db)
            let auditor = Auditor(name: "Ada")
            try await auditor.save(on: db)

            try await LedgerAuditor(ledgerId: ledger.requireId(), auditorId: auditor.requireId())
                .save(on: db)

            #expect(app.lifecycleEvents.count(of: "LedgerAuditor.willWrite:create") == 1)
        }
    }

    /// `Entry` enters the coverage set through two containers; one save still runs its hooks once.
    @Test func aTypeTwoContainersDeclareRunsItsHooksOnce() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let (ledger, vault) = try await seedLedger(on: db)
            let entry = try Entry(label: "once", ledgerId: ledger.requireId(), vaultId: vault.requireId())

            try await entry.save(on: db)

            #expect(app.lifecycleEvents.count(of: "Entry.willWrite:create") == 1)
            #expect(entry.trace == [
                "willWrite", "fieldValidation", "validateModel", "didWrite", "didCommit"
            ])
        }
    }

    /// A model no registration reaches runs no hooks — its migration alone wires nothing.
    @Test func anUnregisteredModelRunsNoHooks() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            try await Stray(note: "loose").save(on: db)

            #expect(app.lifecycleEvents.all.isEmpty)
            let count = try await Stray.query(on: db).count()
            #expect(count == 1)
        }
    }

    /// A model no container declares runs its hooks once it is registered with its migration.
    @Test func aRegisteredModelWithNoContainerRunsItsHooks() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            try await Beacon(note: "lit").save(on: db)

            #expect(app.lifecycleEvents.all.contains("Beacon.willWrite:create"))
            #expect(app.lifecycleEvents.all.contains("Beacon.didCommit:create"))
        }
    }

    /// A model that declares no hook saves exactly as it did before the lifecycle shipped.
    @Test func aModelWithNoHooksSavesUnchanged() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { app, db in
            let plain = Plain(note: "quiet")
            try await plain.save(on: db)

            #expect(app.lifecycleEvents.all.isEmpty)
            let stored = try #require(await Plain.find(plain.requireId(), on: db))
            #expect(stored.note == "quiet")
        }
    }

    /// Registering a model that declares no containment never makes it answer as a container: the
    /// containment inversion still attributes staleness only to real containers.
    @Test func aRegisteredModelWithNoContainerIsNotAContainer() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
            try app.useLiveInvalidation(on: app.routes)
        } _: { app, db in
            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            let beacon = Beacon(note: "alone")
            try await beacon.save(on: db)

            let expected = try Set([beacon.modelIdentity])
            #expect(await events.next() == expected)
        }
    }

    /// The middleware holds its `Application` weakly, so a write that outlives the application
    /// finds nothing to run the hooks against. It refuses the write rather than letting an
    /// unvalidated row through, and the message names the model and the action.
    @Test func aWriteThatOutlivesItsApplicationIsRefused() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            let reachedNext = LifecycleEventBox()
            let middleware = DataModelLifecycleMiddleware<Beacon>(applicationReader: { nil })
            let beacon = Beacon(note: "orphan")

            do {
                try await middleware.create(
                    model: beacon,
                    on: db,
                    next: RecordingResponder { reachedNext.append("next") }
                )
                Issue.record("the write was not refused")
            } catch let error as DataModelLifecycleError {
                guard case .applicationShutDown(let modelType, let action) = error else {
                    Issue.record("unexpected case: \(error)")
                    return
                }
                #expect(modelType == "Beacon")
                #expect(action == .create)
                #expect(error.debugDescription.contains("Beacon"))
            }

            #expect(reachedNext.all.isEmpty)
            #expect(try await Beacon.query(on: db).count() == 0)
        }
    }
}

/// Stands in for the responder FluentKit hands the middleware, so the refusal can be observed as
/// the write never reaching it.
private struct RecordingResponder: AnyAsyncModelResponder {
    let onHandle: @Sendable () -> Void

    init(_ onHandle: @escaping @Sendable () -> Void) {
        self.onHandle = onHandle
    }

    func handle(_: ModelEvent, _: any AnyModel, on _: any Database) async throws {
        onHandle()
    }

    /// FluentKit's future-returning bridge is internal to that module, so the synchronous half of
    /// the protocol has to be answered here.
    func handle(_: ModelEvent, _: any AnyModel, on db: any Database) -> EventLoopFuture<Void> {
        onHandle()
        return db.eventLoop.makeSucceededVoidFuture()
    }
}
