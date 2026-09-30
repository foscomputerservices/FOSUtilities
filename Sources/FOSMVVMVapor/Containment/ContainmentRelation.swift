// ContainmentRelation.swift
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
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

/// One authorization-bearing containment relationship of a container, declared from a Fluent relationship.
///
/// Build these from your `@Children` / `@Siblings` / `@Parent` relationships — the framework reads the
/// join off Fluent, so you never restate a foreign key or pivot table:
///
/// ```swift
/// extension Board: ContainerDataModel {
///     static var containment: [ContainmentRelation] {
///         [.children(\Board.$cards), .siblings(\Board.$members)]   // Board owns Cards (FK) and Members (pivot)
///     }
/// }
/// ```
///
/// List only the relationships that a subject can be *authorized to* — not every Fluent relationship is
/// containment.
public struct ContainmentRelation: Sendable {
    // Erased types, internal: consumed by the register-time checks + C6, not by app code.
    // `any DataModel`, not a bare `Model` — this module sees both FOSMVVM.Model and FluentKit.Model,
    // and C6 needs the Fluent query capability.
    /// == From.self, captured by the factory; for `.all(_:)` the owning `SystemContainer` type once
    /// `register(_:)` binds it, and `nil` until then (an `.all` relation has no From to capture).
    let containerType: Any.Type?
    let containedType: any DataModel.Type // == To.self, captured by the factory
    /// `true` for `.all(_:)`: the relation reaches every row of the type, so the subject-scope
    /// engine loads the type whole instead of gathering its ids.
    let reachesWholeType: Bool
    /// == Through.self for `.siblings`, nil otherwise. A membership change IS a pivot save, so the
    /// L2 emit sweep must cover the pivot type — the relation is the only place Through is concrete.
    let pivotType: (any DataModel.Type)?

    /// ONE refinement-aware code path with two internal entries (refined/unrefined) — no drift.
    /// The container is the fetched row, or `nil` for a system container (which has none): the
    /// row relations cast it and throw on `nil`; `.all` ignores it.
    private let load: @Sendable ((any DataModel)?, any Database, ContainmentQueryRefinement) async throws -> [any DataModel]

    /// The count twin of `load`: the size of the authorized member set, run as a `.count()` query —
    /// never a fetch. Honors the refinement's FILTER (it alone changes cardinality) but ignores sort
    /// and window (neither changes a count) — applied in lockstep with `load`.
    private let count: @Sendable ((any DataModel)?, any Database, ContainmentQueryRefinement) async throws -> Int

    /// The additive twin of `load`, captured at factory time: persists a new contained record
    /// into a fetched container, setting the join (FK or pivot) the same way Fluent's relationship
    /// does. `nil` for a `.parent` relation — a to-one parent is not a create scope. Internal so
    /// only the in-module write route calls it.
    private let create: (@Sendable (_ container: (any DataModel)?, _ child: any DataModel, _ db: any Database) async throws -> Void)?

    /// The inversion twin of `load`, captured at factory time: given a just-mutated instance, the
    /// identities of the containers THIS relation attributes staleness to — read straight off the
    /// instance's own join references (no DB). The L2 live-invalidation derivation
    /// (`InvalidationIdentitySet.staleIdentities(forMutated:registry:)`) is its only caller. Empty
    /// when the instance is not this
    /// relation's invertible end, or a reference is unset/nil. `isRegisteredContainer` gates the
    /// to-one target of `.parent` and the far end of `.siblings`: a target contributes only when it
    /// is itself a registered container.
    private let invert: @Sendable (
        _ mutated: any DataModel,
        _ isRegisteredContainer: @Sendable (any DataModel.Type) -> Bool
    ) -> Set<ModelIdentity>

    /// The ids of every member this relation reaches from ANY of the given containers, in one
    /// query: the subject-scope engine unions these across granted containers before loading
    /// the rows once with the request's refinement.
    private let memberIds: @Sendable (_ containerIds: [ModelIdType], _ db: any Database) async throws -> [ModelIdType]

