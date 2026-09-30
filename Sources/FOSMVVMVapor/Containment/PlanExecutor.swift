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
    /// Executes the typed request's boot-derived ``RecordLoadPlan``: binds the scopes and the
    /// request refinement from the INSTANCE (its `query`/`sort` properties — the single source
    /// of truth; nothing is re-parsed from the URL), loads every declared tuple through the
    /// authorized engine (results land in ``containerRecordCache``, and each tuple's deposited
    /// keys land in ``tupleCacheKeys``), then runs the ``SupplementalRecordLoading`` hooks.
    ///
    /// A non-composable (legacy) ResponseBody is a no-op. A composable ResponseBody with NO
    /// stored plan throws `ContainmentError.invalidLoadPlan` — registration
    /// (`register(request:app:)`) always derives the plan, so a missing plan means the request
    /// was never registered, and silently loading nothing would be the misconfiguration's
    /// invisible mode.
    func executeRecordLoadPlan<SR: ServerRequest>(for vmRequest: SR) async throws {
        guard let factory = SR.ResponseBody.self as? any ComposableFactory.Type else {
            return
        }
        guard let plan = application.recordLoadPlan(for: SR.self) else {
            throw ContainmentError.invalidLoadPlan(
                request: String(describing: SR.self),
                reason: "\(String(describing: SR.ResponseBody.self)) is composable but no RecordLoadPlan was derived — register the request via try app.register(request: SR.self, app: app), which derives and validates the plan at boot"
            )
        }

        let resolved = try await resolveRecordLoadPlan(plan, for: vmRequest)
        try await resolved.execute(on: self)
        depositRegistrationSet(from: resolved)
        try await runSupplementalLoads(of: factory)
    }

    /// The executed plan's staleness surface — ``touchedContainers(of:)`` — deposited for
    /// ``ServerRequestBody/buildResponse(_:)`` to attach as the `X-FOS-Registrations` header.
    /// Derived from the executed plan's tuples only (spec §3.4): containers touched solely by a
    /// SupplementalRecordLoading hook are outside the v1 registration surface.
    private func depositRegistrationSet(from resolved: ResolvedRecordLoadPlan) {
        let identities = touchedContainers(of: resolved)
        let threshold = application.maxRegistrationsWarningThreshold
        if identities.count > threshold {
            logger.warning("\(resolved.requestName) registers \(identities.count) identities for live refresh — over maxRegistrationsWarningThreshold (\(threshold)). Every identity was registered; a load within the subject scope registers one per bound model, so consider narrowing the plan or paginating it.")
        }
        registrationSet = identities
    }

    /// The identities an executed plan touched: every scope's bound identities (one per named
    /// scope; one per bound model within the subject scope, plus the subject itself when the
    /// provider vends it) and every container its tuples' cache keys name. The ONE traversal
    /// behind both the read path's registration set (`depositRegistrationSet`) and the write
    /// path's cache invalidation (`invalidateWrittenContainers`, WriteRoute.swift) — the
    /// live-invalidation contract holds only while a client registers on exactly what a write
    /// invalidates, so neither site may re-derive this shape on its own.
    func touchedContainers(of resolved: ResolvedRecordLoadPlan) -> Set<ModelIdentity> {
        var identities = Set(resolved.rootIdentities.values)
        for bound in resolved.subjectBindings.values {
            identities.formUnion(bound)
        }
        if let subject = resolved.subjectIdentity {
            identities.insert(subject)
        }
        for tuple in resolved.plan.tuples {
            for key in tupleCacheKeys[tuple] ?? [] {
                // A subject-scope key names no container: its rows are the bound identities above.
                if case .container(let key) = key {
                    identities.insert(key.container)
                }
            }
        }
        return identities
    }

    /// The registration set the executor deposited for this served response (empty when no plan
    /// executed). ``ServerRequestBody/buildResponse(_:)`` reads it to attach `X-FOS-Registrations`.
    var registrationSet: Set<ModelIdentity> {
        get { storage[RegistrationSetStore.self] ?? [] }
        set { storage[RegistrationSetStore.self] = newValue }
    }

    /// The executor's per-request side map: each executed tuple → the record-level cache keys
    /// its branches deposited, in deposit order. ``ProjectionContext`` snapshots it so a
    /// handle's read returns exactly its own tuple's loaded set — never a same-type sweep
    /// across other tuples' entries.
    var tupleCacheKeys: [RecordLoadPlan.Tuple: [RecordCacheKey]] {
        get { storage[TupleCacheKeysStore.self] ?? [:] }
        set { storage[TupleCacheKeysStore.self] = newValue }
    }
}

