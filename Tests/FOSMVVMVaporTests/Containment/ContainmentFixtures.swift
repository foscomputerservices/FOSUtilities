// ContainmentFixtures.swift
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

import Fluent // app.migrations (addHarborMigrations) lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import Foundation
import Vapor

// Fluent fixtures follow Vapor's template idiom (final class + @unchecked Sendable).
// validate(fields:validations:) returns nil — fixtures carry no form contract.

final class Pier: DataModel, @unchecked Sendable {
    static let schema = "piers"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// The apex container — every Dock belongs to a Harbor; apex-rooted plans resolve here.
final class Harbor: ContainerDataModel, @unchecked Sendable {
    static let schema = "harbors"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Dock.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Harbor.$docks)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$harbor) var docks: [Dock]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Dock: ContainerDataModel, @unchecked Sendable {
    static let schema = "docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Berth.self, CrewMember.self, Pier.self, PersonnelFolder.self]
    }

    static var containment: [ContainmentRelation] {
        [
            .children(\Dock.$berths),
            .siblings(\Dock.$crew),
            .parent(\Dock.$pier),
            .children(\Dock.$personnelFolders)
        ]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "harbor_id") var harbor: Harbor
    @Parent(key: "pier_id") var pier: Pier
    @Children(for: \.$dock) var berths: [Berth]
    @Children(for: \.$dock) var personnelFolders: [PersonnelFolder]
    @Siblings(through: DockCrew.self, from: \.$dock, to: \.$crewMember) var crew: [CrewMember]
    init() {}
    init(name: String, pierId: ModelIdType, harborId: ModelIdType) {
        self.name = name
        $pier.id = pierId
        $harbor.id = harborId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// A `.guards` container under Dock — authority granted above stops here; its records need
/// authority anchored at the folder itself. Registered only by the suites that exercise it.
final class PersonnelFolder: ContainerDataModel, @unchecked Sendable {
    static let schema = "personnel_folders"
    static var authorityFlow: AuthorityFlow {
        .guards
    }

    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [PersonnelFile.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\PersonnelFolder.$files)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "dock_id") var dock: Dock
    @Children(for: \.$folder) var files: [PersonnelFile]
    init() {}
    init(name: String, dockId: ModelIdType) {
        self.name = name
        $dock.id = dockId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Child of PersonnelFolder — reachable only through the guard.
final class PersonnelFile: DataModel, @unchecked Sendable {
    static let schema = "personnel_files"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "folder_id") var folder: PersonnelFolder
    init() {}
    init(name: String, folderId: ModelIdType) {
        self.name = name
        $folder.id = folderId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Berth: DataModel, @unchecked Sendable {
    static let schema = "berths"
    @ID(key: .id) var id: UUID?
    @Field(key: "number") var number: Int
    @Field(key: "dock_name") var dockName: String // denormalized — the composite-sort fixture column
    @Parent(key: "dock_id") var dock: Dock
    init() {}
    init(number: Int, dockName: String, dockId: ModelIdType) {
        self.number = number
        self.dockName = dockName
        $dock.id = dockId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Berth's ONE published sort vocabulary (test-side stand-in for a shared-module enum).
enum BerthSortKey: String, SortKey {
    case number
    case dockName
}

extension Berth: SortableDataModel {
    static func sortMappings(for key: BerthSortKey) -> [SortMapping<Berth>] {
        switch key {
        case .number: [.keyPath(\Berth.$number)]
        case .dockName: [.keyPath(\Berth.$dockName), .keyPath(\Berth.$number)] // stable tiebreak
        }
    }
}

final class CrewMember: DataModel, @unchecked Sendable {
    static let schema = "crew_members"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Siblings(through: DockCrew.self, from: \.$crewMember, to: \.$dock) var docks: [Dock]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class DockCrew: DataModel, @unchecked Sendable {
    static let schema = "dock_crew"
    @ID(key: .id) var id: UUID?
    @Parent(key: "dock_id") var dock: Dock
    @Parent(key: "crew_member_id") var crewMember: CrewMember
    init() {}
    init(dockId: ModelIdType, crewMemberId: ModelIdType) {
        $dock.id = dockId
        $crewMember.id = crewMemberId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - Authorization value fixture (C6 engine tests)

/// A Sendable snapshot of one grant row, composed per the ContainerAuthorization DocC example.
struct TestGrant: ContainerAuthorization {
    let authorizedContainer: ModelIdentity
    let operations: [ContainerOperation]
    let recordTypes: [ModelNamespace]

    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any FOSMVVM.Model.Type,
        in container: ModelIdentity
    ) -> Bool {
        container == authorizedContainer
            && operations.authorizes(operation) // honors the wildcard — never `contains`
            && recordTypes.contains(recordType.modelIdentityNamespace)
    }
}

/// The shipped provider path for engine tests: set the grants in Application storage, register
/// ``TestGrantsProvider``, and every load in a Request reads exactly this set (fetched + memoized
/// once per Request). The C8 audit removed the direct `authorizedBy:` engine entry, so these tests
/// drive the engine through the provider the same way production does.
struct TestGrantsKey: StorageKey {
    typealias Value = [TestGrant]
}

/// Vends whatever grants the test placed in ``TestGrantsKey`` — set the storage before the first
/// authorized load in a Request (the provider is read once per Request, then memoized).
struct TestGrantsProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[TestGrantsKey.self] ?? []
    }
}

// MARK: - Deliberately misconfigured containers (fail-fast tests)

/// Same namespace as Dock (anchored to Dock) — duplicate-registration fixture.
final class RogueDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "rogue_docks"
    static var modelIdentityNamespace: ModelNamespace {
        .init(for: Dock.self)
    }

    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        []
    }

    static var containment: [ContainmentRelation] {
        []
    }

    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// containment built from ANOTHER container's KeyPath — container-type-mismatch fixture.
final class MismatchedDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "mismatched_docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Berth.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Dock.$berths)]
    }

    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// containment ≠ containedRecordTypes — drift fixture, MISSING direction (declared Berth, forgot containment).
final class DriftingDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "drifting_docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Berth.self]
    }

    static var containment: [ContainmentRelation] {
        []
    }

    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// containment ≠ containedRecordTypes — drift fixture, SURPLUS direction (containment declares a type
/// containedRecordTypes omits). Needs its own child relationship so the KeyPath's From is itself.
final class SurplusDock: ContainerDataModel, @unchecked Sendable {
    static let schema = "surplus_docks"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        []
    }

    static var containment: [ContainmentRelation] {
        [.children(\SurplusDock.$boats)]
    }

    @ID(key: .id) var id: UUID?
    @Children(for: \.$surplusDock) var boats: [Boat]
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Child of SurplusDock (exists only so SurplusDock has a relationship of its own).
final class Boat: DataModel, @unchecked Sendable {
    static let schema = "boats"
    @ID(key: .id) var id: UUID?
    @Parent(key: "surplus_dock_id") var surplusDock: SurplusDock
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - Migrations (parents first — FK order)

struct CreatePier: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Pier.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Pier.schema).delete()
    }
}

