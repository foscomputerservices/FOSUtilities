// InvalidateProjections.swift
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

import FOSMVVM
import Foundation
import Vapor

public extension Vapor.Application {
    /// Nudges live clients to refresh every projection built from `model`
    ///
    /// Call it at each point a non-Fluent source commits a change — an
    /// `Application`-hosted actor mutating its state, a computed aggregate
    /// going stale:
    ///
    /// ```swift
    /// actor StatusMonitor {
    ///     // Minted once — the identity of "the status" for this process's
    ///     // lifetime. A restart is covered: reconnecting clients refresh
    ///     // every live screen.
    ///     private let statusId = ModelIdType()
    ///     private var activeSessions = 0
    ///
    ///     func sessionOpened(app: Application) async throws {
    ///         activeSessions += 1
    ///         try await app.invalidateProjections(of: snapshot())
    ///     }
    ///
    ///     func snapshot() -> StatusSnapshot {
    ///         .init(id: statusId, activeSessions: activeSessions)
    ///     }
    /// }
    /// ```
    ///
    /// Clients refresh the ViewModels whose factory called
    /// ``FOSMVVM/ProjectionContext/registerDependency(on:)`` for this model.
    /// Fluent-persisted models never need this call — their saves already
    /// notify live clients. When the change ships together with Fluent writes,
    /// make the call inside ``liveTransaction(_:)`` and it reaches clients
    /// only if the transaction commits. With live invalidation not enabled
    /// (no `useLiveInvalidation(on:)` at boot) it is a no-op.
    ///
    /// - Throws: `ModelError.missingId` when `model.id` is `nil`.
    func invalidateProjections(of model: some FOSMVVM.Model) async throws {
        try await routeProjectionInvalidation(of: model, hub: invalidationHub)
    }
}

public extension Vapor.Request {
    /// Nudges live clients to refresh every projection built from `model`
    ///
    /// The request-scoped spelling of
    /// ``Vapor/Application/invalidateProjections(of:)`` — same behavior, for
    /// call sites inside a route handler:
    ///
    /// ```swift
    /// try await req.invalidateProjections(of: status)
    /// ```
    func invalidateProjections(of model: some FOSMVVM.Model) async throws {
        try await application.invalidateProjections(of: model)
    }
}

/// The shared routing core, following the middleware's collector-first precedence
/// (InvalidationEmitMiddleware.route): task-local collector present → COLLECT
/// (its liveTransaction flushes on commit); else hub present → EMIT; else live
/// invalidation is not enabled → no-op. A collector is only ever installed by
/// liveTransaction, which requires a hub — so collector-first never strands a nudge.
private func routeProjectionInvalidation(
    of model: some FOSMVVM.Model,
    hub: InvalidationHub?
) async throws {
    let identity = try model.modelIdentity

    if let collector = LiveTransactionState.collector {
        await collector.collect([identity])
    } else if let hub {
        await hub.emit([identity])
    }
}
