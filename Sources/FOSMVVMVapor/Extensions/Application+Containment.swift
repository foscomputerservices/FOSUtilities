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
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

public extension Application {
    /// Register a container model: adds its Fluent migration **and** its identity descriptor in one call,
    /// so declaring the migration *is* registering the type — there is no separate step to forget.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.register(Board.self, migration: Board.CreateBoard())
    /// ```
    ///
    /// - Throws: if the model's namespace is already registered, or its `containment` doesn't match
    ///   its `containedRecordTypes` — a misconfiguration caught at boot, not at first request.
    func register(_ type: (some ContainerDataModel).Type, migration: any Migration) throws {
        // Boot-time fail-fast #2: every relation must be built from the registered type's own KeyPaths
        // (the factory's From generic is free — construction alone can't prove this).
        for relation in type.containment {
            guard let containerType = relation.containerType else {
                throw ContainmentError.systemRelationOnContainer(
                    modelType: String(describing: type),
                    memberType: String(describing: relation.containedType)
                )
            }
            guard ObjectIdentifier(containerType) == ObjectIdentifier(type) else {
                throw ContainmentError.containerTypeMismatch(
                    expected: String(describing: containerType),
                    actual: String(describing: type)
                )
            }
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

        // Lifecycle BEFORE emit: FluentKit chains in installation order, so the first installed is
        // the outermost — both validations run before anything else touches the row.
        registerLifecycleMiddleware(for: descriptor)

        // L2 live invalidation honors registrations made AFTER useLiveInvalidation(on:) — the
        // boot switch sweeps the earlier ones (either call order works, spec §3.1).
        if let hub = invalidationHub {
            registerInvalidationEmitMiddleware(for: descriptor, hub: hub)
        }
    }

    /// Register a ``SystemContainer`` — the container with no rows that owns every row of the types
    /// it lists — so grants on its identity scope loads, creates at the top land in it, and a
    /// write to an owned row marks it stale:
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.register(Suite.self)
    /// try app.register(Workspace.self, migration: Workspace.Initial())   // what Suite owns, registered as usual
    /// ```
    ///
    /// No migration: there is no table. With exactly one system container registered and no
    /// `useApplicationScope(_:)`, plans within `.application` bind to it by themselves.
    ///
    /// - Throws: if the container's namespace is already registered, or one of its relations is
    ///   not ``ContainmentRelation/all(_:)``. A listed type left unregistered is refused when the
    ///   application boots, whichever order the registrations came in.
    func register(_ type: (some SystemContainer).Type) throws {
        for relation in type.containment {
            if let containerType = relation.containerType {
                throw ContainmentError.rowRelationOnSystemContainer(
                    modelType: String(describing: type),
                    relationContainer: String(describing: containerType)
                )
            }
        }

        var registry = modelTypeRegistry
        let descriptor = RegisteredModel(for: type)
        try registry.insert(descriptor)
        storage[ModelTypeRegistryStore.self] = registry

        // No middleware: the container has no rows, and its owned types install their own when
        // they register — which the boot check below requires.
        // Registration order is the app's: the owned-types check runs once, at boot.
        if storage[SystemContainerBootCheckStore.self] == nil {
            storage[SystemContainerBootCheckStore.self] = true
            lifecycle.use(SystemContainerBootCheck())
        }
    }

    /// Every type a registered system container lists must itself be registered — a `.all`
    /// relation loads and creates rows of a type the registry must know.
    func requireSystemContainerMembersRegistered() throws {
        for descriptor in modelTypeRegistry.allRegistered where descriptor.isTableless {
            for relation in descriptor.containment
                where modelTypeRegistry.registered(for: relation.containedType.modelIdentityNamespace) == nil {
                throw ContainmentError.unregisteredSystemMember(
                    container: descriptor.typeName,
                    memberType: String(describing: relation.containedType)
                )
            }
        }
    }

    /// Register a `DataModel` with its migration, so its lifecycle hooks and live invalidation run
    ///
    /// Same call as for a container; every `DataModel` goes through it, contained or not:
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.register(Board.self, migration: Board.Initial())   // a container
    /// try app.register(Card.self, migration: Card.Initial())     // a contained type
    /// try app.register(ServiceStatus.self, migration: ServiceStatus.Create())  // no container
    /// ```
    ///
    /// Adding the migration directly with `app.migrations.add` skips the hooks; the review reports it.
    /// Registering a model does not by itself make it loadable by a factory: a plan reaches a
    /// `DataModel` through a container that declares it, or — `within: .subject` — through a grant
    /// that names it (``ModelAuthorization``), and a subject-scoped plan requires the model registered.
    ///
    /// - Throws: if the model's namespace is already registered.
    func register<M: DataModel>(_ type: M.Type, migration: any Migration) throws
        where M.IDValue == ModelIdType {
        var registry = modelTypeRegistry
        let descriptor = RegisteredModel(for: type)
        try registry.insert(descriptor)
        storage[ModelTypeRegistryStore.self] = registry

        migrations.add(migration)

        registerLifecycleMiddleware(for: descriptor)

        if let hub = invalidationHub {
            registerInvalidationEmitMiddleware(for: descriptor, hub: hub)
        }
    }
}

/// Installed once by the first `register(_:)` of a system container; runs the owned-types check
/// when the application boots, so registration order is the app's.
private struct SystemContainerBootCheck: LifecycleHandler {
    func willBoot(_ application: Application) throws {
        try application.requireSystemContainerMembersRegistered()
    }
}

private struct SystemContainerBootCheckStore: StorageKey {
    typealias Value = Bool
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
    /// Register the app's grant provider — the framework scopes every load through it.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.useModelAuthorizationProvider(GrantProvider())
    /// ```
    ///
    /// - Throws: if a provider is already registered — exactly one provider per application,
    ///   caught at boot.
    func useModelAuthorizationProvider(_ provider: some ModelAuthorizationProvider) throws {
        if let existing = storage[ModelAuthorizationProviderStore.self] {
            throw ContainmentError.duplicateAuthorizationProvider(
                registered: String(describing: type(of: existing)),
                duplicate: String(describing: type(of: provider))
            )
        }
        storage[ModelAuthorizationProviderStore.self] = provider
    }

    /// The former spelling of ``useModelAuthorizationProvider(_:)``.
    @available(*, deprecated, renamed: "useModelAuthorizationProvider(_:)")
    func useContainerAuthorizationProvider(_ provider: some ModelAuthorizationProvider) throws {
        try useModelAuthorizationProvider(provider)
    }
}

extension Application {
    /// Read side of the seam — consumed only by Request's provider-driven entry (same module).
    var modelAuthorizationProvider: (any ModelAuthorizationProvider)? {
        storage[ModelAuthorizationProviderStore.self]
    }
}

private struct ModelAuthorizationProviderStore: StorageKey {
    typealias Value = any ModelAuthorizationProvider
}
