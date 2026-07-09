// InvalidationEmitMiddleware.swift
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

import FluentKit
import FOSMVVM
import Foundation

// L2 live-invalidation, emit side (spec §3.1): the DERIVATION half (InvalidationIdentitySet —
// given a just-mutated record and the type registry, the set of ``ModelIdentity`` that just went
// stale, zero author code, D-L2-2) and the ROUTING half composed onto it
// (InvalidationEmitMiddleware — the per-type Fluent ModelMiddleware that is the layer's only
// emit point).

/// The only emit point (spec §3.1): fires after each completed Fluent mutation of `M` and routes
/// the derived staleness set in pinned order — task-local collector present → COLLECT (its
/// `liveTransaction` flushes on commit); else `db.inTransaction` → SUPPRESS + warn once per model
/// type (a bare transaction exposes no commit hook, and an early emit is a stale-forever hazard);
/// else → EMIT to the hub (an auto-commit save's middleware completion IS post-commit). The hub
/// is injected at registration — never attached to `Database`. One instance exists per model type
/// in the registered graph (`Application.registerInvalidationEmitMiddleware`): FluentKit's
/// generic middleware type-filters, and only the generic async path preserves the task-local.
struct InvalidationEmitMiddleware<M: DataModel>: AsyncModelMiddleware {
    let hub: InvalidationHub
    /// Reads the LIVE registry (weak-app closure): containers registered after this middleware
    /// was wired must still contribute to the inversion — a snapshot would silently pin the
    /// derivation to registration order.
    let registryReader: @Sendable () -> ModelTypeRegistry

    func create(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await next.create(model, on: db)
        await route(model, on: db)
    }

    func update(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await next.update(model, on: db)
        await route(model, on: db)
    }

    func delete(model: M, force: Bool, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await next.delete(model, force: force, on: db)
        await route(model, on: db)
    }

    /// softDelete/restore are membership-visibility mutations — routed like the three verbs.
    func softDelete(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await next.softDelete(model, on: db)
        await route(model, on: db)
    }

    func restore(model: M, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        try await next.restore(model, on: db)
        await route(model, on: db)
    }

    private func route(_ model: M, on db: any Database) async {
        let stale = InvalidationIdentitySet.staleIdentities(
            forMutated: model,
            registry: registryReader()
        )

        if let collector = LiveTransactionState.collector {
            await collector.collect(stale)
        } else if db.inTransaction {
            let typeName = String(describing: M.self)
            if await hub.shouldWarnSuppressedEmit(for: typeName) {
                db.logger.warning(
                    "A \(typeName) write inside a bare database.transaction { } cannot notify live clients — FOSMVVM cannot see whether the transaction commits, so this write's invalidation was suppressed. Use liveTransaction { } to nudge live clients on commit. (Warned once per model type.)"
                )
            }
        } else {
            await hub.emit(stale)
        }
    }
}

/// The containment-derived staleness surface of a single mutation.
enum InvalidationIdentitySet {
    /// The identities that just went stale when `mutated` was saved/deleted: its own identity plus
    /// the identities of every registered container it belongs to. Read straight off the instance's
    /// join references (no DB): a `.children` member reads its owner FK, a `.siblings` pivot reads
    /// both linked ends, a `.parent`-declared owner reads its to-one target. A record no registered
    /// container declares yields only its own identity.
    static func staleIdentities(
        forMutated mutated: any DataModel,
        registry: ModelTypeRegistry
    ) -> Set<ModelIdentity> {
        var identities: Set<ModelIdentity> = []
        if let own = try? mutated.modelIdentity {
            identities.insert(own)
        }

        let isRegisteredContainer: @Sendable (any DataModel.Type) -> Bool = { type in
            registry.registered(for: type.modelIdentityNamespace) != nil
        }

        for descriptor in registry.allRegistered {
            for relation in descriptor.containment {
                identities.formUnion(
                    relation.staleContainerIdentities(
                        forMutated: mutated,
                        isRegisteredContainer: isRegisteredContainer
                    )
                )
            }
        }

        return identities
    }
}
