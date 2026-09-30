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

import Fluent // app.migrations (addWorkspaceMigrations) lives in vapor/fluent
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

/// The application's top container — every Board belongs to a Workspace; plans within
/// `.application` resolve here.
final class Workspace: ContainerDataModel, @unchecked Sendable {
    static let schema = "workspaces"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Board.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Workspace.$boards)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$workspace) var boards: [Board]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Board: ContainerDataModel, @unchecked Sendable {
    static let schema = "boards"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Card.self, Member.self, Pier.self, Checklist.self]
    }

    static var containment: [ContainmentRelation] {
        [
            .children(\Board.$cards),
            .siblings(\Board.$members),
            .parent(\Board.$pier),
            .children(\Board.$checklists)
        ]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "workspace_id") var workspace: Workspace
    @Parent(key: "pier_id") var pier: Pier
    @Children(for: \.$board) var cards: [Card]
    @Children(for: \.$board) var checklists: [Checklist]
    @Siblings(through: BoardMember.self, from: \.$board, to: \.$member) var members: [Member]
    init() {}
    init(name: String, pierId: ModelIdType, workspaceId: ModelIdType) {
        self.name = name
        $pier.id = pierId
        $workspace.id = workspaceId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// A `.guards` container under Board — authority granted above stops here; its records need
/// authority anchored at the folder itself. Registered only by the suites that exercise it.
final class Checklist: ContainerDataModel, @unchecked Sendable {
    static let schema = "checklists"
    static var authorityFlow: AuthorityFlow {
        .guards
    }

    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [ChecklistItem.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Checklist.$files)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "board_id") var board: Board
    @Children(for: \.$folder) var files: [ChecklistItem]
    init() {}
    init(name: String, boardId: ModelIdType) {
        self.name = name
        $board.id = boardId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Child of Checklist — reachable only through the guard.
final class ChecklistItem: DataModel, @unchecked Sendable {
    static let schema = "checklist_items"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Parent(key: "folder_id") var folder: Checklist
    init() {}
    init(name: String, folderId: ModelIdType) {
        self.name = name
        $folder.id = folderId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Card: DataModel, @unchecked Sendable {
    static let schema = "cards"
    @ID(key: .id) var id: UUID?
    @Field(key: "number") var number: Int
    @Field(key: "board_name") var boardName: String // denormalized — the composite-sort fixture column
    @Parent(key: "board_id") var board: Board
    init() {}
    init(number: Int, boardName: String, boardId: ModelIdType) {
        self.number = number
        self.boardName = boardName
        $board.id = boardId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Card's ONE published sort vocabulary (test-side stand-in for a shared-module enum).
enum CardSortKey: String, SortKey {
    case number
    case boardName
}

extension Card: SortableDataModel {
    static func sortMappings(for key: CardSortKey) -> [SortMapping<Card>] {
        switch key {
        case .number: [.keyPath(\Card.$number)]
        case .boardName: [.keyPath(\Card.$boardName), .keyPath(\Card.$number)] // stable tiebreak
        }
    }
}

/// The request query Card reads as a filter (test-side stand-in for a shared-module type). A query
/// IS a filter — the model translates it to Fluent below.
struct CardSearchQuery: ServerRequestQuery {
    var boardName: String?
}

/// A query type Card does NOT read — the wrong-query-type fixture (mirror of OtherSortKey).
struct OtherQuery: ServerRequestQuery {
    var value: Int
}

extension Card: FilterableDataModel {
    static func apply(filter: CardSearchQuery, to query: QueryBuilder<Card>) -> QueryBuilder<Card> {
        guard let boardName = filter.boardName else { return query }
        return query.filter(\.$boardName == boardName)
    }
}

final class Member: DataModel, @unchecked Sendable {
    static let schema = "members"
    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Siblings(through: BoardMember.self, from: \.$member, to: \.$board) var boards: [Board]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class BoardMember: DataModel, @unchecked Sendable {
    static let schema = "board_member"
    @ID(key: .id) var id: UUID?
    @Parent(key: "board_id") var board: Board
    @Parent(key: "member_id") var member: Member
    init() {}
    init(boardId: ModelIdType, memberId: ModelIdType) {
        $board.id = boardId
        $member.id = memberId
    }

    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - Authorization value fixture (C6 engine tests)

/// A Sendable snapshot of one grant row, composed per the ModelAuthorization DocC example.
struct TestGrant: ModelAuthorization {
    let authorizedModel: ModelIdentity
    let operations: [ContainerOperation]
    let recordTypes: [ModelNamespace]
    /// What the grant allows on the named model itself; empty by default, so every existing
    /// fixture keeps the deny default.
    var modelOperations: [ModelOperation] = []

    func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
        model == authorizedModel && modelOperations.authorizes(operation)
    }

    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any FOSMVVM.Model.Type,
        in container: ModelIdentity
    ) -> Bool {
        container == authorizedModel
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
struct TestGrantsProvider: ModelAuthorizationProvider {
    func modelAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[TestGrantsKey.self] ?? []
    }
}

// MARK: - Deliberately misconfigured containers (fail-fast tests)

/// Same namespace as Board (anchored to Board) — duplicate-registration fixture.
final class RogueBoard: ContainerDataModel, @unchecked Sendable {
    static let schema = "rogue_boards"
    static var modelIdentityNamespace: ModelNamespace {
        .init(for: Board.self)
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
final class MismatchedBoard: ContainerDataModel, @unchecked Sendable {
    static let schema = "mismatched_boards"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Card.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Board.$cards)]
    }

    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// containment ≠ containedRecordTypes — drift fixture, MISSING direction (declared Card, forgot containment).
final class DriftingBoard: ContainerDataModel, @unchecked Sendable {
    static let schema = "drifting_boards"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Card.self]
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
final class SpareBoard: ContainerDataModel, @unchecked Sendable {
    static let schema = "surplus_boards"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        []
    }

    static var containment: [ContainmentRelation] {
        [.children(\SpareBoard.$boats)]
    }

    @ID(key: .id) var id: UUID?
    @Children(for: \.$spareBoard) var boats: [Boat]
    init() {}
    func validate(fields: [any FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

/// Child of SpareBoard (exists only so SpareBoard has a relationship of its own).
final class Boat: DataModel, @unchecked Sendable {
    static let schema = "boats"
    @ID(key: .id) var id: UUID?
    @Parent(key: "surplus_dock_id") var spareBoard: SpareBoard
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

struct CreateWorkspace: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Workspace.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Workspace.schema).delete()
    }
}

struct CreateBoard: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Board.schema).id()
            .field("name", .string, .required)
            .field("workspace_id", .uuid, .required, .references(Workspace.schema, "id"))
            .field("pier_id", .uuid, .required, .references(Pier.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Board.schema).delete()
    }
}

struct CreateChecklist: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Checklist.schema).id()
            .field("name", .string, .required)
            .field("board_id", .uuid, .required, .references(Board.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Checklist.schema).delete()
    }
}

struct CreateChecklistItem: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(ChecklistItem.schema).id()
            .field("name", .string, .required)
            .field("folder_id", .uuid, .required, .references(Checklist.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ChecklistItem.schema).delete()
    }
}

struct CreateCard: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Card.schema).id()
            .field("number", .int, .required)
            .field("board_name", .string, .required)
            .field("board_id", .uuid, .required, .references(Board.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Card.schema).delete()
    }
}

