// Application+DataModelLifecycle.swift
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
import Vapor

extension Vapor.Application {
    /// Wires the lifecycle middleware for one registration: the model itself, every contained
    /// type, and every `.siblings` pivot — the same type set the emit middleware covers. Each
    /// model type gets exactly one middleware no matter how many descriptors reach it, so a type
    /// two containers declare still runs its hooks once per write.
    ///
    /// Called from every `register` overload, never gated on live invalidation: the hooks are
    /// a property of the model, not of the notification layer.
    func registerLifecycleMiddleware(for descriptor: RegisteredModel) {
        var modelTypes: [any DataModel.Type] = descriptor.modelType.map { [$0] } ?? []
        for relation in descriptor.containment {
            modelTypes.append(relation.containedType)
            if let pivotType = relation.pivotType {
                modelTypes.append(pivotType)
            }
        }

        // Weak: the middleware lives in the Databases configuration the Application owns — a
        // strong capture would cycle. After shutdown no hook runs.
        let applicationReader: @Sendable () -> Vapor.Application? = { [weak self] in self }

        var covered = storage[LifecycleCoverageStore.self] ?? []
        for modelType in modelTypes {
            guard covered.insert(ObjectIdentifier(modelType)).inserted else {
                continue
            }
            databases.middleware.use(
                lifecycleMiddleware(for: modelType, applicationReader: applicationReader)
            )
        }
        storage[LifecycleCoverageStore.self] = covered
    }
}

/// Opens the erased model type into the generic middleware (SE-0352): FluentKit's middleware
/// protocol type-filters per concrete model, so each covered type needs its own instance.
private func lifecycleMiddleware<M: DataModel>(
    for _: M.Type,
    applicationReader: @escaping @Sendable () -> Vapor.Application?
) -> any AnyModelMiddleware {
    DataModelLifecycleMiddleware<M>(applicationReader: applicationReader)
}

/// The model types whose lifecycle middleware is already wired — a type can enter through several
/// descriptors (its own registration, a container's contained side, a pivot). Kept apart from the
/// emit middleware's coverage: the two are installed under different conditions.
private struct LifecycleCoverageStore: StorageKey {
    typealias Value = Set<ObjectIdentifier>
}