private struct TupleCacheKeysStore: StorageKey {
    typealias Value = [RecordLoadPlan.Tuple: [RecordCacheKey]]
}

private struct RegistrationSetStore: StorageKey {
    typealias Value = Set<ModelIdentity>
}

/// A ``RecordLoadPlan`` bound to one request: each named scope resolved to an identity, each
/// subject-scoped tuple bound to the models its first type's grants reach, and the request's
/// refinement axes bound to the marked tuple. Grants stay per-call — every load goes through
/// the provider-driven engine entry, which memoizes them per Request.
struct ResolvedRecordLoadPlan: Sendable {
    let requestName: String
    let plan: RecordLoadPlan
    /// `.request` and `.application` bind one identity each.
    let rootIdentities: [ContainmentScope: ModelIdentity]
    /// `.subject` binds PER TUPLE, not per scope: two subject-scoped tuples with different first
    /// types bind different sets (the Workspaces this subject may read; the SystemStatuses it may
    /// read), so the scope alone names no set. In query order, distinct by identity.
    let subjectBindings: [RecordLoadPlan.Tuple: [ModelIdentity]]
    /// The provider's identity for the subject, when any tuple is within the subject scope and
    /// the provider vends one; registered so a grant write refreshes the subject's lists.
    let subjectIdentity: ModelIdentity?
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
        var branches: [Branch]
        var hops: ArraySlice<any FOSMVVM.Model.Type>
        switch tuple.root {
        case .subject:
            guard let bound = subjectBindings[tuple] else {
                throw ContainmentError.invalidLoadPlan(
                    request: requestName,
                    reason: "tuple within the .subject scope has no bound model set — resolution invariant breakage; file an issue"
                )
            }
            if tuple.path.isEmpty {
                // The bound rows ARE the records: the binding's one refined query already deposited
                // them under the subject key (a cache hit here); the tuple just names that key.
                let key = try await request.loadSubjectScope(of: tuple, request: requestName, sortedBy: sortTerms, pagination: pagination, filter: filter)
                request.tupleCacheKeys[tuple] = [.subject(key)]
                return
            }
            // Each bound model of the first type is its own root and anchors its own subtree —
            // exactly what a `.request` root does, one branch per bound identity. The remaining
            // hops descend through ordinary containment, re-anchoring at `.guards` as below.
            branches = bound.map { (container: $0, anchor: $0) }
            hops = tuple.path.dropFirst()
        case .request, .application, .parent:
            guard let root = rootIdentities[tuple.root] else {
                throw ContainmentError.invalidLoadPlan(
                    request: requestName,
                    reason: "tuple within the .\(tuple.root) scope has no bound container identity — resolution invariant breakage; file an issue"
                )
            }
            branches = [(container: root, anchor: root)]
            hops = tuple.path[...]
        }

