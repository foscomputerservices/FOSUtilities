// ModelTypeRegistry.swift
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

/// Recovers a persisted ModelIdentity's Swift model type (and its containment) on the server.
/// Populated as a side effect of Application.register(_:migration:); injected into Application/Request
/// storage — never process-global (parallel-test isolation). Internal: every current consumer
/// (C6 engine, C8 factory, DEF-7 guard) is in-module — promote to `public` only when
/// an app-side consumer appears (additive). Deliberately distinct from localization's ModelRegistry.
struct ModelTypeRegistry: Sendable {
    private var models: [ModelNamespace: RegisteredModel] = [:]

    init() {}

    /// The descriptor registered for a namespace, or nil if none is registered.
    func registered(for namespace: ModelNamespace) -> RegisteredModel? {
        models[namespace]
    }

    /// Every registered descriptor — the boot-validation sweep's iteration surface.
    var allRegistered: [RegisteredModel] {
        Array(models.values)
    }

    /// Throws ContainmentError.duplicateNamespace — silent last-writer-wins would corrupt the
    /// identity→type mapping that authorization keys on.
    mutating func insert(_ model: RegisteredModel) throws {
        guard models[model.namespace] == nil else {
            throw ContainmentError.duplicateNamespace(modelType: model.typeName)
        }
        models[model.namespace] = model
    }
}

/// A type-erased handle to a registered model — recover an instance by id, and read its containment.
struct RegisteredModel: Sendable {
    let namespace: ModelNamespace
    let containment: [ContainmentRelation]
    let authorityFlow: AuthorityFlow
    let typeName: String
    /// The registered concrete type — the L2 emit-middleware sweep opens it back into a generic
    /// (a container with EMPTY containment has no relation to recover its type from). `nil` for a
    /// system container: it has no rows, so no middleware of its own to install.
    let modelType: (any DataModel.Type)?
    /// Whether this registration declares a container. A plain DataModel is registered for its
    /// lifecycle hooks and its own identity, and must never answer the containment inversion's
    /// `isRegisteredContainer` question — an empty `containment` cannot tell the two apart
    /// (a container may legitimately declare none).
    let isContainer: Bool
    /// A `SystemContainer` registration: one identity, no table. The engine skips the row fetch
    /// and hands its relations no container; the two middleware sweeps install nothing for it.
    let isTableless: Bool
    /// The one identity of a system container; `nil` for a registration with rows (whose
    /// identities are minted per row).
    let identity: ModelIdentity?

    private let findById: @Sendable (ModelIdType, any Database) async throws -> (any DataModel)?
    // The subject-scope engine's one refined query over an id set, and its count twin — captured
    // here because only the registering init knows the concrete type well enough to build them.
    private let loadByIds: @Sendable ([ModelIdType], ContainmentQueryRefinement, any Database) async throws -> [any DataModel]
    private let countByIds: @Sendable ([ModelIdType], AnyFilter?, any Database) async throws -> Int
    // The whole-type twins: a granted system container reaches every row, so no id list is built.
    private let loadAll: @Sendable (ContainmentQueryRefinement, any Database) async throws -> [any DataModel]
    private let countAll: @Sendable (AnyFilter?, any Database) async throws -> Int

    init(for type: (some ContainerDataModel).Type) {
        self.namespace = type.modelIdentityNamespace
        self.containment = type.containment
        self.authorityFlow = type.authorityFlow
        self.typeName = String(describing: type)
        self.modelType = type
        self.isContainer = true
        self.isTableless = false
        self.identity = nil
        self.findById = { id, db in try await type.find(id, on: db) }
        self.loadByIds = Self.loader(for: type)
        self.countByIds = Self.counter(for: type)
        self.loadAll = Self.wholeTypeLoader(for: type)
        self.countAll = Self.wholeTypeCounter(for: type)
    }

