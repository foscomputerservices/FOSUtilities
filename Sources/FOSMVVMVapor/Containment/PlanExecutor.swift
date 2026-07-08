// PlanExecutor.swift
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

// The request half of C7: bind the boot-derived RecordLoadPlan to THIS request's identities
// and refinement, then descend every tuple through the provider-driven authorized engine so
// each load unit lands in the container-record cache before projection begins.

extension Vapor.Request {
    /// Executes the typed request's boot-derived ``RecordLoadPlan``: binds the roots and the
    /// request refinement from the INSTANCE (its `query`/`sort` properties — the single source
    /// of truth; nothing is re-parsed from the URL), loads every declared tuple through the
    /// authorized engine (results land in ``containerRecordCache``, and each tuple's deposited
    /// keys land in ``tupleCacheKeys``), then runs the ``SupplementalRecordLoading`` hooks.
    ///
    /// A non-composable (legacy) ResponseBody is a no-op. A composable ResponseBody with NO
    /// stored plan throws `ContainmentError.invalidLoadPlan` — registration is Application-only
    /// (`register(request:)`), which always derives the plan, so a missing plan means the request
    /// was never registered, and silently loading nothing would be the misconfiguration's
    /// invisible mode.
    func executeRecordLoadPlan<SR: ServerRequest>(for vmRequest: SR) async throws {
        guard let factory = SR.ResponseBody.self as? any ComposableFactory.Type else {
            return
        }
        guard let plan = application.recordLoadPlan(for: SR.self) else {
            throw ContainmentError.invalidLoadPlan(
                request: String(describing: SR.self),
                reason: "\(String(describing: SR.ResponseBody.self)) is composable but no RecordLoadPlan was derived — register the request on the Application via try app.register(request:), which derives and validates the plan at boot"
            )
        }

        let resolved = try await resolveRecordLoadPlan(plan, for: vmRequest)
        try await resolved.execute(on: self)
        try await runSupplementalLoads(of: factory)
    }

    /// The executor's per-request side map: each executed tuple → the record-level cache keys
    /// its branches deposited, in deposit order. ``ProjectionContext`` snapshots it so a
    /// handle's read returns exactly its own tuple's loaded set — never a same-type sweep
    /// across other tuples' entries.
    var tupleCacheKeys: [RecordLoadPlan.Tuple: [ContainerRecordCacheKey]] {
        get { storage[TupleCacheKeysStore.self] ?? [:] }
        set { storage[TupleCacheKeysStore.self] = newValue }
    }
}

private struct TupleCacheKeysStore: StorageKey {
    typealias Value = [RecordLoadPlan.Tuple: [ContainerRecordCacheKey]]
}

/// A ``RecordLoadPlan`` bound to one request: each root source resolved to an identity and
/// the request's refinement axes bound to the marked tuple. Grants stay per-call — every
/// load goes through the provider-driven engine entry, which memoizes them per Request.
struct ResolvedRecordLoadPlan: Sendable {
    let requestName: String
    let plan: RecordLoadPlan
    let rootIdentities: [RootSource: ModelIdentity]
    let sortTerms: [AnySortTerm]
    let pagination: Pagination?
    let filter: AnyFilter?
}

extension ResolvedRecordLoadPlan {
    /// CONCURRENCY (v1, deliberate): tuples and levels execute SEQUENTIALLY. The engine writes
    /// the container-record cache inside authorizedRecords, and the cache's @unchecked Sendable
    /// contract (ContainerRecordCache.swift) holds only while entries are touched sequentially
    /// within the request's handler task — concurrent engine calls on one Request would race
    /// its read-modify-write. Breadth concurrency per level (TaskGroup + single-writer deposit)
    /// is deferred until the cache gains a concurrent-writer contract; the M2 collapse
    /// optimization (one query per run) will change this calculus anyway.
    /// Loads every tuple: depth-sequential down each path (children need parent identities),
    /// re-anchoring at each `.guards` container instance per branch.
    func execute(on request: Request) async throws {
        for tuple in plan.tuples {
            try await load(tuple, on: request)
        }
    }
}

private extension ResolvedRecordLoadPlan {
    /// One branch of a tuple's descent: the container to load from next, and the identity
    /// its grant checks run against (the nearest `.guards` instance above, else the root).
    typealias Branch = (container: ModelIdentity, anchor: ModelIdentity)

