// PlanRegistration.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

// The boot half of C7: derive each composable request type's RecordLoadPlan ONCE at route
// registration and validate it against the app's registered containment, so misdeclarations
// surface at boot — never at request time. The request INSTANCE only parameterizes resolution.

extension Application {
    /// Derives, validates, and stores `Request`'s ``RecordLoadPlan`` — a no-op when
    /// `Request.ResponseBody` does not opt into ``ComposableFactory``
    /// (legacy requests derive no plan).
    ///
    /// Boot fail-fasts (typed): composition cycles and duplicate `.refinedByRequest` marks
    /// (`RecordLoadPlan.WalkError`); all-empty conformers, unresolvable containment hops,
    /// `.query` roots without a `RootedQuery`, and `.apex` roots without a registered
    /// resolver (`ContainmentError.invalidLoadPlan`). Dead `.refinedByRequest` markers and
    /// `.guards` containers bypassed by every declared path only warn.
    func registerRecordLoadPlan<Request: ServerRequest>(for _: Request.Type) throws {
        // Conditional conformances surface through this runtime metatype cast too —
        // the trait is detected on the concrete ResponseBody type, however it conforms.
        guard let factory = Request.ResponseBody.self as? any ComposableFactory.Type else {
            return
        }

        // Cycle + multiple-.refinedByRequest fail-fasts surface from the walk itself.
        let plan = try RecordLoadPlan.walk(from: factory)
        let requestName = String(describing: Request.self)

        try rejectAllEmptyConformers(from: factory, request: requestName) // safe: walk proved acyclic
        try assertStableRequirementTokens(from: factory, request: requestName) // safe: walk proved acyclic
        try resolveHops(of: plan, request: requestName)
        try requireRootBindings(of: plan, for: Request.self)
        warnOnDeadRefinementMarker(in: plan, for: Request.self)
        warnOnForeignSortBridge(in: plan, for: Request.self)
        warnOnBypassedGuards(in: plan, request: requestName)

        var plans = storage[RecordLoadPlanStorageKey.self] ?? [:]
        plans[ObjectIdentifier(Request.self)] = plan
        storage[RecordLoadPlanStorageKey.self] = plans
    }

    /// The stored plan for a request type. `nil` means EITHER the ResponseBody is
    /// non-composable (legacy — expected, correct) OR the request was never registered.
    /// Registration is Application-only (`register(request:)`) and always derives a composable
    /// body's plan, so a composable body reaching the executor with no stored plan is a
    /// never-registered configuration error: the executor throws typed
    /// (`ContainmentError.invalidLoadPlan`) rather than silently loading nothing.
    func recordLoadPlan<Request: ServerRequest>(for _: Request.Type) -> RecordLoadPlan? {
        storage[RecordLoadPlanStorageKey.self]?[ObjectIdentifier(Request.self)]
    }
}

// MARK: - Boot checks

private extension Application {
    /// Every factory in the graph must declare its `dataRequirements` as stored `static let`s: a
    /// computed property mints a fresh declaration identity on each access, which silently breaks
    /// the handle→tuple resolution a projection reads back through. Lint it at boot.
    func assertStableRequirementTokens(
        from factory: any ComposableFactory.Type,
        request: String
    ) throws {
        guard RecordLoadPlan.requirementTokensAreStable(for: factory) else {
            throw ContainmentError.unstableRequirementTokens(
                request: request,
                handle: "\(String(describing: factory)).dataRequirements"
            )
        }
        for child in factory.children {
            try assertStableRequirementTokens(from: child.factoryType, request: request)
        }
    }

    /// A conformance declaring neither requirements nor children is meaningless — each
    /// default is meaningful only against the other (pure composer / leaf).
    func rejectAllEmptyConformers(
        from factory: any ComposableFactory.Type,
        request: String
    ) throws {
        if factory.dataRequirements.isEmpty, factory.children.isEmpty {
            throw ContainmentError.invalidLoadPlan(
                request: request,
                reason: "\(String(describing: factory)) conforms to ComposableFactory but declares neither dataRequirements nor children — declare the factory's data or drop the conformance"
            )
        }
        for child in factory.children {
            try rejectAllEmptyConformers(from: child.factoryType, request: request)
        }
    }