    private init(
        containerType: Any.Type?,
        containedType: any DataModel.Type,
        reachesWholeType: Bool = false,
        pivotType: (any DataModel.Type)? = nil,
        load: @escaping @Sendable ((any DataModel)?, any Database, ContainmentQueryRefinement) async throws -> [any DataModel],
        count: @escaping @Sendable ((any DataModel)?, any Database, ContainmentQueryRefinement) async throws -> Int,
        create: (@Sendable ((any DataModel)?, any DataModel, any Database) async throws -> Void)?,
        invert: @escaping @Sendable (any DataModel, @Sendable (any DataModel.Type) -> Bool) -> Set<ModelIdentity>,
        memberIds: @escaping @Sendable ([ModelIdType], any Database) async throws -> [ModelIdType]
    ) {
        self.containerType = containerType
        self.containedType = containedType
        self.reachesWholeType = reachesWholeType
        self.pivotType = pivotType
        self.load = load
        self.count = count
        self.create = create
        self.invert = invert
        self.memberIds = memberIds
    }

    /// The ids of the members reached from any of `containerIds` — one query, no rows.
    func memberIds(ofContainers containerIds: [ModelIdType], on db: any Database) async throws -> [ModelIdType] {
        try await memberIds(containerIds, db)
    }

    /// A to-many child relationship (child table holds the foreign key back to the container).
    public static func children<From: DataModel, To: DataModel>(
        _ keyPath: KeyPath<From, ChildrenProperty<From, To>> & Sendable
    ) -> ContainmentRelation {
        .init(
            containerType: From.self,
            containedType: To.self,
            load: { container, db, refinement in
                try await refinement
                    .apply(to: container.cast(to: From.self)[keyPath: keyPath].query(on: db))
                    .all()
            },
            count: { container, db, refinement in
                try await ContainmentQueryRefinement
                    .applyFilter(refinement.filter, to: container.cast(to: From.self)[keyPath: keyPath].query(on: db))
                    .count()
            },
            create: { container, child, db in
                // ChildrenProperty.create sets the child's FK back to the container and saves it.
                try await container.cast(to: From.self)[keyPath: keyPath].create(child.cast(to: To.self), on: db)
            },
            invert: childInverter(keyPath),
            memberIds: { containerIds, db in
                // Registered types carry ModelIdType ids (register(_:migration:) requires it);
                // the casts only narrow the generic signature, never drop a real id.
                let ownerIds = containerIds.compactMap { $0 as? From.IDValue }
                let memberIds: [To.IDValue?] = switch From()[keyPath: keyPath].parentKey {
                case .required(let parentKeyPath):
                    try await To.query(on: db)
                        .filter(parentKeyPath.appending(path: \.$id) ~~ ownerIds)
                        .all(\._$id)
                case .optional(let parentKeyPath):
                    try await To.query(on: db)
                        .filter(parentKeyPath.appending(path: \.$id) ~~ ownerIds.map { Optional($0) })
                        .all(\._$id)
                }
                return memberIds.compactMap { $0.flatMap { $0 as? ModelIdType } }
            }
        )
    }

    /// A to-many sibling relationship joined through a pivot table.
    public static func siblings<From: DataModel, To: DataModel>(
        _ keyPath: KeyPath<From, SiblingsProperty<From, To, some DataModel>> & Sendable
    ) -> ContainmentRelation {
        .init(
            containerType: From.self,
            containedType: To.self,
            pivotType: siblingPivotType(keyPath),
            load: { container, db, refinement in
                try await refinement
                    .apply(to: container.cast(to: From.self)[keyPath: keyPath].query(on: db))
                    .all()
            },
            count: { container, db, refinement in
                try await ContainmentQueryRefinement
                    .applyFilter(refinement.filter, to: container.cast(to: From.self)[keyPath: keyPath].query(on: db))
                    .count()
            },
            create: { container, child, db in
                // A new sibling must be persisted before the pivot can reference it; then attach.
                // One transaction: a failed attach must not leave a committed orphan row.
                let to = try child.cast(to: To.self)
                let from = try container.cast(to: From.self)
                try await db.transaction { tx in
                    try await to.create(on: tx)
                    try await from[keyPath: keyPath].attach(to, on: tx)
                }
            },
            invert: siblingInverter(keyPath),
            memberIds: { containerIds, db in
                let siblings = From()[keyPath: keyPath]
                return try await siblingMemberIds(siblings, ofContainers: containerIds, on: db)
            }
        )
    }