    func load(_ tuple: RecordLoadPlan.Tuple, on request: Request) async throws {
        guard let root = rootIdentities[tuple.root] else {
            throw ContainmentError.invalidLoadPlan(
                request: requestName,
                reason: "tuple rooted at .\(tuple.root) has no bound root identity — resolution invariant breakage; file an issue"
            )
        }

        var branches: [Branch] = [(container: root, anchor: root)]
        for hop in tuple.path {
            let hopType = try dataModelType(of: hop)
            // A `.guards` hop re-anchors each subtree at ITS OWN instance: a guard with N
            // instances anchors each instance's records at that instance, never globally.
            let reanchors = (hop as? any Container.Type)?.authorityFlow == .guards
            var next = [Branch]()
            for branch in branches {
                let parents = try await request.authorizedRecords(
                    of: branch.container,
                    containing: hopType,
                    for: tuple.operation,
                    authorizedAs: branch.anchor
                )
                for parent in parents {
                    let identity = try parent.modelIdentity
                    next.append((container: identity, anchor: reanchors ? identity : branch.anchor))
                }
            }
            branches = next
        }

        let recordType = try dataModelType(of: tuple.recordType)
        var depositedKeys = [ContainerRecordCacheKey]()
        for branch in branches {
            let sortedBy = tuple.isRefinedByRequest ? sortTerms : []
            let paginatedBy = tuple.isRefinedByRequest ? pagination : nil
            let filteredBy = tuple.isRefinedByRequest ? filter : nil
            _ = try await request.authorizedRecords(
                of: branch.container,
                containing: recordType,
                for: tuple.operation,
                authorizedAs: branch.anchor,
                sortedBy: sortedBy,
                pagination: paginatedBy,
                filter: filteredBy
            )
            // Same inputs → the same key the engine just deposited (shared constructor —
            // ContainerRecordCacheKey.forLoad — is the no-drift guarantee).
            depositedKeys.append(.forLoad(
                of: branch.container,
                containing: recordType,
                for: tuple.operation,
                authorizedAs: branch.anchor,
                sortedBy: sortedBy,
                pagination: paginatedBy,
                filter: filteredBy
            ))
        }
        request.tupleCacheKeys[tuple] = depositedKeys
    }

    /// Backstop, not a code path: boot hop-resolution only registers server DataModels, so a
    /// plan hop that is not one means framework-invariant breakage.
    func dataModelType(of modelType: any FOSMVVM.Model.Type) throws -> any DataModel.Type {
        guard let dataModelType = modelType as? any DataModel.Type else {
            throw ContainmentError.invalidLoadPlan(
                request: requestName,
                reason: "\(String(describing: modelType)) is not a server DataModel — framework-invariant breakage; file an issue"
            )
        }
        return dataModelType
    }
}

// MARK: - Binding (RecordLoadPlan → ResolvedRecordLoadPlan)

/// Internal (not private): the write route (WriteRoute.swift) resolves + executes the candidate
/// plan through this same binding, so a write's candidate load and a read's plan load share one
/// resolution path.
extension Vapor.Request {
    /// Binding reads the TYPED INSTANCE's `query`/`sort` properties — the middleware (or a
    /// programmatic caller, e.g. a write route's refresh) bound them; the executor never
    /// re-parses the URL, so the instance is the single source of truth.
    func resolveRecordLoadPlan<SR: ServerRequest>(
        _ plan: RecordLoadPlan,
        for vmRequest: SR
    ) async throws -> ResolvedRecordLoadPlan {
        let requestName = String(describing: SR.self)
        let query = vmRequest.query

        var rootIdentities = [RootSource: ModelIdentity]()
        for source in Set(plan.tuples.map(\.root)) {
            let identity: ModelIdentity
            switch source {
            case .query:
                // Boot validated the TYPE conformance (RootedQuery); only the instance can
                // be missing here — a malformed request, not a configuration error.
                guard let rooted = query.flatMap({ $0 as? any RootedQuery }) else {
                    throw Abort(.badRequest, reason: "\(requestName) requires a \(String(describing: SR.Query.self)) query to vend its root identity")
                }
                identity = rooted.rootIdentity
            case .apex:
                guard let resolver = application.apexContainerResolver else {
                    throw ContainmentError.invalidLoadPlan(
                        request: requestName,
                        reason: "the plan has .apex-rooted loads but no apex container resolver is registered — register one in configure(_:) via useApexContainerResolver(_:)"
                    )
                }
                identity = try await resolver.resolve(self)
            }
            try verifyRootContainment(of: identity, boundTo: source, in: plan, request: requestName)
            rootIdentities[source] = identity
        }

        // The request's axes bind to the ONE marked tuple; without a mark they apply nowhere.
        var sortTerms = [AnySortTerm]()
        var pagination: Pagination?
        var filter: AnyFilter?
        if plan.tuples.contains(where: \.isRefinedByRequest) {
            if let erasing = vmRequest.sort.flatMap({ $0 as? any ErasedSortTermsProviding }) {
                sortTerms = erasing.erasedSortTerms
            }
            pagination = query.flatMap { $0 as? any PaginatedQuery }?.pagination
            // The query IS the filter — a FilterableDataModel at the marked tuple reads it as a WHERE.
            filter = query.map(AnyFilter.init)
        }

        return ResolvedRecordLoadPlan(
            requestName: requestName,
            plan: plan,
            rootIdentities: rootIdentities,
            sortTerms: sortTerms,
            pagination: pagination,
            filter: filter
        )
    }

