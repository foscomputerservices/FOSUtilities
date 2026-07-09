// Application+Containment.swift
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

public extension Application {
    /// Register a container model: adds its Fluent migration **and** its identity descriptor in one call,
    /// so declaring the migration *is* registering the type — there is no separate step to forget.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.register(Dock.self, migration: Dock.CreateDock())
    /// ```
    ///
    /// - Throws: if the model's namespace is already registered, or its `containment` doesn't match
    ///   its `containedRecordTypes` — a misconfiguration caught at boot, not at first request.
    func register(_ type: (some ContainerDataModel).Type, migration: any Migration) throws {
        // Boot-time fail-fast #2: every relation must be built from the registered type's own KeyPaths
        // (the factory's From generic is free — construction alone can't prove this).
        for relation in type.containment
            where ObjectIdentifier(relation.containerType) != ObjectIdentifier(type) {
            throw ContainmentError.containerTypeMismatch(
                expected: String(describing: relation.containerType),
                actual: String(describing: type)
            )
        }

        // Boot-time fail-fast #3 (arch §5 C4 invariant (a)): the two cross-boundary declarations of
        // "what this container owns" must not drift.
        let declared = Set(type.containment.map { ObjectIdentifier($0.containedType) })
        let contained = Set(type.containedRecordTypes.map { ObjectIdentifier($0) })
        guard declared == contained else {
            throw ContainmentError.containmentDrift(
                modelType: String(describing: type),
                containmentTypes: type.containment.map { String(describing: $0.containedType) },
                containedRecordTypes: type.containedRecordTypes.map { String(describing: $0) }
            )
        }

        // Boot-time fail-fast #1 (duplicate namespace) lives in insert(_:).
        var registry = modelTypeRegistry
        let descriptor = RegisteredModel(for: type)
        try registry.insert(descriptor)
        storage[ModelTypeRegistryStore.self] = registry

        migrations.add(migration)

        // L2 live invalidation honors registrations made AFTER useLiveInvalidation(on:) — the
        // boot switch sweeps the earlier ones (either call order works, spec §3.1).
        if let hub = invalidationHub {
            registerInvalidationEmitMiddleware(for: descriptor, hub: hub)
        }
    }
}

extension Application {
    /// Injected, not global — parallel-test isolation. Mirrors localizationStore/mvvmEnvironment.
    var modelTypeRegistry: ModelTypeRegistry {
        storage[ModelTypeRegistryStore.self] ?? ModelTypeRegistry()
    }
}

extension Vapor.Request {
    var modelTypeRegistry: ModelTypeRegistry {
        application.modelTypeRegistry
    }
}

private struct ModelTypeRegistryStore: StorageKey {
    typealias Value = ModelTypeRegistry
}

public extension Application {
    /// Register the app's authorization provider — the framework scopes every container load through it.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.useContainerAuthorizationProvider(GrantProvider())
    /// ```
    ///
    /// - Throws: if a provider is already registered — exactly one provider per application,
    ///   caught at boot.
    func useContainerAuthorizationProvider(_ provider: some ContainerAuthorizationProvider) throws {
        if let existing = storage[ContainerAuthorizationProviderStore.self] {
            throw ContainmentError.duplicateAuthorizationProvider(
                registered: String(describing: type(of: existing)),
                duplicate: String(describing: type(of: provider))
            )
        }
        storage[ContainerAuthorizationProviderStore.self] = provider
    }
}

extension Application {
    /// Read side of the seam — consumed only by Request's provider-driven entry (same module).
    var containerAuthorizationProvider: (any ContainerAuthorizationProvider)? {
        storage[ContainerAuthorizationProviderStore.self]
    }
}

private struct ContainerAuthorizationProviderStore: StorageKey {
    typealias Value = any ContainerAuthorizationProvider
}
