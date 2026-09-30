// LiveTransaction.swift
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
import FOSMVVM
import Foundation
import Vapor

public extension Vapor.Request {
    /// A Fluent transaction whose writes still notify live clients
    ///
    /// Inside a bare `database.transaction { }` FOSMVVM cannot know whether your
    /// writes commit, so it stays silent (and logs a warning). Use
    /// `liveTransaction` instead and every write inside the closure nudges live
    /// clients if — and only if — the transaction commits:
    ///
    /// ```swift
    /// try await req.liveTransaction { db in
    ///     dock.status = .closed
    ///     try await dock.save(on: db)
    /// }
    /// ```
    ///
    /// ``DataModelLifecycle/didCommit(in:)`` of every model written inside the closure runs once the
    /// transaction commits, whether or not live invalidation is enabled, so use `liveTransaction`
    /// wherever a hook must see a durable row.
    ///
    /// > Note: One `liveTransaction` opened inside another is a second, independent transaction
    /// > that commits — and runs the work collected inside it — on its own, so nest one only when
    /// > its writes are meant to stand whether or not the enclosing transaction commits.
    ///
    /// > Warning: On SQLite, write only through the database the closure hands you. SQLite holds one
    /// > connection per event loop, and the transaction holds it, so a query on `req.db` or `app.db`
    /// > from inside the closure can wait for that same connection and fail after the pool timeout.
    func liveTransaction<T: Sendable>(
        _ closure: @Sendable @escaping (any Database) async throws -> T
    ) async throws -> T {
        try await runLiveTransaction(hub: application.invalidationHub, db: db, closure)
    }
}

public extension Vapor.Application {
    /// A Fluent transaction whose writes still notify live clients
    ///
    /// Inside a bare `database.transaction { }` FOSMVVM cannot know whether your
    /// writes commit, so it stays silent (and logs a warning). Use
    /// `liveTransaction` instead — from background jobs and other
    /// application-level work — and every write inside the closure nudges live
    /// clients if — and only if — the transaction commits:
    ///
    /// ```swift
    /// try await app.liveTransaction { db in
    ///     dock.status = .closed
    ///     try await dock.save(on: db)
    /// }
    /// ```
    ///
    /// ``DataModelLifecycle/didCommit(in:)`` of every model written inside the closure runs once the
    /// transaction commits, whether or not live invalidation is enabled, so use `liveTransaction`
    /// wherever a hook must see a durable row.
    ///
    /// > Note: One `liveTransaction` opened inside another is a second, independent transaction
    /// > that commits — and runs the work collected inside it — on its own, so nest one only when
    /// > its writes are meant to stand whether or not the enclosing transaction commits.
    ///
    /// > Warning: On SQLite, write only through the database the closure hands you. SQLite holds one
    /// > connection per event loop, and the transaction holds it, so a query on `req.db` or `app.db`
    /// > from inside the closure can wait for that same connection and fail after the pool timeout.
    func liveTransaction<T: Sendable>(
        _ closure: @Sendable @escaping (any Database) async throws -> T
    ) async throws -> T {
        try await runLiveTransaction(hub: invalidationHub, db: db, closure)
    }
}

