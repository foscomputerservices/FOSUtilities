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
import FOSFoundation
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
        pagination: Pagination? = nil,
        filter: AnyFilter? = nil
    ) async throws -> [any DataModel] {
        guard let provider = application.modelAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        return try await authorizedRecords(
            via: provider, of: container, containing: containedType,
            for: operation, authorizedAs: anchor, sortedBy: sortTerms, pagination: pagination, filter: filter
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
        guard let provider = application.modelAuthorizationProvider else {
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
    /// (ModelAuthorization refines Sendable) — no @unchecked here.
    func memoizedAuthorizations<P: ModelAuthorizationProvider>(via provider: P) async throws -> [P.Authorization] {
        if let memoized = storage[AuthorizationMemoKey<P>.self] {
            return memoized
        }
        let authorizations = try await provider.modelAuthorizations(for: self)
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
        via provider: some ModelAuthorizationProvider,
        of container: ModelIdentity,
        containing containedType: any DataModel.Type,
        for operation: ContainerOperation,
        authorizedAs anchor: ModelIdentity?,
        sortedBy sortTerms: [AnySortTerm],
        pagination: Pagination?,
        filter: AnyFilter?
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
            pagination: pagination,
            filter: filter
        )
        let refinement = cacheKey.refinement
        if let cached = containerRecordCache[cacheKey] {
            return cached
        }

        guard let descriptor = modelTypeRegistry.registered(for: container.namespace) else {
            throw ContainmentError.unregisteredNamespace(identity: String(describing: container))
        }

        // A system container has no row: its `.all` relations take no container. A stored
        // container whose row is gone loads empty — a data condition, cached like any other.
        let containerRecord: (any DataModel)?
        if descriptor.isTableless {
            containerRecord = nil
        } else {
            guard let found = try await descriptor.find(container.id, on: db) else {
                containerRecordCache[cacheKey] = []
                return []
            }
            containerRecord = found
        }

        // SECURITY: the grant check runs against the ANCHOR, never the load container — both the
        // instance-scope filter and the operation×type check. Substituting `container` in either
        // silently re-decides "from where?" on the wrong identity.
        let authorizations = try await memoizedAuthorizations(via: provider)
        let scoped = authorizations.filter { $0.authorizedModel == anchor }
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
            logger.warning("Container load returned \(records.count) \(String(describing: containedType)) records from \(descriptor.typeName) — over maxRecordsWarningThreshold (\(threshold)). The full set was returned; consider paginating this load.")
        }

        // Total the window is a view into: only when a window is present (an unpaginated load's
        // total IS records.count — no query needed). Applies the refinement's FILTER (via the
        // refined memberCount) so the total is the FILTERED set size the window slices, never the
        // whole-set size. Runs inside the authorized path, after the grant check above, so it never
        // counts rows the caller cannot see. Mirrors the records loop's relation match.
        if refinement.pagination != nil {
            var total = 0
            for relation in descriptor.containment
                where ObjectIdentifier(relation.containedType) == ObjectIdentifier(containedType) {
                total += try await relation.memberCount(of: containerRecord, on: db, applying: refinement)
            }
            containerRecordCountCache[cacheKey] = total
        }

        containerRecordCache[cacheKey] = records
        return records
    }

    /// Opened-generic verdict: EXACTLY the engine's grant check (instance-scope filter, then the
    /// operation×type check), on the same memoized set — no records, no cache write.
    func holdsAuthorization(
        via provider: some ModelAuthorizationProvider,
        _ operation: ContainerOperation,
        ofType containedType: any DataModel.Type,
        in container: ModelIdentity
    ) async throws -> Bool {
        try await memoizedAuthorizations(via: provider)
            .filter { $0.authorizedModel == container }
            .contains { $0.authorizes(operation, ofType: containedType, in: container) }
    }
}

private struct AuthorizationMemoKey<P: ModelAuthorizationProvider>: StorageKey {
    typealias Value = [P.Authorization]
}

// MARK: - The subject's identity

extension Vapor.Request {
    /// The identity the provider vends for this request's subject, asked ONCE per Request and
    /// memoized beside the grants (`nil` when the provider vends none). Every load within the
    /// subject scope registers it, so a grant write reaches the subject's live lists.
    func subjectIdentity() async throws -> ModelIdentity? {
        guard let provider = application.modelAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        if let memoized = storage[SubjectIdentityMemoKey.self] {
            return memoized.identity
        }
        let identity = try await provider.subjectIdentity(for: self)
        storage[SubjectIdentityMemoKey.self] = SubjectIdentityMemo(identity: identity)
        return identity
    }
}

/// Boxed so "asked, and the answer was nil" is distinguishable from "never asked".
private struct SubjectIdentityMemo: Sendable {
    let identity: ModelIdentity?
}

private struct SubjectIdentityMemoKey: StorageKey {
    typealias Value = SubjectIdentityMemo
}

// MARK: - The subject scope

extension Vapor.Request {
    /// The models of `type` the subject may `operation`, within the subject scope: every model a
    /// grant names with the matching ``ModelOperation``, plus every member of a granted container
    /// that directly contains the type. Ids are gathered from the memoized grants (one member-id
    /// query per relation that reaches the type), then the rows load ONCE with the request's
    /// refinement, so paging across the union is exact. Cached per request like every load.
    func authorizedModels(
        ofType type: any DataModel.Type,
        for operation: ContainerOperation,
        sortedBy sortTerms: [AnySortTerm] = [],
        pagination: Pagination? = nil,
        filter: AnyFilter? = nil
    ) async throws -> [any DataModel] {
        guard let provider = application.modelAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        return try await authorizedModels(
            via: provider, ofType: type, for: operation,
            refinement: .normalized(sortTerms: sortTerms, pagination: pagination, filter: filter)
        )
    }

