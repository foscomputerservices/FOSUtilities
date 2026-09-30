// BehavioralCommitTests.swift
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
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

private struct BehavioralTransactionFailure: Error {}

/// Design 1.3 steps 7–8, 1.9 (OQ3/OQ14) and DocC 4.4: `didWrite` is in the transaction, and
/// `didCommit` runs only when the write became durable.
@Suite("Behavioral: didWrite rollback and didCommit routing")
struct BehavioralCommitTests {
    // MARK: - didWrite

    @Test("A throw from didWrite rolls the transaction back and leaves no row")
    func didWriteThrowRollsBackTheRow() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            await #expect(throws: BehavioralHookFailure(hook: "didWrite")) {
                try await app.liveTransaction { tx in
                    try await BehavioralProbe(title: BehavioralTitle.didWriteThrow).save(on: tx)
                }
            }

            let written = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(written == 0)
            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 0)
        }
    }

    @Test("A throw from didWrite propagates from an auto-commit save")
    func didWriteThrowPropagatesOnAnAutoCommitSave() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            await #expect(throws: BehavioralHookFailure(hook: "didWrite")) {
                try await BehavioralProbe(title: BehavioralTitle.didWriteThrow).save(on: db)
            }

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 0)
        }
    }

    /// negative space: "May write rows. A throw rolls the transaction back" — the rows the hook
    /// itself wrote go back too when the enclosing transaction fails.
    @Test("Rows written by didWrite roll back with the transaction")
    func rowsWrittenByDidWriteRollBack() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            await #expect(throws: BehavioralTransactionFailure.self) {
                try await app.liveTransaction { tx in
                    try await BehavioralProbe(title: BehavioralTitle.didWriteWrites).save(on: tx)
                    throw BehavioralTransactionFailure()
                }
            }

            let probes = try await BehavioralProbe.query(on: db).withDeleted().count()
            let orphans = try await BehavioralOrphan.query(on: db).count()
            #expect(probes == 0)
            #expect(orphans == 0)
        }
    }

    @Test("didWrite sees the same database as the write, so its rows commit with it")
    func rowsWrittenByDidWriteCommitWithTheWrite() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            try await app.liveTransaction { tx in
                try await BehavioralProbe(title: BehavioralTitle.didWriteWrites).save(on: tx)
            }

            let orphans = try await BehavioralOrphan.query(on: db).count()
            #expect(orphans == 1)
        }
    }

    // MARK: - didCommit, the three routes

    @Test("An auto-commit save runs didCommit immediately")
    func autoCommitSaveRunsDidCommit() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            try await BehavioralProbe(title: BehavioralTitle.ok).save(on: db)

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 1)
        }
    }

    @Test("Inside liveTransaction didCommit runs only after the closure returns")
    func liveTransactionRunsDidCommitAfterTheClosure() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, _ in
            let box = try #require(app.behavioralEvents)

            try await app.liveTransaction { tx in
                try await BehavioralProbe(title: BehavioralTitle.ok).save(on: tx)
                #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 0)
            }

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 1)
        }
    }

    @Test("Inside a bare database transaction didCommit does not run")
    func bareTransactionSuppressesDidCommit() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            try await db.transaction { tx in
                try await BehavioralProbe(title: BehavioralTitle.ok).save(on: tx)
            }

            // The write landed …
            let written = try await BehavioralProbe.query(on: db).count()
            #expect(written == 1)
            // … and the hook that needed to see the commit never ran.
            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 0)
        }
    }

    @Test("A liveTransaction that throws discards didCommit")
    func throwingLiveTransactionDiscardsDidCommit() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            await #expect(throws: BehavioralTransactionFailure.self) {
                try await app.liveTransaction { tx in
                    try await BehavioralProbe(title: BehavioralTitle.ok).save(on: tx)
                    throw BehavioralTransactionFailure()
                }
            }

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 0)
            let written = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(written == 0)
        }
    }

    @Test("A nested liveTransaction runs didCommit once, on its own commit")
    func nestedLiveTransactionRunsDidCommitOnceOnItsOwnCommit() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, _ in
            let box = try #require(app.behavioralEvents)

            try await app.liveTransaction { outer in
                // A request pinned off the outer's event loop, so the inner transaction never waits
                // on the outer's connection — see makeRequest(_:offTheLoopOf:).
                let req = try #require(makeRequest(app, offTheLoopOf: outer))
                try await req.liveTransaction { inner in
                    try await BehavioralProbe(title: BehavioralTitle.ok).save(on: inner)
                }
                // `req.liveTransaction` takes a database of its own, so the inner call is its own
                // transaction: it has committed, and its after-commit work has already run.
                #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 1)
            }

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 1)
        }
    }

    @Test("didCommit runs with live invalidation enabled, as it does without it")
    func didCommitRunsWithLiveInvalidationEnabled() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
            try app.useLiveInvalidation(on: app.routes)
        } _: { app, _ in
            let box = try #require(app.behavioralEvents)

            try await app.liveTransaction { tx in
                try await BehavioralProbe(title: BehavioralTitle.ok).save(on: tx)
            }

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 1)
        }
    }

    /// negative space: two writes of the SAME model in one transaction. Each write is its own
    /// Fluent event, so each defers its own didCommit and the commit runs both.
    @Test("Two writes of one model in one transaction run didCommit twice")
    func twoWritesOfOneModelRunDidCommitTwice() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, _ in
            let box = try #require(app.behavioralEvents)

            try await app.liveTransaction { tx in
                let probe = BehavioralProbe(title: BehavioralTitle.ok)
                try await probe.save(on: tx)
                probe.title = "Wilma"
                try await probe.save(on: tx)
            }

            #expect(box.count(of: "didCommit(create)", of: BehavioralProbe.self) == 1)
            #expect(box.count(of: "didCommit(update)", of: BehavioralProbe.self) == 1)
        }
    }
}