    /// Every row of a type, owned by a ``SystemContainer`` — the relation of a container with no
    /// rows of its own.
    ///
    /// ```swift
    /// enum Suite: SystemContainer {
    ///     static var containment: [ContainmentRelation] { [.all(Workspace.self)] }
    /// }
    /// ```
    ///
    /// A grant on the system container's identity extends to every `Workspace`; a create within
    /// the application scope bound to it saves the row with no join to set; a write to any
    /// `Workspace` marks the system container stale. Only a `SystemContainer` may declare it —
    /// a `ContainerDataModel` listing `.all(_:)` is refused at registration.
    public static func all<To: DataModel>(_: To.Type) -> ContainmentRelation where To.IDValue == ModelIdType {
        // The constraint the owned type must meet anyway: only a type register(_:migration:) accepts
        // can be owned, and the boot check requires it registered — refused here, one step earlier.
        .init(
            containerType: nil, // bound to the owning SystemContainer by register(_:)
            containedType: To.self,
            reachesWholeType: true,
            load: { _, db, refinement in
                try await refinement.apply(to: To.query(on: db)).all()
            },
            count: { _, db, refinement in
                try await ContainmentQueryRefinement.applyFilter(refinement.filter, to: To.query(on: db)).count()
            },
            create: { _, child, db in
                try await child.cast(to: To.self).create(on: db)
            },
            invert: { _, _ in [] }, // the owner's identity is known only once bound — see bound(to:owner:)
            memberIds: { _, db in
                // The engine loads the type whole through `reachesWholeType` and never asks this;
                // it stays correct for a caller that does ask by ids.
                try await To.query(on: db).all(\._$id).compactMap { $0 as? ModelIdType }
            }
        )
    }

    /// The same relation with its owner known: `containerType` names the system container and
    /// `invert` attributes every mutated row of the type to `identity`. `register(_:)` binds each
    /// `.all` relation this way; a row relation is never rebound (its owner is its From).
    func bound(to identity: ModelIdentity, owner: Any.Type) -> ContainmentRelation {
        let containedType = containedType
        return .init(
            containerType: owner,
            containedType: containedType,
            reachesWholeType: reachesWholeType,
            pivotType: pivotType,
            load: load,
            count: count,
            create: create,
            invert: { mutated, _ in
                ObjectIdentifier(type(of: mutated)) == ObjectIdentifier(containedType) ? [identity] : []
            },
            memberIds: memberIds
        )
    }

    /// A to-one parent relationship (this container's record references the parent by foreign key).
    public static func parent<From: DataModel, To: DataModel>(
        _ keyPath: KeyPath<From, ParentProperty<From, To>> & Sendable
    ) -> ContainmentRelation {
        // create: nil — a to-one parent is not a create scope; createMember(into:) rejects it.
        .init(
            containerType: From.self,
            containedType: To.self,
            load: { container, db, _ in
                // `.parent` ignores the whole refinement — filter, sort AND window are lossless for one row.
                try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).all()
            },
            count: { container, db, _ in
                try await container.cast(to: From.self)[keyPath: keyPath].query(on: db).count()
            },
            create: nil,
            invert: parentInverter(keyPath),
            memberIds: { containerIds, db in
                // The to-one target of each named container: read the FK off the rows.
                try await From.query(on: db)
                    .filter(\._$id ~~ containerIds.compactMap { $0 as? From.IDValue })
                    .all()
                    .compactMap { $0[keyPath: keyPath].id as? ModelIdType }
            }
        )
    }
}

// MARK: - Invalidation inversion (L2 live-invalidation)

extension ContainmentRelation {
    /// The identities of the containers this relation attributes staleness to, given a just-mutated
    /// instance — read straight off the instance's own join references, no DB. The derivation half
    /// of the L2 emit middleware; empty when `mutated` is not this relation's invertible end.
    func staleContainerIdentities(
        forMutated mutated: any DataModel,
        isRegisteredContainer: @Sendable (any DataModel.Type) -> Bool
    ) -> Set<ModelIdentity> {
        invert(mutated, isRegisteredContainer)
    }

    // `.children`: the mutated instance is the child (To); its FK back to the container (From) is
    // named by the ChildrenProperty's own `parentKey` — read that field directly for the owner id.
    private static func childInverter<From: DataModel, To: DataModel>(
        _ keyPath: KeyPath<From, ChildrenProperty<From, To>> & Sendable
    ) -> @Sendable (any DataModel, @Sendable (any DataModel.Type) -> Bool) -> Set<ModelIdentity> {
        { mutated, _ in
            guard let child = mutated as? To else { return [] }
            let ownerId: From.IDValue? = switch From()[keyPath: keyPath].parentKey {
            case .required(let parentKeyPath): child[keyPath: parentKeyPath].$id.value
            case .optional(let parentKeyPath): child[keyPath: parentKeyPath].id
            }
            return mintIdentity(of: From.self, id: ownerId).map { [$0] } ?? []
        }
    }