    /// Every consecutive hop pair — and the terminal hop to the record type — must resolve
    /// to a registered ContainmentRelation (C4 invariant (a), generalized to declared paths).
    func resolveHops(of plan: RecordLoadPlan, request: String) throws {
        // The root→first-hop edge is deliberately NOT validated HERE: a root binds to an
        // IDENTITY at request time (.query — the RootedQuery's value; .apex — the resolver's),
        // so its container TYPE is unknown at boot. That edge fail-fasts on first load instead:
        // ContainmentError.unregisteredNamespace when the root identity's namespace was never
        // registered, else Request.verifyRootContainment (PlanExecutor.swift) throws
        // ContainmentError.invalidLoadPlan when the bound root's registered descriptor declares
        // no containment of the tuple's first hop. No silent-empty mode remains on this edge.
        for tuple in plan.tuples {
            let chain: [any FOSMVVM.Model.Type] = tuple.path + [tuple.recordType]
            for index in chain.indices.dropLast() {
                let container = chain[index]
                let next = chain[index + 1]
                guard let descriptor = modelTypeRegistry.registered(for: container.modelIdentityNamespace) else {
                    throw ContainmentError.invalidLoadPlan(
                        request: request,
                        reason: "hop container \(String(describing: container)) is not a registered container — register it in configure(_:) via register(_:migration:)"
                    )
                }
                guard descriptor.containment.contains(where: { ObjectIdentifier($0.containedType) == ObjectIdentifier(next) }) else {
                    throw ContainmentError.invalidLoadPlan(
                        request: request,
                        reason: "\(descriptor.typeName) declares no containment of \(String(describing: next)) — fix the declared path or the container's containment"
                    )
                }
            }
        }
    }

    /// `.query` roots need the request type to vend the root (``RootedQuery``); `.apex`
    /// roots need the application to resolve it (``useApexContainerResolver(_:)``).
    func requireRootBindings<Request: ServerRequest>(
        of plan: RecordLoadPlan,
        for _: Request.Type
    ) throws {
        let requestName = String(describing: Request.self)
        if plan.tuples.contains(where: { $0.root == .query }),
           !(Request.Query.self is any RootedQuery.Type) {
            throw ContainmentError.invalidLoadPlan(
                request: requestName,
                reason: "the plan has .query-rooted loads but \(String(describing: Request.Query.self)) does not conform to RootedQuery — the request's query must vend the root identity"
            )
        }
        if plan.tuples.contains(where: { $0.root == .apex }), apexContainerResolver == nil {
            throw ContainmentError.invalidLoadPlan(
                request: requestName,
                reason: "the plan has .apex-rooted loads but no apex container resolver is registered — register one in configure(_:) via useApexContainerResolver(_:)"
            )
        }
    }

    /// `.refinedByRequest` on a request type that declares no axes refines nothing —
    /// warn, don't throw: the marker is harmless until an axis arrives.
    func warnOnDeadRefinementMarker<Request: ServerRequest>(
        in plan: RecordLoadPlan,
        for _: Request.Type
    ) {
        guard plan.tuples.contains(where: \.isRefinedByRequest) else {
            return
        }
        let declaresSort = Request.Sort.self != EmptySort.self
        let declaresWindow = Request.Query.self is any PaginatedQuery.Type
        if !declaresSort, !declaresWindow {
            logger.warning(".refinedByRequest in \(String(describing: Request.self))'s plan is dead: the request type declares no refinement axes (Sort is EmptySort and Query is not PaginatedQuery)")
        }
    }

