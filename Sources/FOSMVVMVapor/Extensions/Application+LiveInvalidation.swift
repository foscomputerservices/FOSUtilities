// Application+LiveInvalidation.swift
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

public extension Vapor.Application {
    /// Turns on live invalidation for this server
    ///
    /// Call once at boot, passing the route group your clients authenticate
    /// against; every registered container model then nudges connected clients
    /// after each committed change:
    ///
    /// ```swift
    /// let authed = app.grouped(MyAuthMiddleware())
    /// try app.useLiveInvalidation(on: authed)
    /// ```
    ///
    /// Model registrations made before or after this call are both honored.
    func useLiveInvalidation(on routes: any RoutesBuilder) throws {
        guard storage[InvalidationHubStore.self] == nil else {
            throw LiveInvalidationError.alreadyEnabled
        }

        let hub = InvalidationHub()
        storage[InvalidationHubStore.self] = hub

        // Sweep registrations made BEFORE this call; register(_:migration:) covers the ones
        // made after (spec §3.1: either call order works).
        for descriptor in modelTypeRegistry.allRegistered {
            registerInvalidationEmitMiddleware(for: descriptor, hub: hub)
        }

        mountInvalidationStream(on: routes, hub: hub)
    }
}

extension Vapor.Application {
    /// The hub's presence IS the layer's enabled flag — set once by useLiveInvalidation(on:).
    var invalidationHub: InvalidationHub? {
        storage[InvalidationHubStore.self]
    }

    /// Wires the emit middleware for one registration: the container itself, every contained
    /// type, and every `.siblings` pivot (a membership change IS a pivot save — spec §3.1). Each
    /// model type gets exactly one middleware no matter how many descriptors reach it — a
    /// duplicate would double-emit.
    func registerInvalidationEmitMiddleware(for descriptor: RegisteredModel, hub: InvalidationHub) {
        var modelTypes: [any DataModel.Type] = [descriptor.modelType]
        for relation in descriptor.containment {
            modelTypes.append(relation.containedType)
            if let pivotType = relation.pivotType {
                modelTypes.append(pivotType)
            }
        }

        // Weak: the middleware lives in the Databases configuration the Application owns — a
        // strong capture would cycle. After shutdown the reader degrades to an empty registry.
        let registryReader: @Sendable () -> ModelTypeRegistry = { [weak self] in
            self?.modelTypeRegistry ?? ModelTypeRegistry()
        }

        var covered = storage[InvalidationEmitCoverageStore.self] ?? []
        for modelType in modelTypes {
            guard covered.insert(ObjectIdentifier(modelType)).inserted else {
                continue
            }
            databases.middleware.use(
                emitMiddleware(for: modelType, hub: hub, registryReader: registryReader)
            )
        }
        storage[InvalidationEmitCoverageStore.self] = covered
    }
}

/// Opens the erased model type into the generic middleware (SE-0352): FluentKit's middleware
/// protocol type-filters per concrete model, so each covered type needs its own instance.
private func emitMiddleware<M: DataModel>(
    for _: M.Type,
    hub: InvalidationHub,
    registryReader: @escaping @Sendable () -> ModelTypeRegistry
) -> any AnyModelMiddleware {
    InvalidationEmitMiddleware<M>(hub: hub, registryReader: registryReader)
}

private struct InvalidationHubStore: StorageKey {
    typealias Value = InvalidationHub
}

/// The model types whose emit middleware is already wired — a type can enter through several
/// descriptors (its own registration, a container's contained side, a pivot).
private struct InvalidationEmitCoverageStore: StorageKey {
    typealias Value = Set<ObjectIdentifier>
}

/// Boot-time misconfiguration; internal like ContainmentError — apps never catch it, its value
/// is the diagnostic message in Vapor's failed configure(_:).
enum LiveInvalidationError: Error, CustomDebugStringConvertible {
    case alreadyEnabled

    var debugDescription: String {
        switch self {
        case .alreadyEnabled:
            "useLiveInvalidation(on:) was called twice. Enable live invalidation exactly once at boot — a second enable would double-wire the emit middleware."
        }
    }
}