    /// A container with no rows: its relations are bound to its identity here, so a mutated
    /// owned row inverts to it and its `containerType` names the owner.
    init(for type: (some SystemContainer).Type) {
        let identity = type.identity
        self.namespace = identity.namespace
        self.containment = type.containment.map { $0.bound(to: identity, owner: type) }
        self.authorityFlow = type.authorityFlow
        self.typeName = String(describing: type)
        self.modelType = nil
        self.isContainer = true
        self.isTableless = true
        self.identity = identity
        // Unreachable by construction: the engine never fetches a system container's row and a
        // plan cannot name a SystemContainer as its type (it is not a Model) — thrown, not [].
        let typeName = String(describing: type)
        self.findById = { _, _ in throw ContainmentError.containerTypeMismatch(expected: "a stored DataModel", actual: typeName) }
        self.loadByIds = { _, _, _ in throw ContainmentError.containerTypeMismatch(expected: "a stored DataModel", actual: typeName) }
        self.countByIds = { _, _, _ in throw ContainmentError.containerTypeMismatch(expected: "a stored DataModel", actual: typeName) }
        self.loadAll = { _, _ in throw ContainmentError.containerTypeMismatch(expected: "a stored DataModel", actual: typeName) }
        self.countAll = { _, _ in throw ContainmentError.containerTypeMismatch(expected: "a stored DataModel", actual: typeName) }
    }

    /// A DataModel no registered container declares: it carries no containment, it needs no grant
    /// of its own, and it is not a container.
    init<M: DataModel>(for type: M.Type) where M.IDValue == ModelIdType {
        self.namespace = type.modelIdentityNamespace
        self.containment = []
        self.authorityFlow = .inherits
        self.typeName = String(describing: type)
        self.modelType = type
        self.isContainer = false
        self.isTableless = false
        self.identity = nil
        self.findById = { id, db in try await type.find(id, on: db) }
        self.loadByIds = Self.loader(for: type)
        self.countByIds = Self.counter(for: type)
        self.loadAll = Self.wholeTypeLoader(for: type)
        self.countAll = Self.wholeTypeCounter(for: type)
    }

    /// The rows of this type whose id is in `ids`, refined by the request — the subject-scope
    /// engine's one load.
    func records(withIds ids: [ModelIdType], applying refinement: ContainmentQueryRefinement, on db: any Database) async throws -> [any DataModel] {
        try await loadByIds(ids, refinement, db)
    }

    /// The count twin of ``records(withIds:applying:on:)``: honors the filter only.
    func recordCount(withIds ids: [ModelIdType], filter: AnyFilter?, on db: any Database) async throws -> Int {
        try await countByIds(ids, filter, db)
    }

    /// Every row of this type, refined by the request — the subject-scope engine's load when a
    /// granted system container owns the type.
    func records(applying refinement: ContainmentQueryRefinement, on db: any Database) async throws -> [any DataModel] {
        try await loadAll(refinement, db)
    }

    /// The count twin of ``records(applying:on:)``: honors the filter only.
    func recordCount(filter: AnyFilter?, on db: any Database) async throws -> Int {
        try await countAll(filter, db)
    }

    private static func loader<M: DataModel>(for _: M.Type) -> @Sendable ([ModelIdType], ContainmentQueryRefinement, any Database) async throws -> [any DataModel] where M.IDValue == ModelIdType {
        { ids, refinement, db in
            try await refinement.apply(to: M.query(on: db).filter(\._$id ~~ ids)).all()
        }
    }

    private static func counter<M: DataModel>(for _: M.Type) -> @Sendable ([ModelIdType], AnyFilter?, any Database) async throws -> Int where M.IDValue == ModelIdType {
        { ids, filter, db in
            try await ContainmentQueryRefinement.applyFilter(filter, to: M.query(on: db).filter(\._$id ~~ ids)).count()
        }
    }

    private static func wholeTypeLoader<M: DataModel>(for _: M.Type) -> @Sendable (ContainmentQueryRefinement, any Database) async throws -> [any DataModel] {
        { refinement, db in
            try await refinement.apply(to: M.query(on: db)).all()
        }
    }

    private static func wholeTypeCounter<M: DataModel>(for _: M.Type) -> @Sendable (AnyFilter?, any Database) async throws -> Int {
        { filter, db in
            try await ContainmentQueryRefinement.applyFilter(filter, to: M.query(on: db)).count()
        }
    }

    /// Fetch the instance for this identity's id — the engine's recover step.
    func find(_ id: ModelIdType, on db: any Database) async throws -> (any DataModel)? {
        try await findById(id, db)
    }
}
