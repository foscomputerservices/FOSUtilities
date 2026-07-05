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

    private let findById: @Sendable (ModelIdType, any Database) async throws -> (any DataModel)?

    init(for type: (some ContainerDataModel).Type) {
        self.namespace = type.modelIdentityNamespace
        self.containment = type.containment
        self.authorityFlow = type.authorityFlow
        self.typeName = String(describing: type)
        self.findById = { id, db in try await type.find(id, on: db) }
    }

    /// Fetch the instance for this identity's id — the engine's recover step.
    func find(_ id: ModelIdType, on db: any Database) async throws -> (any DataModel)? {
        try await findById(id, db)
    }
}