    /// A `.refinedByRequest` plan whose request `Sort` is neither `EmptySort` nor a
    /// `SortCriteria` (the `ErasedSortTermsProviding` bridge) contributes ZERO sort terms: the
    /// executor's refinement bridge silently produces no terms, so the request compiles and
    /// serves but its sort is a no-op. Warn — don't throw — naming the request and the ignored
    /// `Sort` type so the silent zero-terms behavior becomes visible.
    func warnOnForeignSortBridge<Request: ServerRequest>(
        in plan: RecordLoadPlan,
        for _: Request.Type
    ) {
        guard plan.tuples.contains(where: \.isRefinedByRequest) else {
            return
        }
        let sortType = Request.Sort.self
        if sortType == EmptySort.self || sortType is any ErasedSortTermsProviding.Type {
            return
        }
        logger.warning("\(String(describing: Request.self))'s .refinedByRequest plan declares Sort type \(String(describing: sortType)), which is neither EmptySort nor SortCriteria — it contributes zero sort terms, so the request's sort is silently ignored")
    }

    /// A registered `.guards` container whose records the plan loads WITHOUT traversing the
    /// guard never anchors that load — warn, don't throw: the load's root itself may be the
    /// guard, and roots bind to identities only at request time.
    func warnOnBypassedGuards(in plan: RecordLoadPlan, request: String) {
        let guardContainers = modelTypeRegistry.allRegistered.filter { $0.authorityFlow == .guards }
        guard !guardContainers.isEmpty else {
            return
        }
        for tuple in plan.tuples {
            for guardContainer in guardContainers
                where guardContainer.containment.contains(where: { ObjectIdentifier($0.containedType) == ObjectIdentifier(tuple.recordType) })
                && !tuple.path.contains(where: { $0.modelIdentityNamespace == guardContainer.namespace }) {
                logger.warning("\(request)'s plan loads \(String(describing: tuple.recordType)) on a path that never traverses \(guardContainer.typeName) (.guards) — the guard will not anchor this load")
            }
        }
    }
}

private struct RecordLoadPlanStorageKey: StorageKey {
    typealias Value = [ObjectIdentifier: RecordLoadPlan]
}

// MARK: - Candidate (write) plan derivation

/// Wraps a write request's ``WriteTargetProviding/candidates`` as a single-requirement composable
/// factory, so the SAME `RecordLoadPlan.walk` that derives read plans derives the candidate plan —
/// one code path, no parallel walker. `candidates` is read once here (the derived plan is stored
/// and reused): re-reading a computed `candidates` would mint fresh declaration tokens, which the
/// token-stability lint rejects at boot.
private struct CandidateFactory<Writer: WriteTargetProviding>: ComposableFactory {
    static var dataRequirements: [any DataRequirement] {
        [Writer.candidates]
    }
}

extension Application {
    /// Derives, validates, and stores the write request's candidate ``RecordLoadPlan`` — the
    /// write-side twin of `registerRecordLoadPlan`. Boot fail-fasts: an unstable (computed)
    /// `candidates`; a candidate verb that does not match the registering door's
    /// (`expectedOperation` — e.g. `.write` candidates on a delete registration); a `.create`
    /// candidate with intermediate hops; a `.refinedByRequest`-marked candidate (a windowed
    /// candidate set would fabricate not-found for targets outside the window); an unresolvable
    /// candidate hop; a `.query`-rooted candidate whose request query is not `RootedQuery`; a
    /// `.apex`-rooted candidate with no registered resolver.
    func deriveCandidatePlan<SR: ServerRequest, Writer: WriteTargetProviding>(
        for _: SR.Type,
        writer _: Writer.Type,
        expectedOperation: ContainerOperation
    ) throws {
        let requestName = String(describing: SR.self)

        guard RecordLoadPlan.requirementTokensAreStable(for: CandidateFactory<Writer>.self) else {
            throw ContainmentError.unstableRequirementTokens(
                request: requestName,
                handle: "\(String(describing: Writer.self)).candidates"
            )
        }

        let plan = try RecordLoadPlan.walk(from: CandidateFactory<Writer>.self)
        try requireVerbDoorCoherence(of: plan, request: requestName, writer: Writer.self, expectedOperation: expectedOperation)
        try resolveHops(of: plan, request: requestName)
        try requireRootBindings(of: plan, for: SR.self)

        var plans = storage[CandidatePlanStorageKey.self] ?? [:]
        plans[ObjectIdentifier(SR.self)] = plan
        storage[CandidatePlanStorageKey.self] = plans
    }