    /// The paginated total behind the last ``authorizedModels(ofType:for:sortedBy:pagination:filter:)``
    /// with these inputs, or `nil` when that load carried no window.
    func authorizedModelCount(
        ofType type: any DataModel.Type,
        for operation: ContainerOperation,
        sortedBy sortTerms: [AnySortTerm] = [],
        pagination: Pagination? = nil,
        filter: AnyFilter? = nil
    ) -> Int? {
        subjectScopeCountCache[SubjectScopeCacheKey(
            containedType: ObjectIdentifier(type),
            operation: operation,
            refinement: .normalized(sortTerms: sortTerms, pagination: pagination, filter: filter)
        )]
    }
}

private extension Vapor.Request {
    func authorizedModels(
        via provider: some ModelAuthorizationProvider,
        ofType type: any DataModel.Type,
        for operation: ContainerOperation,
        refinement: ContainmentQueryRefinement
    ) async throws -> [any DataModel] {
        let key = SubjectScopeCacheKey(containedType: ObjectIdentifier(type), operation: operation, refinement: refinement)
        // The executor reconstructs this key through SubjectScopeCacheKey.forLoad from the same
        // inputs; `refinement` arrived already normalized through it.
        if let cached = subjectScopeCache[key] {
            return cached
        }
        guard let descriptor = modelTypeRegistry.registered(for: type.modelIdentityNamespace) else {
            throw ContainmentError.unregisteredNamespace(identity: String(describing: type))
        }

        let records: [any DataModel]
        switch try await subjectReach(via: provider, ofType: type, for: operation) {
        case .everyModel:
            records = try await descriptor.records(applying: refinement, on: db)
            if refinement.pagination != nil {
                subjectScopeCountCache[key] = try await descriptor.recordCount(filter: refinement.filter, on: db)
            }
        case .models(let ids) where ids.isEmpty:
            subjectScopeCache[key] = []
            return []
        case .models(let ids):
            let orderedIds = Array(ids)
            records = try await descriptor.records(withIds: orderedIds, applying: refinement, on: db)
            if refinement.pagination != nil {
                subjectScopeCountCache[key] = try await descriptor.recordCount(withIds: orderedIds, filter: refinement.filter, on: db)
            }
        }

        let threshold = application.maxRecordsWarningThreshold
        if records.count > threshold {
            logger.warning("Subject-scope load returned \(records.count) \(String(describing: type)) records — over maxRecordsWarningThreshold (\(threshold)). The full set was returned; consider paginating this load.")
        }

        subjectScopeCache[key] = records
        return records
    }

    /// The union of the two authorities, one hop deep: models a grant names with the operation's
    /// model-level twin, and members of granted containers whose registered containment declares
    /// the type and whose grant extends the operation to it. A granted container that reaches the
    /// whole type (a system container's `.all`) makes the reach every model, and no ids are gathered.
    func subjectReach(
        via provider: some ModelAuthorizationProvider,
        ofType type: any DataModel.Type,
        for operation: ContainerOperation
    ) async throws -> SubjectReach {
        let grants = try await memoizedAuthorizations(via: provider)
        let namespace = type.modelIdentityNamespace
        var ids = Set<ModelIdType>()

        if let modelOperation = operation.modelOperation {
            for grant in grants
                where grant.authorizedModel.namespace == namespace
                && grant.authorizes(modelOperation, on: grant.authorizedModel) {
                ids.insert(grant.authorizedModel.id)
            }
        }

        var grantedContainers = [ModelNamespace: [ModelIdType]]()
        for grant in grants {
            let container = grant.authorizedModel
            guard let descriptor = modelTypeRegistry.registered(for: container.namespace),
                  descriptor.isContainer,
                  descriptor.containment.contains(where: { ObjectIdentifier($0.containedType) == ObjectIdentifier(type) }),
                  grant.authorizes(operation, ofType: type, in: container) else {
                continue
            }
            grantedContainers[container.namespace, default: []].append(container.id)
        }
        for (containerNamespace, containerIds) in grantedContainers {
            guard let descriptor = modelTypeRegistry.registered(for: containerNamespace) else { continue }
            for relation in descriptor.containment
                where ObjectIdentifier(relation.containedType) == ObjectIdentifier(type) {
                if relation.reachesWholeType {
                    return .everyModel
                }
                try await ids.formUnion(relation.memberIds(ofContainers: containerIds, on: db))
            }
        }
        return .models(ids)
    }
}

/// What the subject's grants reach within one type.
enum SubjectReach: Equatable {
    /// The named models and the direct members of granted containers, by id.
    case models(Set<ModelIdType>)
    /// Every row of the type: a granted system container owns it.
    case everyModel
}

extension Vapor.Request {
    /// The reach behind ``authorizedModels(ofType:for:sortedBy:pagination:filter:)``, before any
    /// row loads — the engine's decision between an id list and the whole type.
    func subjectReach(ofType type: any DataModel.Type, for operation: ContainerOperation) async throws -> SubjectReach {
        guard let provider = application.modelAuthorizationProvider else {
            throw ContainmentError.noAuthorizationProvider
        }
        return try await subjectReach(via: provider, ofType: type, for: operation)
    }
}