    // `.parent`: the mutated instance is the container (From) that holds the to-one FK; read the
    // referenced parent (To) id directly. The parent contributes only when it is itself a
    // registered container — the fixture's `.parent(\Board.$pier)` names an unregistered Pier and so
    // stays dormant; a child-declared owning container (`.parent(\Child.$owner)`) does not.
    private static func parentInverter<From: DataModel, To: DataModel>(
        _ keyPath: KeyPath<From, ParentProperty<From, To>> & Sendable
    ) -> @Sendable (any DataModel, @Sendable (any DataModel.Type) -> Bool) -> Set<ModelIdentity> {
        { mutated, isRegisteredContainer in
            guard let owner = mutated as? From, isRegisteredContainer(To.self) else { return [] }
            let parentId = owner[keyPath: keyPath].$id.value
            return mintIdentity(of: To.self, id: parentId).map { [$0] } ?? []
        }
    }

    /// Recovers Through concretely — the public `siblings` signature spells it `some DataModel`,
    /// which the factory body cannot name.
    private static func siblingPivotType<From: DataModel, Through: DataModel>(
        _: KeyPath<From, SiblingsProperty<From, some DataModel, Through>> & Sendable
    ) -> any DataModel.Type {
        Through.self
    }

    // `.siblings`: inverted from the PIVOT (Through) — a membership change IS a pivot save/delete.
    // The pivot's two `@Parent` references name both linked ends: the declaring container (From)
    // always contributes; the far end (To) contributes only when it too is a registered container.
    /// One pivot query: the `To` ids joined to any of the `From` ids.
    private static func siblingMemberIds<From: DataModel, To: DataModel, Through: DataModel>(
        _ siblings: SiblingsProperty<From, To, Through>,
        ofContainers containerIds: [ModelIdType],
        on db: any Database
    ) async throws -> [ModelIdType] {
        let memberIds: [To.IDValue] = try await Through.query(on: db)
            .filter(siblings.from.appending(path: \.$id) ~~ containerIds.compactMap { $0 as? From.IDValue })
            .all(siblings.to.appending(path: \.$id))
        return memberIds.compactMap { $0 as? ModelIdType }
    }

    private static func siblingInverter<From: DataModel, To: DataModel, Through: DataModel>(
        _ keyPath: KeyPath<From, SiblingsProperty<From, To, Through>> & Sendable
    ) -> @Sendable (any DataModel, @Sendable (any DataModel.Type) -> Bool) -> Set<ModelIdentity> {
        { mutated, isRegisteredContainer in
            guard let pivot = mutated as? Through else { return [] }
            let siblings = From()[keyPath: keyPath]
            var identities: Set<ModelIdentity> = []
            if let identity = mintIdentity(of: From.self, id: pivot[keyPath: siblings.from].$id.value) {
                identities.insert(identity)
            }
            if isRegisteredContainer(To.self),
               let identity = mintIdentity(of: To.self, id: pivot[keyPath: siblings.to].$id.value) {
                identities.insert(identity)
            }
            return identities
        }
    }
}

/// Mints a container's opaque ``ModelIdentity`` from its type and a persisted id, via the sanctioned
/// public seam (a fresh instance's ``Model/modelIdentity``) — FOSMVVMVapor cannot mint one from raw
/// values. `nil` id (an unset/unloaded reference) yields `nil`, never a crash. `_$id.value` is the
/// generic FluentKit id seam that sidesteps the FOSMVVM/FluentKit `id` ambiguity on `DataModel`.
private func mintIdentity<M: DataModel>(of _: M.Type, id: M.IDValue?) -> ModelIdentity? {
    guard let id else { return nil }
    let model = M()
    model._$id.value = id
    return try? model.modelIdentity
}

extension ContainmentRelation {
    // The UNREFINED, UNAUTHORIZED containment load. C6 is the authorized entry point that wraps this
    // and composes filter/sort/pagination onto the query. Internal so only in-module engine code
    // calls it. For `.parent` (to-one) the result is a single-element array.
    // PRECONDITION: `container` must be a *fetched* instance (Fluent fatalErrors on an unpopulated
    // relationship idValue) — the engine always obtains it via RegisteredModel.find.
    func members(of container: (any DataModel)?, on db: any Database) async throws -> [any DataModel] {
        try await load(container, db, .none)
    }

