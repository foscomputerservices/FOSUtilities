// IdentitySetDerivationTests.swift
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

// Test-taxonomy discipline: exercises the internal L2 emit-derivation via `@testable import
// FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

/// The `.siblings` fixtures give CrewMember a docks relation but no container conformance. Declaring
/// it here (same module as the fixtures — not retroactive) lets the pivot test register BOTH ends of
/// DockCrew as containers, so the pivot inversion's far-end branch is exercised, not just the near.
extension CrewMember: ContainerDataModel {
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Dock.self]
    }

    static var containment: [ContainmentRelation] {
        [.siblings(\CrewMember.$docks)]
    }
}

/// The `.parent` inverter's EMITTING branch needs a registered `.parent` target — the shared
/// fixtures register none, so `.parent(\Dock.$pier)` stays dormant everywhere else. Declaring Pier
/// a (leaf) container here lets one test register it and assert the Dock→Pier contribution.
/// Registration is per-app, so suites that don't register Pier are untouched.
extension Pier: ContainerDataModel {
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        []
    }

    static var containment: [ContainmentRelation] {
        []
    }
}

// MARK: - Optional-parent fixtures (the child inverter's `.optional(parentKeyPath)` branch)

/// Every shared-fixture `@Parent` is required; Marina/Buoy pin the `@OptionalParent` join —
/// `ChildrenProperty.parentKey == .optional` — through the same derivation path.
final class Marina: ContainerDataModel, @unchecked Sendable {
    static let schema = "marinas"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Buoy.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Marina.$buoys)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$marina) var buoys: [Buoy]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Buoy: DataModel, @unchecked Sendable {
    static let schema = "buoys"
    @ID(key: .id) var id: UUID?
    @Field(key: "label") var label: String
    @OptionalParent(key: "marina_id") var marina: Marina?
    init() {}
    init(label: String, marinaId: ModelIdType?) {
        self.label = label
        $marina.id = marinaId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

struct CreateMarina: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Marina.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Marina.schema).delete()
    }
}

struct CreateBuoy: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Buoy.schema).id()
            .field("label", .string, .required)
            .field("marina_id", .uuid, .references(Marina.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Buoy.schema).delete()
    }
}

@Suite("Invalidation identity-set derivation (spec §3.1, group 3)")
struct IdentitySetDerivationTests {
    /// A mutated `.children` member emits its own identity + its owning container's — read off the
    /// Berth's `dock_id` FK through Dock's `.children(\Dock.$berths)` parent key.
    @Test func childEmitsOwnAndOwningContainer() async throws {
        try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let berth = try #require(
                await Berth.query(on: db).filter(\.$dock.$id == dock1.requireId()).first()
            )

            let derived = InvalidationIdentitySet.staleIdentities(
                forMutated: berth,
                registry: app.modelTypeRegistry
            )

            #expect(try derived == Set([berth.modelIdentity, dock1.modelIdentity]))
        }
    }

    /// A mutated Dock emits its own identity + its apex Harbor's — read off the Dock's `harbor_id`
    /// FK through Harbor's `.children(\Harbor.$docks)`. Its unregistered `.parent(\Dock.$pier)`
    /// target (Pier) contributes nothing.
    @Test func containedContainerEmitsOwnAndApex() async throws {
        try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.query(on: db).first())

            let derived = InvalidationIdentitySet.staleIdentities(
                forMutated: dock1,
                registry: app.modelTypeRegistry
            )

            #expect(try derived == Set([dock1.modelIdentity, harbor.modelIdentity]))
        }
    }

    /// A mutated pivot (DockCrew) covers `.siblings` membership: it emits its own identity + both
    /// linked ends that are registered containers. With Dock AND CrewMember both registered, that is
    /// both ends.
    @Test func pivotEmitsBothRegisteredLinkedContainers() async throws {
        try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Dock.self, migration: CreateDock())
            try app.register(CrewMember.self, migration: CreateCrewMember())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let pivot = try #require(
                await DockCrew.query(on: db).filter(\.$dock.$id == dock1.requireId()).first()
            )
            let crew = try #require(await CrewMember.find(pivot.$crewMember.id, on: db))

            let derived = InvalidationIdentitySet.staleIdentities(
                forMutated: pivot,
                registry: app.modelTypeRegistry
            )

            #expect(try derived == Set([
                pivot.modelIdentity,
                dock1.modelIdentity,
                crew.modelIdentity
            ]))
        }
    }

    /// A registered model that no container declares (the apex Harbor) emits only its own identity.
    @Test func uncontainedModelEmitsOnlyItself() async throws {
        try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.find(dock1.$harbor.id, on: db))

            let derived = InvalidationIdentitySet.staleIdentities(
                forMutated: harbor,
                registry: app.modelTypeRegistry
            )

            #expect(try derived == Set([harbor.modelIdentity]))
        }
    }

    /// The `.parent` inverter's EMITTING branch: with Pier registered, a mutated Dock's own
    /// `.parent(\Dock.$pier)` reads the to-one target directly and the Pier identity joins the set —
    /// alongside the apex Harbor from the `.children` inversion.
    @Test func registeredParentTargetContributes() async throws {
        try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Pier.self, migration: CreatePier())
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(await Harbor.find(dock1.$harbor.id, on: db))
            let pier = try #require(await Pier.find(dock1.$pier.id, on: db))

            let derived = InvalidationIdentitySet.staleIdentities(
                forMutated: dock1,
                registry: app.modelTypeRegistry
            )

            #expect(try derived == Set([
                dock1.modelIdentity,
                harbor.modelIdentity,
                pier.modelIdentity
            ]))
        }
    }

    /// The child inverter's `.optional(parentKeyPath)` branch: a Buoy with its `@OptionalParent`
    /// marina SET derives its Marina; the SAME join left nil contributes nothing — {self} only.
    @Test func optionalParentKeyEmitsWhenSetAndSkipsWhenNil() async throws {
        try await withFluentTestApp { app in
            try app.register(Marina.self, migration: CreateMarina())
            app.migrations.add(CreateBuoy())
        } _: { app, db in
            let marina = Marina(name: "West Marina")
            try await marina.save(on: db)
            let moored = try Buoy(label: "B-1", marinaId: marina.requireId())
            let adrift = Buoy(label: "B-2", marinaId: nil)
            try await moored.save(on: db)
            try await adrift.save(on: db)

            let mooredSet = InvalidationIdentitySet.staleIdentities(
                forMutated: moored,
                registry: app.modelTypeRegistry
            )
            #expect(try mooredSet == Set([moored.modelIdentity, marina.modelIdentity]))

            let adriftSet = InvalidationIdentitySet.staleIdentities(
                forMutated: adrift,
                registry: app.modelTypeRegistry
            )
            #expect(try adriftSet == Set([adrift.modelIdentity]))
        }
    }

    /// An UNSET required reference contributes nothing and never crashes: an unsaved Berth with an
    /// id but no `dock_id` set derives {self} only (the required-parent `$id.value` read is nil).
    @Test func unsetRequiredReferenceContributesNothing() async throws {
        try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor())
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
        } _: { app, _ in
            let berth = Berth()
            berth._$id.value = ModelIdType()
            let ownIdentity = try berth.modelIdentity

            let derived = InvalidationIdentitySet.staleIdentities(
                forMutated: berth,
                registry: app.modelTypeRegistry
            )

            #expect(derived == Set([ownIdentity]))
        }
    }
}