    /// The root-edge check boot deliberately could not run (roots bind to identities only at
    /// request time): the bound root's registered descriptor must declare containment of each
    /// of its tuples' first hops — a misrooted query is a typed error, never a silent empty.
    func verifyRootContainment(
        of root: ModelIdentity,
        boundTo source: RootSource,
        in plan: RecordLoadPlan,
        request: String
    ) throws {
        guard let descriptor = modelTypeRegistry.registered(for: root.namespace) else {
            throw ContainmentError.unregisteredNamespace(identity: String(describing: root))
        }
        for tuple in plan.tuples where tuple.root == source {
            let firstHop = tuple.path.first ?? tuple.recordType
            guard descriptor.containment.contains(where: { ObjectIdentifier($0.containedType) == ObjectIdentifier(firstHop) }) else {
                throw ContainmentError.invalidLoadPlan(
                    request: request,
                    reason: "the .\(source) root resolved to \(descriptor.typeName), which declares no containment of \(String(describing: firstHop)) — the bound root identity does not match the plan's declared path"
                )
            }
        }
    }
}

// MARK: - Refinement bridge

/// Internal bridge opening a request's typed `SortCriteria<Key>` to the engine's erased terms
/// without naming `Key` — the executor sees only `any ServerRequestSort`. Internal (not private):
/// the boot Sort-bridge warn (PlanRegistration.swift) probes this same conformance to detect a
/// request `Sort` that contributes zero terms.
protocol ErasedSortTermsProviding {
    var erasedSortTerms: [AnySortTerm] { get }
}

extension SortCriteria: ErasedSortTermsProviding {
    var erasedSortTerms: [AnySortTerm] {
        erasedTerms
    }
}

// MARK: - Supplemental loads (runner; the public ``SupplementalRecordLoading`` surface is C8's)

private extension Vapor.Request {
    /// Runs every conformer's hook over the composition graph: it shares the walk's pre-order /
    /// declaration order, so hooks fire deterministically. The global once-per-factory dedup is the
    /// runner's own (a factory reached on two paths runs its hook once), not a property inherited
    /// from the plan walk.
    func runSupplementalLoads(of factory: any ComposableFactory.Type) async throws {
        var visited = Set<ObjectIdentifier>()
        var conformers = [any SupplementalRecordLoading.Type]()
        collectSupplementalLoaders(from: factory, visited: &visited, into: &conformers)
        for conformer in conformers {
            try await conformer.loadSupplementalRecords(for: self)
        }
    }

    func collectSupplementalLoaders(
        from factory: any ComposableFactory.Type,
        visited: inout Set<ObjectIdentifier>,
        into conformers: inout [any SupplementalRecordLoading.Type]
    ) {
        guard visited.insert(ObjectIdentifier(factory)).inserted else {
            return
        }
        if let conformer = factory as? any SupplementalRecordLoading.Type {
            conformers.append(conformer)
        }
        for child in factory.children {
            collectSupplementalLoaders(from: child.factoryType, visited: &visited, into: &conformers)
        }
    }
}