    /// Refined containment load: applies the refinement INSIDE the typed closure (push-down: sort via
    /// To's SortableDataModel mappings, window via QueryBuilder.range) before `.all()`. `.parent`
    /// ignores the whole refinement (sort AND window — lossless for one row). Sort terms whose key
    /// type ≠ To.RequestSortKey, or a To that is not SortableDataModel while terms are present, throw
    /// ContainmentError.unsortableContainedType — fail-fast, never a silently unsorted result.
    /// Same fetched-container PRECONDITION as the unrefined entry above.
    func members(
        of container: (any DataModel)?,
        on db: any Database,
        applying refinement: ContainmentQueryRefinement
    ) async throws -> [any DataModel] {
        try await load(container, db, refinement)
    }

    /// The count of the full authorized member set — the total an unfiltered window is a view into.
    /// Runs a `.count()` query; never fetches the rows. Same fetched-container PRECONDITION as
    /// `members`.
    func memberCount(of container: (any DataModel)?, on db: any Database) async throws -> Int {
        try await count(container, db, .none)
    }

    /// The count of the authorized member set the FILTER selects — the total a filtered window is a
    /// view into. Applies only the refinement's filter (sort/window never change a count), in
    /// lockstep with the refined `members`. Same fetched-container PRECONDITION as `members`.
    /// Filtering is opportunistic: a non-filterable To (or a non-matching query type) counts the
    /// full set, never throws.
    func memberCount(
        of container: (any DataModel)?,
        on db: any Database,
        applying refinement: ContainmentQueryRefinement
    ) async throws -> Int {
        try await count(container, db, refinement)
    }

    /// Persists `child` into `container` through this relation's join. Throws
    /// `ContainmentError.invalidCreateScope` for a `.parent` relation — a to-one parent is not a
    /// create scope. Same fetched-container PRECONDITION as the load entries.
    func createMember(_ child: any DataModel, into container: (any DataModel)?, on db: any Database) async throws {
        guard let create else {
            throw ContainmentError.invalidCreateScope(
                container: container.map { String(describing: type(of: $0)) } ?? containerType.map { String(describing: $0) } ?? "a system container",
                recordType: String(describing: type(of: child))
            )
        }
        try await create(container, child, db)
    }
}

extension Vapor.Request {
    /// Creates `child` inside the container named by `container`, through the container's own
    /// declared containment (its `.children`/`.siblings` relation for the child's type). The
    /// framework's create path: it recovers the container, finds the relation, and sets the join —
    /// the writer's `apply` never names a parent.
    ///
    /// Throws `ContainmentError.unregisteredNamespace` for an unregistered container namespace,
    /// `Abort(.notFound)` when the container row is gone, and
    /// `ContainmentError.invalidCreateScope` when the container declares no create scope (or only a
    /// `.parent` relation) for the child's type.
    func createMember(_ child: any DataModel, in container: ModelIdentity, on db: any Database) async throws {
        guard let descriptor = modelTypeRegistry.registered(for: container.namespace) else {
            throw ContainmentError.unregisteredNamespace(identity: String(describing: container))
        }
        // A system container has no row to recover: its `.all` create saves with no join.
        let containerRecord: (any DataModel)?
        if descriptor.isTableless {
            containerRecord = nil
        } else {
            guard let found = try await descriptor.find(container.id, on: db) else {
                throw Abort(.notFound)
            }
            containerRecord = found
        }
        let childType = ObjectIdentifier(type(of: child))
        guard let relation = descriptor.containment.first(where: {
            ObjectIdentifier($0.containedType) == childType
        }) else {
            throw ContainmentError.invalidCreateScope(
                container: descriptor.typeName,
                recordType: String(describing: type(of: child))
            )
        }
        try await relation.createMember(child, into: containerRecord, on: db)
    }
}

private extension (any DataModel)? {
    /// The row relations' container: a system container passes `nil`, which only `.all` accepts —
    /// a row relation reached with no row is framework-invariant breakage, thrown never swallowed.
    func cast<To: DataModel>(to type: To.Type) throws -> To {
        guard let self else {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: type),
                actual: "no container row (a system container)"
            )
        }
        return try self.cast(to: type)
    }
}

private extension DataModel {
    /// Backstop, not a code path: register(_:migration:) proves every relation's containerType at
    /// boot, so a failing cast here means framework-invariant breakage — throw, never return [].
    func cast<To: DataModel>(to _: To.Type) throws -> To {
        guard let cast = self as? To else {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: To.self),
                actual: String(describing: type(of: self))
            )
        }
        return cast
    }
}