        for hop in hops {
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
        var depositedKeys = [RecordCacheKey]()
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
            depositedKeys.append(.container(.forLoad(
                of: branch.container,
                containing: recordType,
                for: tuple.operation,
                authorizedAs: branch.anchor,
                sortedBy: sortedBy,
                pagination: paginatedBy,
                filter: filteredBy
            )))
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

        // The request's axes bind to the ONE marked tuple; without a mark they apply nowhere.
        // Bound first: a refined tuple within the subject scope binds through its refined query.
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

        var rootIdentities = [ContainmentScope: ModelIdentity]()
        for scope in Set(plan.tuples.map(\.root)) {
            let identity: ModelIdentity
            switch scope {
            case .request:
                // Boot validated the TYPE conformance (ScopedQuery); only the instance can
                // be missing here — a malformed request, not a configuration error.
                guard let scoped = query.flatMap({ $0 as? any ScopedQuery }) else {
                    throw Abort(.badRequest, reason: "\(requestName) requires a \(String(describing: SR.Query.self)) query to name its container")
                }
                identity = scoped.scopeIdentity
            case .application:
                guard let applicationScope = application.resolvedApplicationScope else {
                    throw ContainmentError.invalidLoadPlan(
                        request: requestName,
                        reason: "the plan has loads within the application scope but none is registered — register one in configure(_:) via useApplicationScope(_:), or register exactly one SystemContainer"
                    )
                }
                identity = try await applicationScope.resolve(self)
            case .subject:
                continue // bound per tuple below
            case .parent:
                // The walk resolves every `.parent` declaration to the scope its composition
                // chain opened, so no tuple reaches the executor within `.parent`.
                throw ContainmentError.invalidLoadPlan(
                    request: requestName,
                    reason: "a tuple reached the executor within the .parent scope, which the walk always resolves — framework-invariant breakage; file an issue"
                )
            }
            try verifyRootContainment(of: identity, boundTo: scope, in: plan, request: requestName)
            rootIdentities[scope] = identity
        }

        // The subject scope binds per tuple: its first type's one refined query runs here and its
        // rows are the bound set (the load re-reads the same cache entry). No root-containment
        // check: every row is of the first type by construction, and boot (resolveHops) already
        // validated the chain from that type down.
        var subjectBindings = [RecordLoadPlan.Tuple: [ModelIdentity]]()
        var subjectIdentity: ModelIdentity?
        let subjectTuples = plan.tuples.filter { $0.root == .subject }
        if !subjectTuples.isEmpty {
            subjectIdentity = try await self.subjectIdentity()
            for tuple in subjectTuples {
                let key = try await loadSubjectScope(of: tuple, request: requestName, sortedBy: sortTerms, pagination: pagination, filter: filter)
                var seen = Set<ModelIdentity>()
                subjectBindings[tuple] = try (subjectScopeCache[key] ?? []).compactMap { row in
                    let identity = try row.modelIdentity
                    return seen.insert(identity).inserted ? identity : nil
                }
            }
        }

        return ResolvedRecordLoadPlan(
            requestName: requestName,
            plan: plan,
            rootIdentities: rootIdentities,
            subjectBindings: subjectBindings,
            subjectIdentity: subjectIdentity,
            sortTerms: sortTerms,
            pagination: pagination,
            filter: filter
        )
    }

    /// The subject scope's one query for a tuple's FIRST type: refined by the request only when
    /// the first type is also the record type (no `via:`) and the tuple carries the mark — a
    /// refinement never applies to an intermediate level. Returns the key the engine deposited
    /// under (shared constructor — SubjectScopeCacheKey.forLoad — is the no-drift guarantee).
    func loadSubjectScope(
        of tuple: RecordLoadPlan.Tuple,
        request requestName: String,
        sortedBy sortTerms: [AnySortTerm],
        pagination: Pagination?,
        filter: AnyFilter?
    ) async throws -> SubjectScopeCacheKey {
        guard let firstType = (tuple.path.first ?? tuple.recordType) as? any DataModel.Type else {
            throw ContainmentError.invalidLoadPlan(
                request: requestName,
                reason: "\(String(describing: tuple.path.first ?? tuple.recordType)) is not a server DataModel — framework-invariant breakage; file an issue"
            )
        }
        let refined = tuple.path.isEmpty && tuple.isRefinedByRequest
        let sortedBy = refined ? sortTerms : []
        let paginatedBy = refined ? pagination : nil
        let filteredBy = refined ? filter : nil
        _ = try await authorizedModels(
            ofType: firstType,
            for: tuple.operation,
            sortedBy: sortedBy,
            pagination: paginatedBy,
            filter: filteredBy
        )
        return .forLoad(ofType: firstType, for: tuple.operation, sortedBy: sortedBy, pagination: paginatedBy, filter: filteredBy)
    }

    /// The scope-edge check boot deliberately could not run (a scope binds to an identity only
    /// at request time): the bound container's registered descriptor must declare containment of
    /// each of its tuples' first hops — a mis-scoped query is a typed error, never a silent empty.
    func verifyRootContainment(
        of root: ModelIdentity,
        boundTo scope: ContainmentScope,
        in plan: RecordLoadPlan,
        request: String
    ) throws {
        guard let descriptor = modelTypeRegistry.registered(for: root.namespace) else {
            throw ContainmentError.unregisteredNamespace(identity: String(describing: root))
        }
        for tuple in plan.tuples where tuple.root == scope {
            let firstHop = tuple.path.first ?? tuple.recordType
            guard descriptor.containment.contains(where: { ObjectIdentifier($0.containedType) == ObjectIdentifier(firstHop) }) else {
                throw ContainmentError.invalidLoadPlan(
                    request: request,
                    reason: "the .\(scope) scope resolved to \(descriptor.typeName), which declares no containment of \(String(describing: firstHop)) — the bound container identity does not match the plan's declared path"
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
