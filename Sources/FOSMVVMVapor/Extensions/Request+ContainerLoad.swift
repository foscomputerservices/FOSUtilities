// Request+ContainerLoad.swift
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

extension Vapor.Request {
    /// The C8 entry: acquisition + scoping in one call (spec C3.3). Opens the stored provider (cheap;
    /// no fetch) and forwards to the opened-generic core — generics preserved end-to-end.
    func authorizedRecords(
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        authorizedAs anchor: ModelIdentity? = nil,
        sortedBy sortTerms: [AnySortTerm] = [],
        pagination: Pagination? = nil
    ) async throws -> [any DataModel] {
        guard let provider = application.containerAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        return try await authorizedRecords(
            via: provider, of: container, containing: containedType,
            for: operation, authorizedAs: anchor, sortedBy: sortTerms, pagination: pagination
        )
    }

    /// Grant verdict only — the create door's step-4 twin: update/delete resolve their target
    /// against the loaded candidate set; create has no target, so its door asks exactly the
    /// engine's grant question (same instance-scope filter, same operation×type check, against
    /// the same memoized per-Request authorization set) without loading records or touching the
    /// cache. `false` is indistinguishable from a missing container by design — callers map it
    /// to not-found semantics, never to a distinct "forbidden".
    func holdsAuthorization(
        _ operation: ContainerOperation,
        ofType containedType: any DataModel.Type,
        in container: ModelIdentity
    ) async throws -> Bool {
        guard let provider = application.containerAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        return try await holdsAuthorization(
            via: provider, operation, ofType: containedType, in: container
        )
    }
}

private extension Vapor.Request {
    /// The one memo point: [P.Authorization] is fetched once per Request and reused by every
    /// authorization consumer (record loads AND grant verdicts) — the structural form of the
    /// cache's one-authorization-set contract. Memo box is plainly Sendable
    /// (ContainerAuthorization refines Sendable) — no @unchecked here.
    func memoizedAuthorizations<P: ContainerAuthorizationProvider>(via provider: P) async throws -> [P.Authorization] {
        if let memoized = storage[AuthorizationMemoKey<P>.self] {
            return memoized
        }
        let authorizations = try await provider.containerAuthorizations(for: self)
        storage[AuthorizationMemoKey<P>.self] = authorizations
        return authorizations
    }

    /// THE authorized read path (arch seam invariant #1) — everything that projects reads through
    /// this. ONE call = ONE (container, containedType) set — the unit a projection binds, the sort
    /// vocabulary types against, the window applies to, and the cache key names. Compute-once per
    /// (container, type, operation, refinement) within a Request; cached thereafter (empty results
    /// too). Opened-generic over the app's auth record — no existential arrays cross this seam.
    ///
    /// The authorizations come from the memoized set (fetched once per Request via the provider),
    /// so this is the cache's SOLE writer — the one-authorization-set-per-Request contract is
    /// structural, not a caller obligation.
    ///
    /// Pipeline ORDER is contractual: cache probe → registry lookup (unregistered ⇒ throw —
    /// configuration bug, not data) → find container (missing row ⇒ cached empty — data condition,
    /// indistinguishable from unauthorized by design) → instance-scope → operation×type check →
    /// refined members per matching relation (declaration order) → threshold warn → cache write.
    ///
    /// `authorizedAs` names the identity the grant check runs against — "from where?" bears on
    /// authorization exactly through the anchor: a grant on the ANCHOR authorizes loading members
    /// of a DIFFERENT container reached on the anchored path. `nil` ⇒ the load container. The
    /// anchor joins the cache key: same-anchor calls share one entry; different anchors never merge.
    func authorizedRecords(
        via provider: some ContainerAuthorizationProvider,
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        authorizedAs anchor: ModelIdentity?,
        sortedBy sortTerms: [AnySortTerm],
        pagination: Pagination?
    ) async throws -> [any DataModel] {
        let anchor = anchor ?? container
        // Anchor + pagination-boundary normalization live inside the shared key constructor —
        // the executor's tuple→keys side map reconstructs this exact key from the same inputs.
        let cacheKey = ContainerRecordCacheKey.forLoad(
            of: container,
            containing: containedType,
            for: operation,
            authorizedAs: anchor,
            sortedBy: sortTerms,
            pagination: pagination
        )
        let refinement = cacheKey.refinement
        if let cached = containerRecordCache[cacheKey] {
            return cached
        }

        guard let descriptor = modelTypeRegistry.registered(for: container.namespace) else {
            throw ContainmentError.unregisteredNamespace(identity: String(describing: container))
        }

        guard let containerRecord = try await descriptor.find(container.id, on: db) else {
            containerRecordCache[cacheKey] = []
            return []
        }

        // SECURITY: the grant check runs against the ANCHOR, never the load container — both the
        // instance-scope filter and the operation×type check. Substituting `container` in either
        // silently re-decides "from where?" on the wrong identity.
        let authorizations = try await memoizedAuthorizations(via: provider)
        let scoped = authorizations.filter { $0.authorizedContainer == anchor }
        guard scoped.contains(where: { $0.authorizes(operation, ofType: containedType, in: anchor) }) else {
            containerRecordCache[cacheKey] = []
            return []
        }

        var records = [any DataModel]()
        for relation in descriptor.containment
            where ObjectIdentifier(relation.containedType) == ObjectIdentifier(containedType) {
            try await records += relation.members(of: containerRecord, on: db, applying: refinement)
        }

        let threshold = application.maxRecordsWarningThreshold
        if records.count > threshold {
            logger.warning("Container load returned \(records.count) \(String(describing: containedType)) records from \(String(describing: type(of: containerRecord))) — over maxRecordsWarningThreshold (\(threshold)). The full set was returned; consider paginating this load.")
        }

        containerRecordCache[cacheKey] = records
        return records
    }

    /// Opened-generic verdict: EXACTLY the engine's grant check (instance-scope filter, then the
    /// operation×type check), on the same memoized set — no records, no cache write.
    func holdsAuthorization(
        via provider: some ContainerAuthorizationProvider,
        _ operation: ContainerOperation,
        ofType containedType: any DataModel.Type,
        in container: ModelIdentity
    ) async throws -> Bool {
        try await memoizedAuthorizations(via: provider)
            .filter { $0.authorizedContainer == container }
            .contains { $0.authorizes(operation, ofType: containedType, in: container) }
    }
}

private struct AuthorizationMemoKey<P: ContainerAuthorizationProvider>: StorageKey {
    typealias Value = [P.Authorization]
}