struct CreateMember: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Member.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Member.schema).delete()
    }
}

struct CreateBoardMember: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(BoardMember.schema).id()
            .field("board_id", .uuid, .required, .references(Board.schema, "id"))
            .field("member_id", .uuid, .required, .references(Member.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BoardMember.schema).delete()
    }
}

// MARK: - Shared seed

/// Seeds the standard graph and returns the two saved boards (ids populated, no relations eager-loaded):
/// dock1 (3 cards, 2 members) and dock2 (1 card, 1 shared members member).
func seedWorkspace(on db: any Database) async throws -> (dock1: Board, dock2: Board) {
    let workspace = Workspace(name: "Grand Workspace")
    try await workspace.save(on: db)
    let pier = Pier(name: "North Pier")
    try await pier.save(on: db)
    let dock1 = try Board(name: "Board 1", pierId: pier.requireId(), workspaceId: workspace.requireId())
    let dock2 = try Board(name: "Board 2", pierId: pier.requireId(), workspaceId: workspace.requireId())
    try await dock1.save(on: db)
    try await dock2.save(on: db)
    for number in 1...3 {
        try await Card(number: number, boardName: dock1.name, boardId: dock1.requireId()).save(on: db)
    }
    try await Card(number: 9, boardName: dock2.name, boardId: dock2.requireId()).save(on: db)
    let alice = Member(name: "Alice")
    let bob = Member(name: "Bob")
    try await alice.save(on: db)
    try await bob.save(on: db)
    try await BoardMember(boardId: dock1.requireId(), memberId: alice.requireId()).save(on: db)
    try await BoardMember(boardId: dock1.requireId(), memberId: bob.requireId()).save(on: db)
    try await BoardMember(boardId: dock2.requireId(), memberId: alice.requireId()).save(on: db)
    return (dock1, dock2)
}

/// Adds every fixture migration in FK order. (Checklist/ChecklistItem migrations are added
/// only by the suites that register them.)
func addWorkspaceMigrations(_ app: Application) {
    app.migrations.add(CreateWorkspace())
    app.migrations.add(CreatePier())
    app.migrations.add(CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
}