    /// The stored candidate plan for a write request type — derived at write registration, resolved
    /// per request by the write route. `nil` means the request was never registered as a write.
    func candidatePlan<SR: ServerRequest>(for _: SR.Type) -> RecordLoadPlan? {
        storage[CandidatePlanStorageKey.self]?[ObjectIdentifier(SR.self)]
    }
}

/// Internal (not private): the walk can only produce a `.createRecords` tuple with a non-empty
/// path through composition prefixing, which `deriveCandidatePlan`'s childless CandidateFactory
/// can never trigger — the boot test exercises that defense-in-depth branch directly.
extension Application {
    /// Verb–door coherence: the candidate declaration's verb must be the registering door's
    /// (`.write` for PATCH, `.create` for POST, `.delete` for DELETE) — a mismatched verb would
    /// load candidates under the wrong grant question. `.create` candidates additionally take no
    /// intermediate hops (the create scope is exactly one container), and no candidate may carry
    /// `.refinedByRequest` (a windowed candidate set would fabricate not-found for targets that
    /// fall outside the window's page).
    func requireVerbDoorCoherence<Writer: WriteTargetProviding>(
        of plan: RecordLoadPlan,
        request: String,
        writer _: Writer.Type,
        expectedOperation: ContainerOperation
    ) throws {
        let writerName = String(describing: Writer.self)
        for tuple in plan.tuples {
            guard tuple.operation == expectedOperation else {
                throw ContainmentError.invalidLoadPlan(
                    request: request,
                    reason: "\(writerName).candidates declares a .\(tuple.operation) load but this door registers .\(expectedOperation) — the candidate verb must match the write door (LoadRequirement.write for update, .create for create, .delete for delete)"
                )
            }
            if expectedOperation == .createRecords, !tuple.path.isEmpty {
                throw ContainmentError.invalidLoadPlan(
                    request: request,
                    reason: "\(writerName).candidates declares a .create scope with intermediate hops — the create scope is exactly one container; declare it with no via: path"
                )
            }
            if tuple.isRefinedByRequest {
                throw ContainmentError.invalidLoadPlan(
                    request: request,
                    reason: "\(writerName).candidates carries .refinedByRequest — a windowed candidate set would fabricate not-found for targets outside the window; candidates load whole, never refined"
                )
            }
        }
    }
}

// `resolveHops` / `requireRootBindings` are file-private to PlanRegistration; deriveCandidatePlan
// reuses them by living in the same file.

private struct CandidatePlanStorageKey: StorageKey {
    typealias Value = [ObjectIdentifier: RecordLoadPlan]
}

// MARK: - Apex container resolver

/// The boot-registered `.apex` root binding: resolves the application's apex container
/// identity for a request (constant apps return a constant; multi-tenant apps resolve
/// per request).
struct ApexContainerResolver: Sendable {
    let resolve: @Sendable (Vapor.Request) async throws -> ModelIdentity
}

extension Application {
    /// Registers the app's apex container resolver — answers "who is the top container for this
    /// caller?" so `.apex`-rooted loads bind their root identity through it:
    ///
    /// ```swift
    /// try app.useApexContainerResolver { req in
    ///     try await req.auth.require(User.self).harborIdentity
    /// }
    /// ```
    ///
    /// Constant apps return a constant; multi-tenant apps resolve per request. Plan validation
    /// requires a registered resolver for any `.apex`-rooted plan.
    ///
    /// - Throws: if a resolver is already registered — exactly one per application, caught at boot.
    public func useApexContainerResolver(
        _ resolver: @escaping @Sendable (Vapor.Request) async throws -> ModelIdentity
    ) throws {
        guard storage[ApexContainerResolverStorageKey.self] == nil else {
            throw ContainmentError.duplicateApexContainerResolver
        }
        storage[ApexContainerResolverStorageKey.self] = ApexContainerResolver(resolve: resolver)
    }

    /// Read side of the seam — consumed by the `.apex` boot check and the plan executor.
    var apexContainerResolver: ApexContainerResolver? {
        storage[ApexContainerResolverStorageKey.self]
    }
}

private struct ApexContainerResolverStorageKey: StorageKey {
    typealias Value = ApexContainerResolver
}