struct CreateHarbor: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Harbor.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Harbor.schema).delete()
    }
}

struct CreateDock: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Dock.schema).id()
            .field("name", .string, .required)
            .field("harbor_id", .uuid, .required, .references(Harbor.schema, "id"))
            .field("pier_id", .uuid, .required, .references(Pier.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Dock.schema).delete()
    }
}

struct CreatePersonnelFolder: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PersonnelFolder.schema).id()
            .field("name", .string, .required)
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PersonnelFolder.schema).delete()
    }
}

struct CreatePersonnelFile: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PersonnelFile.schema).id()
            .field("name", .string, .required)
            .field("folder_id", .uuid, .required, .references(PersonnelFolder.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PersonnelFile.schema).delete()
    }
}

struct CreateBerth: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Berth.schema).id()
            .field("number", .int, .required)
            .field("dock_name", .string, .required)
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Berth.schema).delete()
    }
}

struct CreateCrewMember: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(CrewMember.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(CrewMember.schema).delete()
    }
}

struct CreateDockCrew: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(DockCrew.schema).id()
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .field("crew_member_id", .uuid, .required, .references(CrewMember.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(DockCrew.schema).delete()
    }
}

// MARK: - Shared seed

/// Seeds the standard graph and returns the two saved docks (ids populated, no relations eager-loaded):
/// dock1 (3 berths, 2 crew) and dock2 (1 berth, 1 shared crew member).
func seedHarbor(on db: any Database) async throws -> (dock1: Dock, dock2: Dock) {
    let harbor = Harbor(name: "Grand Harbor")
    try await harbor.save(on: db)
    let pier = Pier(name: "North Pier")
    try await pier.save(on: db)
    let dock1 = try Dock(name: "Dock 1", pierId: pier.requireId(), harborId: harbor.requireId())
    let dock2 = try Dock(name: "Dock 2", pierId: pier.requireId(), harborId: harbor.requireId())
    try await dock1.save(on: db)
    try await dock2.save(on: db)
    for number in 1...3 {
        try await Berth(number: number, dockName: dock1.name, dockId: dock1.requireId()).save(on: db)
    }
    try await Berth(number: 9, dockName: dock2.name, dockId: dock2.requireId()).save(on: db)
    let alice = CrewMember(name: "Alice")
    let bob = CrewMember(name: "Bob")
    try await alice.save(on: db)
    try await bob.save(on: db)
    try await DockCrew(dockId: dock1.requireId(), crewMemberId: alice.requireId()).save(on: db)
    try await DockCrew(dockId: dock1.requireId(), crewMemberId: bob.requireId()).save(on: db)
    try await DockCrew(dockId: dock2.requireId(), crewMemberId: alice.requireId()).save(on: db)
    return (dock1, dock2)
}

/// Adds every fixture migration in FK order. (PersonnelFolder/PersonnelFile migrations are added
/// only by the suites that register them.)
func addHarborMigrations(_ app: Application) {
    app.migrations.add(CreateHarbor())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
}