/// The wrappers' shared core: run the transaction with the collector installed — always, whether
/// or not live invalidation is enabled, since after-commit hooks need the collector either way —
/// then drain it after `db.transaction` returns (committed): the after-commit hooks first, then
/// the collected union to the broadcaster if there is one. A throw skips the drain — discard is
/// automatic.
///
/// Internal rather than file-private: it is the only seam through which a nested call can be handed
/// a database already in a transaction, which `Request`/`Application` never do, so the join branch
/// below is reachable only from here.
func runLiveTransaction<T: Sendable>(
    hub: InvalidationHub?,
    db: any Database,
    _ closure: @Sendable @escaping (any Database) async throws -> T
) async throws -> T {
    // A nested call joins the enclosing collector only when the handle it was given is ALREADY in a
    // transaction: Fluent then runs the closure on that same connection with no savepoint
    // (FluentSQLiteDatabase.swift:92-95, `guard !inTransaction`), so one BEGIN/COMMIT spans both and
    // the collected work belongs to the outermost commit. Handed a fresh handle — which is what
    // `req.db`/`app.db` answer — it opens a second, independent transaction that commits on its
    // own, so it takes a collector of its own and drains it on that commit.
    let joined = db.inTransaction ? LiveTransactionState.collector : nil
    let collector = joined ?? InvalidationCollector()

    // Binding site (spec §3.1, pinned): INSIDE the closure handed to db.transaction. FluentKit's
    // async transaction bridges through an unstructured Task (Database+Concurrency.swift:26,
    // eventLoop.makeFutureWithTask), so a binding AROUND the transaction call never reaches the
    // middleware — spike-verified both placements.
    let result = try await db.transaction { tx in
        try await LiveTransactionState.$collector.withValue(collector) {
            try await closure(tx)
        }
    }

    guard joined == nil else {
        return result
    }

    for hook in await collector.drainHooks() {
        await hook()
    }
    if let hub {
        await hub.emit(collector.drain())
    }
    return result
}

/// The collect-vs-suppress discriminator: `liveTransaction` installs the
/// collector for its closure's duration; the emit middleware and the lifecycle middleware route
/// on its presence — ambient to the transaction's task tree, attached to nothing, invisible in any
/// API: nothing is attached to the `Database`.
enum LiveTransactionState {
    @TaskLocal static var collector: InvalidationCollector?

    /// Hands `hook` to the enclosing `liveTransaction`, to run once that transaction commits.
    /// False when no `liveTransaction` encloses this call, and false when `db` is not itself in a
    /// transaction: a write made on an auto-commit handle inside a `liveTransaction` is already
    /// durable and is not the transaction's to defer. The caller decides between running the work
    /// now (an auto-commit write) and suppressing it (a bare `database.transaction`, which
    /// exposes no commit to wait for).
    static func deferUntilCommit(
        on db: any Database,
        _ hook: @escaping @Sendable () async -> Void
    ) async -> Bool {
        guard db.inTransaction, let collector else {
            return false
        }

        await collector.collect(hook)
        return true
    }
}

/// Accumulates what one `liveTransaction` owes on commit: the identity sets the emit middleware
/// derives, and the after-commit hooks the lifecycle middleware defers. Drained when the
/// transaction that installed it commits; never drained on rollback (the wrapper's throw path
/// skips it).
actor InvalidationCollector {
    private var identities: Set<ModelIdentity> = []
    private var hooks: [@Sendable () async -> Void] = []

    func collect(_ stale: Set<ModelIdentity>) {
        identities.formUnion(stale)
    }

    func collect(_ hook: @escaping @Sendable () async -> Void) {
        hooks.append(hook)
    }

    func drain() -> Set<ModelIdentity> {
        defer { identities = [] }
        return identities
    }

    /// The deferred hooks in the order they were collected. For writes issued one at a time that
    /// is write order; a batch write hands its models to the middleware before the statement
    /// runs, so no order is promised across a batch.
    func drainHooks() -> [@Sendable () async -> Void] {
        defer { hooks = [] }
        return hooks
    }
}

extension Vapor.Application {
    /// True exactly once per model type — gates the warning that a bare `database.transaction`
    /// cannot run after-commit work. Kept in `Application.storage` rather than on the
    /// live-invalidation broadcaster (`InvalidationHub`): after-commit hooks run with or without
    /// live invalidation, so there may be no broadcaster to hold it.
    func shouldWarnSuppressedAfterCommit(for modelType: any Any.Type) -> Bool {
        locks.lock(for: AfterCommitWarningLock.self).withLock {
            var warned = storage[AfterCommitWarningStore.self] ?? []
            let isFirst = warned.insert(ObjectIdentifier(modelType)).inserted
            storage[AfterCommitWarningStore.self] = warned
            return isFirst
        }
    }
}

private struct AfterCommitWarningStore: StorageKey {
    typealias Value = Set<ObjectIdentifier>
}

private struct AfterCommitWarningLock: LockKey {}
