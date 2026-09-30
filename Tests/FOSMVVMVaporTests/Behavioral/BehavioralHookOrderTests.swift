// BehavioralHookOrderTests.swift
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

/// Design 1.3 ("The sequence, per action") and 1.2 ("what Fluent is about to do to one row").
@Suite("Behavioral: hook order and per-action reach")
struct BehavioralHookOrderTests {
    @Test("A create runs willWrite, validateModel, didWrite, didCommit, in that order")
    func createRunsEveryHookInOrder() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            try await BehavioralProbe(title: BehavioralTitle.ok).save(on: db)

            #expect(box.events(of: BehavioralProbe.self) == [
                "willWrite(create)",
                "validateModel(create)",
                "didWrite(create)",
                "didCommit(create)"
            ])
        }
    }

    @Test("An update reaches every hook with the update action")
    func updateReachesEveryHook() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            probe.title = "Wilma"
            try await probe.save(on: db)

            #expect(box.events(of: BehavioralProbe.self).suffix(4) == [
                "willWrite(update)",
                "validateModel(update)",
                "didWrite(update)",
                "didCommit(update)"
            ])
        }
    }

    @Test("A soft delete reaches every hook with the archive action")
    func archiveReachesEveryHook() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            try await probe.delete(on: db)

            #expect(box.events(of: BehavioralProbe.self).suffix(4) == [
                "willWrite(archive)",
                "validateModel(archive)",
                "didWrite(archive)",
                "didCommit(archive)"
            ])
            // The row stays, marked deleted.
            let archived = try await BehavioralProbe.query(on: db).withDeleted().all()
            #expect(archived.count == 1)
            #expect(archived.first?.deletedAt != nil)
        }
    }

    @Test("A forced delete reaches every hook with the destroy action and removes the row")
    func destroyReachesEveryHook() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            try await probe.delete(force: true, on: db)

            #expect(box.events(of: BehavioralProbe.self).suffix(4) == [
                "willWrite(destroy)",
                "validateModel(destroy)",
                "didWrite(destroy)",
                "didCommit(destroy)"
            ])
            let remaining = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(remaining == 0)
        }
    }

    @Test("A restore reaches every hook with the restore action")
    func restoreReachesEveryHook() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)
            try await probe.delete(on: db)

            let archived = try #require(await BehavioralProbe.query(on: db).withDeleted().first())
            try await archived.restore(on: db)

            #expect(box.events(of: BehavioralProbe.self).suffix(4) == [
                "willWrite(restore)",
                "validateModel(restore)",
                "didWrite(restore)",
                "didCommit(restore)"
            ])
            let live = try await BehavioralProbe.query(on: db).count()
            #expect(live == 1)
        }
    }

    /// negative space: "a model with a @Timestamp(on: .delete) archives on a plain delete(on:) and
    /// destroys on delete(force: true, on:); a model WITHOUT one destroys on either" (DocC 4.1).
    @Test("A plain delete of a model with no delete timestamp is a destroy")
    func plainDeleteOfATimestamplessModelIsDestroy() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let plain = BehavioralPlain(name: "Fred")
            try await plain.save(on: db)

            try await plain.delete(on: db)

            #expect(box.events(of: BehavioralPlain.self).suffix(4) == [
                "willWrite(destroy)",
                "validateModel(destroy)",
                "didWrite(destroy)",
                "didCommit(destroy)"
            ])
        }
    }

    /// negative space: "willWrite … may mutate itself (derived dates, trimming, flags)" runs at
    /// step 1, BEFORE field validation at step 2 — so a title that is only whitespace is empty by
    /// the time the required-rule sees it. Order alone makes this observable.
    @Test("A whitespace-only title is refused, because willWrite trimmed it before field validation ran")
    func whitespaceOnlyTitleIsRefusedAfterTrimming() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            await #expect(throws: ValidationError.self) {
                try await BehavioralProbe(title: "   ").save(on: db)
            }
            let remaining = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(remaining == 0)
        }
    }

    @Test("Field validation does not run for an archive")
    func fieldValidationDoesNotRunForArchive() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            // The in-memory model now fails its own field rule; archiving writes no columns.
            probe.title = BehavioralTitle.fieldInvalid
            try await probe.delete(on: db)

            let remaining = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(remaining == 1)
        }
    }

    @Test("Field validation does not run for a destroy")
    func fieldValidationDoesNotRunForDestroy() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)

            probe.title = BehavioralTitle.fieldInvalid
            try await probe.delete(force: true, on: db)

            let remaining = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(remaining == 0)
        }
    }

    @Test("Field validation does not run for a restore")
    func fieldValidationDoesNotRunForRestore() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { _, db in
            let probe = BehavioralProbe(title: BehavioralTitle.ok)
            try await probe.save(on: db)
            try await probe.delete(on: db)

            let archived = try #require(await BehavioralProbe.query(on: db).withDeleted().first())
            archived.title = BehavioralTitle.fieldInvalid
            try await archived.restore(on: db)

            let live = try await BehavioralProbe.query(on: db).count()
            #expect(live == 1)
        }
    }

    /// negative space: "May throw, and a throw is an error, never a validation" — a willWrite throw
    /// stops the sequence at step 1, so nothing downstream of it runs and no row is written.
    @Test("A throw from willWrite stops the sequence before validation and writes nothing")
    func willWriteThrowStopsEverything() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            await #expect(throws: BehavioralHookFailure(hook: "willWrite")) {
                try await BehavioralProbe(title: BehavioralTitle.willWriteThrow).save(on: db)
            }

            #expect(box.events(of: BehavioralProbe.self) == ["willWrite(create)"])
            let remaining = try await BehavioralProbe.query(on: db).withDeleted().count()
            #expect(remaining == 0)
        }
    }
}
