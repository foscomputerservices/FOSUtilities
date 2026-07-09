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
    func liveTransaction<T: Sendable>(
        _ closure: @Sendable @escaping (any Database) async throws -> T
    ) async throws -> T {
        try await runLiveTransaction(hub: invalidationHub, db: db, closure)
    }
}

/// The wrappers' shared core: run the transaction with the collector installed, flush the
/// collected union to the hub only after `db.transaction` returns (committed); a throw skips the
/// flush — discard is automatic. With no hub (live invalidation not enabled) the wrapper IS the
/// plain transaction.
private func runLiveTransaction<T: Sendable>(
    hub: InvalidationHub?,
    db: any Database,
    _ closure: @Sendable @escaping (any Database) async throws -> T
) async throws -> T {
    guard let hub else {
        return try await db.transaction(closure)
    }

    let collector = InvalidationCollector()
    // Binding site (spec §3.1, pinned): INSIDE the closure handed to db.transaction. FluentKit's
    // async transaction bridges through an unstructured Task (Database+Concurrency.swift:26,
    // eventLoop.makeFutureWithTask), so a binding AROUND the transaction call never reaches the
    // middleware — spike-verified both placements.
    let result = try await db.transaction { tx in
        try await LiveTransactionState.$collector.withValue(collector) {
            try await closure(tx)
        }
    }
    await hub.emit(collector.drain())
    return result
}

/// The collect-vs-suppress discriminator (spec §3.1, pinned): `liveTransaction` installs the
/// collector for its closure's duration; the emit middleware routes on its presence — ambient to
/// the transaction's task tree, attached to nothing, invisible in any API (the north star's
/// no-`Database`-attachment rule).
enum LiveTransactionState {
    @TaskLocal static var collector: InvalidationCollector?
}

/// Accumulates the identity sets the emit middleware derives inside one `liveTransaction`.
/// Drained to the hub on commit; never drained on rollback (the wrapper's throw path skips it).
actor InvalidationCollector {
    private var identities: Set<ModelIdentity> = []

    func collect(_ stale: Set<ModelIdentity>) {
        identities.formUnion(stale)
    }

    func drain() -> Set<ModelIdentity> {
        defer { identities = [] }
        return identities
    }
}
