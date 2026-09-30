// PlanExecutorTests.swift
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

// Test-taxonomy discipline: the executor is an internal seam, exercised via
// `@testable import FOSMVVMVapor` (sanctioned — same posture as PlanRegistrationTests).
// Results are asserted at the engine's cache — the executor's one observable output.

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// MARK: - Shared configure/seed plumbing

/// Registers the full container graph the executor descends:
/// Workspace (the top container) → Board → {Card, Member, Checklist (.guards) → ChecklistItem}.
private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier()) // CreateBoard's DDL references piers
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    try app.register(Checklist.self, migration: CreateChecklist())
    app.migrations.add(CreateChecklistItem())
    try app.register(Card.self, migration: CreateCard()) // a leaf within the subject scope must be registered
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useModelAuthorizationProvider(StorageGrantProvider())
}

/// Registers the application scope: the one seeded Workspace. Seeding happens after boot, so the
/// resolver queries at request time (the multi-tenant shape from the resolver's contract).
private func registerApplicationScope(_ app: Application) throws {
    try app.useApplicationScope { req in
        guard let workspace = try await Workspace.query(on: req.db).first() else {
            throw Abort(.internalServerError, reason: "no workspace seeded")
        }
        return try workspace.modelIdentity
    }
}

/// Grants are set per test AFTER seeding (identities exist only then); the provider reads
/// them from Application storage at request time.
private struct ExecutorGrantsKey: StorageKey {
    typealias Value = [TestGrant]
}

/// The subject's identity, when a test vends one (nil by default — the provider's default answer).
private struct ExecutorSubjectKey: StorageKey {
    typealias Value = ModelIdentity
}

private struct StorageGrantProvider: ModelAuthorizationProvider {
    func modelAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[ExecutorGrantsKey.self] ?? []
    }

    func subjectIdentity(for request: Request) async throws -> ModelIdentity? {
        request.application.storage[ExecutorSubjectKey.self]
    }
}

/// A second Workspace holding one Board ("Board 3") — a model the seeded Workspace's grant never
/// reaches, so a grant NAMING it is the only way into the subject scope.
private func seedSecondWorkspaceBoard(on db: any Database) async throws -> Board {
    let workspace = Workspace(name: "Second Workspace")
    try await workspace.save(on: db)
    let pier = try #require(try await Pier.query(on: db).first())
    let board = try Board(name: "Board 3", pierId: pier.requireId(), workspaceId: workspace.requireId())
    try await board.save(on: db)
    return board
}

private func boardNames(_ records: [any FOSMVVM.Model]?) throws -> Set<String> {
    try Set((records ?? []).map { try #require($0 as? Board).name })
}

/// Seeds one folder per board: folder1 (2 files) under dock1, folder2 (1 file) under dock2.
private func seedChecklists(
    on db: any Database,
    dock1: Board,
    dock2: Board
) async throws -> (folder1: Checklist, folder2: Checklist) {
    let folder1 = try Checklist(name: "Folder 1", boardId: dock1.requireId())
    let folder2 = try Checklist(name: "Folder 2", boardId: dock2.requireId())
    try await folder1.save(on: db)
    try await folder2.save(on: db)
    try await ChecklistItem(name: "File A", folderId: folder1.requireId()).save(on: db)
    try await ChecklistItem(name: "File B", folderId: folder1.requireId()).save(on: db)
    try await ChecklistItem(name: "File C", folderId: folder2.requireId()).save(on: db)
    return (folder1, folder2)
}

/// Mints a real Request; requests carrying a query/sort encode them onto the URL through
/// the production encoder (URL.appending(serverRequest:)) — the shipped wire mechanics.
private func makeRequest(on app: Application, url: URL? = nil) -> Vapor.Request {
    Request(
        application: app,
        method: .GET,
        url: URI(string: url?.absoluteString ?? "/"),
        on: app.eventLoopGroup.next()
    )
}

private func requestURL(for request: some ServerRequest) throws -> URL {
    let base = try #require(URL(string: "http://localhost"))
    return try #require(try base.appending(serverRequest: request))
}

/// The cached records for one (container, type) unit — optionally pinned to an anchor
/// (the diamond assertions discriminate entries by it).
private func cachedRecords(
    in req: Vapor.Request,
    of type: any DataModel.Type,
    in container: ModelIdentity,
    anchoredAt anchor: ModelIdentity? = nil
) -> [any DataModel]? {
    req.containerRecordCache.first { entry in
        entry.key.containedType == ObjectIdentifier(type)
            && entry.key.container == container
            && (anchor.map { entry.key.anchor == $0 } ?? true)
    }?.value
}

private func cardNumbers(_ records: [any DataModel]?) throws -> [Int] {
    try (records ?? []).map { try #require($0 as? Card).number }
}

private func fileNames(_ records: [any DataModel]?) throws -> [String] {
    try (records ?? []).map { try #require($0 as? ChecklistItem).name }
}

// MARK: - Factory fixture plumbing (mirrors PlanRegistrationTests' RegistrationFixture)

private struct ExecutorFixtureContext: ViewModelFactoryContext {
    var appVersion: SystemVersion {
        .init(major: 1, minor: 0)
    }
}

private protocol ExecutorFixture: ComposableFactory {
    init()
}

private extension ExecutorFixture {
    var vmId: ViewModelId {
        ViewModelId()
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func model(context: ExecutorFixtureContext) async throws -> Self {
        .init()
    }
}

/// The query vending a request-scoped root identity (usually a Board's).
private struct ExecScopedQuery: ScopedQuery {
    let scopeIdentity: ModelIdentity
}

/// Test 10's query: roots the tree AND declares the window axis.
private struct PagedCardQuery: ScopedQuery, PaginatedQuery {
    let scopeIdentity: ModelIdentity
    let pagination: Pagination
}

// MARK: - Test 8: the forest (a .request tree + an .application tree, one request)

private struct ApplicationBoardListVM: ExecutorFixture {
    static let boards = Board.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        boards
    }
}

private struct ForestPageVM: ExecutorFixture, RequestableViewModel {
    typealias Request = ForestPageRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }

    static var children: [ComposedChild] {
        [.child(ApplicationBoardListVM.self, within: .application)]
    }
}

private final class ForestPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecScopedQuery?
    var responseBody: ForestPageVM?

    init(query: ExecScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ForestPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Test 9: three-level .inherits descent under one top-container grant

private struct ThreeLevelVM: ExecutorFixture, RequestableViewModel {
    typealias Request = ThreeLevelRequest

    static let cards = Card.loadingPlan(.read, within: .application, via: Board.self)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class ThreeLevelRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: ThreeLevelVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ThreeLevelVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - Test 9: .guards — files load only with a grant anchored on the folder

private struct GuardedFilesVM: ExecutorFixture, RequestableViewModel {
    typealias Request = GuardedFilesRequest

    static let checklistItems = ChecklistItem.loadingPlan(.read, within: .application, via: Board.self, Checklist.self)

    static var loadingPlans: LoadingPlans {
        checklistItems
    }
}

private final class GuardedFilesRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: GuardedFilesVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: GuardedFilesVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - Test 9: anchor-conflict diamond — same (container, type) under two anchors

private struct ApplicationCardListVM: ExecutorFixture {
    static let cards = Card.loadingPlan(.read, within: .parent, via: Board.self)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private struct DiamondPageVM: ExecutorFixture, RequestableViewModel {
    typealias Request = DiamondPageRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }

    static var children: [ComposedChild] {
        [.child(ApplicationCardListVM.self, within: .application)]
    }
}

private final class DiamondPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecScopedQuery?
    var responseBody: DiamondPageVM?

    init(query: ExecScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DiamondPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Test 10: .refinedByRequest — sort/window on exactly the marked tuple

private struct RefinedCardListVM: ExecutorFixture, RequestableViewModel {
    typealias Request = RefinedCardListRequest

    static let cards = Card.loadingPlan(.read, within: .parent).refinedByRequest
    static let members = Member.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
        members
    }
}

private final class RefinedCardListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = PagedCardQuery
    typealias ResponseError = EmptyError
    typealias Sort = SortCriteria<CardSortKey>

    let id: String
    let query: PagedCardQuery?
    let sort: SortCriteria<CardSortKey>?
    var responseBody: RefinedCardListVM?

    init(query: PagedCardQuery? = nil, sort: SortCriteria<CardSortKey>? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: RefinedCardListVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.sort = sort
        self.responseBody = responseBody
    }
}

// MARK: - Test 11: the supplemental seam

private enum SupplementalHookError: Error {
    case declarativeTupleNotCached
    case deliberate
}

private struct SupplementalPageVM: ExecutorFixture, RequestableViewModel {
    typealias Request = SupplementalPageRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

/// The hook proves its post-declarative ordering structurally: it reads the declarative
/// card tuple FROM THE CACHE (throwing if absent) and loads members through the
/// provider-driven entry using that cached tuple's container.
extension SupplementalPageVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        guard let cardEntry = request.containerRecordCache.first(where: {
            $0.key.containedType == ObjectIdentifier(Card.self) && !$0.value.isEmpty
        }) else {
            throw SupplementalHookError.declarativeTupleNotCached
        }
        _ = try await request.authorizedRecords(
            of: cardEntry.key.container,
            containing: Member.self,
            for: .readRecords
        )
    }
}

private final class SupplementalPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecScopedQuery?
    var responseBody: SupplementalPageVM?

    init(query: ExecScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SupplementalPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

private struct ThrowingSupplementalVM: ExecutorFixture, RequestableViewModel {
    typealias Request = ThrowingSupplementalRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

extension ThrowingSupplementalVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        throw SupplementalHookError.deliberate
    }
}

private final class ThrowingSupplementalRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecScopedQuery?
    var responseBody: ThrowingSupplementalVM?

    init(query: ExecScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ThrowingSupplementalVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Obligation 1: composable ResponseBody + nil stored plan is a configuration error

/// A composable ResponseBody that is deliberately NEVER registered — so no plan is ever
/// derived for its request. The executor must treat composable+nil-plan as a typed
/// configuration error, never "legacy, skip".
private struct UnregisteredPageVM: ExecutorFixture, RequestableViewModel {
    typealias Request = UnregisteredPageRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class UnregisteredPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecScopedQuery?
    var responseBody: UnregisteredPageVM?

    init(query: ExecScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: UnregisteredPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Obligation 2: misrooted query — root descriptor must contain the first hop

private struct MisrootedVM: ExecutorFixture, RequestableViewModel {
    typealias Request = MisrootedRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class MisrootedRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecScopedQuery?
    var responseBody: MisrootedVM?

    init(query: ExecScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: MisrootedVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Tests (spec tests 8–11 + 13)

// MARK: - The subject scope (D5): bound from the grants, no container named

private struct SubjectBoardsVM: ExecutorFixture, RequestableViewModel {
    typealias Request = SubjectBoardsRequest

    static let boards = Board.loadingPlan(.read, within: .subject)

    static var loadingPlans: LoadingPlans {
        boards
    }
}

private final class SubjectBoardsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectBoardsVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SubjectBoardsVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

private struct SubjectCardsViaBoardVM: ExecutorFixture, RequestableViewModel {
    typealias Request = SubjectCardsViaBoardRequest

    static let cards = Card.loadingPlan(.read, within: .subject, via: Board.self)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class SubjectCardsViaBoardRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectCardsViaBoardVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SubjectCardsViaBoardVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

/// A window with no container to name: the subject scope needs no ScopedQuery.
private struct SubjectPagedQuery: PaginatedQuery {
    let pagination: Pagination
}

private struct SubjectRefinedCardsVM: ExecutorFixture, RequestableViewModel {
    typealias Request = SubjectRefinedCardsRequest

    static let cards = Card.loadingPlan(.read, within: .subject).refinedByRequest

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class SubjectRefinedCardsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = SubjectPagedQuery
    typealias ResponseError = EmptyError
    typealias Sort = SortCriteria<CardSortKey>

    let id: String
    let query: SubjectPagedQuery?
    let sort: SortCriteria<CardSortKey>?
    var responseBody: SubjectRefinedCardsVM?

    init(query: SubjectPagedQuery? = nil, sort: SortCriteria<CardSortKey>? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SubjectRefinedCardsVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.sort = sort
        self.responseBody = responseBody
    }
}

@Suite("RecordLoadPlan execution through the authorized engine (C7)")
struct PlanExecutorTests {
    /// Spec test 8 — the forest: a `.request` tree and an `.application` tree execute
    /// in ONE request; both trees' records land in the engine's cache.
    @Test func forestLoadsBothTreesIntoTheCache() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: ForestPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedModel: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace]
                )
            ]

            let vmRequest = try ForestPageRequest(query: .init(scopeIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            let cards = try cachedRecords(in: req, of: Card.self, in: dock1.modelIdentity)
            #expect(try cardNumbers(cards).sorted() == [1, 2, 3])

            let boards = try cachedRecords(in: req, of: Board.self, in: workspace.modelIdentity)
            #expect(boards?.count == 2)
        }
    }

    /// Spec test 9 — `.inherits` descent: ONE grant on the workspace (the top container) covering Board and
    /// Card loads the whole three-level tree (workspace → boards → cards, all boards' cards).
    @Test func applicationGrantDescendsThreeLevelsUnderInherits() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: ThreeLevelRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            let workspaceIdentity = try workspace.modelIdentity
            app.storage[ExecutorGrantsKey.self] = [
                TestGrant(
                    authorizedModel: workspaceIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace, Card.modelIdentityNamespace]
                )
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: ThreeLevelRequest())

            let boards = cachedRecords(in: req, of: Board.self, in: workspaceIdentity)
            #expect(boards?.count == 2)

            // Every level's grant check ran against the ROOT anchor (workspace), never the board.
            let dock1Cards = try cachedRecords(
                in: req, of: Card.self, in: dock1.modelIdentity, anchoredAt: workspaceIdentity
            )
            let dock2Cards = try cachedRecords(
                in: req, of: Card.self, in: dock2.modelIdentity, anchoredAt: workspaceIdentity
            )
            #expect(try cardNumbers(dock1Cards).sorted() == [1, 2, 3])
            #expect(try cardNumbers(dock2Cards) == [9])
        }
    }

    /// Spec test 9 — `.guards` denial: a top-container grant covering ChecklistItem does NOT descend
    /// past the folder guard; the folders themselves (above the guard) still load.
    @Test func topContainerGrantDoesNotDescendPastTheGuard() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: GuardedFilesRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let (folder1, folder2) = try await seedChecklists(on: db, dock1: dock1, dock2: dock2)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [
                        Board.modelIdentityNamespace,
                        Checklist.modelIdentityNamespace,
                        ChecklistItem.modelIdentityNamespace // deliberately covered — must not descend
                    ]
                )
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: GuardedFilesRequest())

            let folders = try cachedRecords(in: req, of: Checklist.self, in: dock1.modelIdentity)
            #expect(folders?.count == 1)

            let files1 = try cachedRecords(in: req, of: ChecklistItem.self, in: folder1.modelIdentity)
            let files2 = try cachedRecords(in: req, of: ChecklistItem.self, in: folder2.modelIdentity)
            #expect(files1?.isEmpty == true)
            #expect(files2?.isEmpty == true)
        }
    }

    /// Spec test 9 — `.guards` allow: a grant anchored on the FOLDER instance loads that
    /// folder's files; the other folder's subtree stays empty (per-branch anchoring).
    @Test func folderAnchoredGrantLoadsExactlyThatSubtree() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: GuardedFilesRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let (folder1, folder2) = try await seedChecklists(on: db, dock1: dock1, dock2: dock2)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace, Checklist.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedModel: folder1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [ChecklistItem.modelIdentityNamespace]
                )
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: GuardedFilesRequest())

            // The file loads' cache entries are anchored at each branch's own folder.
            let files1 = try cachedRecords(
                in: req, of: ChecklistItem.self, in: folder1.modelIdentity, anchoredAt: folder1.modelIdentity
            )
            let files2 = try cachedRecords(in: req, of: ChecklistItem.self, in: folder2.modelIdentity)
            #expect(try fileNames(files1).sorted() == ["File A", "File B"])
            #expect(files2?.isEmpty == true)
        }
    }

    /// Spec test 9 — anchor-conflict diamond: the SAME (container, type) reached through the
    /// request scope (anchor = board) and through the application scope (anchor = workspace) keys TWO cache
    /// entries with independent outcomes — one authorized, one empty.
    @Test func anchorConflictDiamondKeysIndependentEntries() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: DiamondPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            let workspaceIdentity = try workspace.modelIdentity
            // Cards granted on dock1 ONLY — the workspace grant covers boards, not cards.
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedModel: workspaceIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace]
                )
            ]

            let vmRequest = try DiamondPageRequest(query: .init(scopeIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            let boardAnchored = try cachedRecords(
                in: req, of: Card.self, in: dock1.modelIdentity, anchoredAt: dock1.modelIdentity
            )
            let workspaceAnchored = try cachedRecords(
                in: req, of: Card.self, in: dock1.modelIdentity, anchoredAt: workspaceIdentity
            )
            #expect(try cardNumbers(boardAnchored).sorted() == [1, 2, 3])
            #expect(workspaceAnchored?.isEmpty == true)
        }
    }

    /// Spec test 10 — `.refinedByRequest`: the request's sort + window land on exactly the
    /// marked tuple (cards, descending, first 2); the unmarked tuple (members) stays unrefined.
    @Test func requestRefinementAppliesToExactlyTheMarkedTuple() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: RefinedCardListRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let dock1Identity = try dock1.modelIdentity
            app.storage[ExecutorGrantsKey.self] = [
                TestGrant(
                    authorizedModel: dock1Identity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace, Member.modelIdentityNamespace]
                )
            ]

            let request = RefinedCardListRequest(
                query: .init(scopeIdentity: dock1Identity, pagination: .init(startIndex: 0, maxResults: 2)),
                sort: SortCriteria([.init(key: CardSortKey.number, direction: .descending)])
            )
            let req = try makeRequest(on: app, url: requestURL(for: request))
            try await req.executeRecordLoadPlan(for: request)

            let cards = cachedRecords(in: req, of: Card.self, in: dock1Identity)
            #expect(try cardNumbers(cards) == [3, 2]) // sorted desc, windowed to 2

            let members = cachedRecords(in: req, of: Member.self, in: dock1Identity)
            #expect(members?.count == 2) // full set — no window leaked onto the unmarked tuple

            let membersKey = req.containerRecordCache.keys.first {
                $0.containedType == ObjectIdentifier(Member.self)
            }
            #expect(membersKey?.refinement == ContainmentQueryRefinement.none)
        }
    }

    /// Spec test 11 — supplemental seam: the conformer's hook runs AFTER the declarative
    /// tuples (it reads the cached card tuple; a miss throws) and loads extra records
    /// through the provider-driven entry.
    @Test func supplementalHookRunsPostDeclarative() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SupplementalPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let dock1Identity = try dock1.modelIdentity
            app.storage[ExecutorGrantsKey.self] = [
                TestGrant(
                    authorizedModel: dock1Identity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace, Member.modelIdentityNamespace]
                )
            ]

            let vmRequest = SupplementalPageRequest(query: .init(scopeIdentity: dock1Identity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            // The hook completed (no declarativeTupleNotCached throw) and its load deposited.
            let members = cachedRecords(in: req, of: Member.self, in: dock1Identity)
            #expect(members?.count == 2)
        }
    }

    /// Spec test 11 — a throwing supplemental hook fails the request (propagates, never
    /// swallow-to-empty).
    @Test func throwingSupplementalHookFailsExecution() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: ThrowingSupplementalRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let vmRequest = try ThrowingSupplementalRequest(query: .init(scopeIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            await #expect(throws: SupplementalHookError.self) {
                try await req.executeRecordLoadPlan(for: vmRequest)
            }
        }
    }

    /// Spec test 13 — the level-write safety pin for the v1 concurrency resolution
    /// (SEQUENTIAL engine calls; see the executor's deferred-breadth-concurrency note):
    /// every sibling deposit at a multi-instance level is present (no lost writes), and
    /// two executions of the same plan produce identical cache shapes and orderings.
    @Test func sequentialExecutionDepositsAllSiblingsDeterministically() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: ThreeLevelRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace, Card.modelIdentityNamespace]
                )
            ]

            let first = makeRequest(on: app)
            try await first.executeRecordLoadPlan(for: ThreeLevelRequest())
            let second = makeRequest(on: app)
            try await second.executeRecordLoadPlan(for: ThreeLevelRequest())

            // All sibling deposits present: one board entry + one card entry per board.
            #expect(first.containerRecordCache.count == 3)
            for board in [dock1, dock2] {
                let firstRun = try cachedRecords(in: first, of: Card.self, in: board.modelIdentity)
                let secondRun = try cachedRecords(in: second, of: Card.self, in: board.modelIdentity)
                #expect(firstRun != nil)
                // Determinism: both executions produced the same records in the same order.
                #expect(try cardNumbers(firstRun) == cardNumbers(secondRun))
            }
            #expect(Set(first.containerRecordCache.keys) == Set(second.containerRecordCache.keys))
        }
    }

    /// A legacy (non-composable) ResponseBody is a no-op: nothing loads, nothing throws.
    @Test func legacyResponseBodyIsANoOp() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
        } _: { app, _ in
            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: TestViewModelRequest())
            #expect(req.containerRecordCache.isEmpty)
        }
    }

    /// Obligation 1 — a COMPOSABLE ResponseBody whose request was never registered (so no plan
    /// was ever derived) is a typed configuration error, never "legacy, skip". Registration is
    /// Application-only now, so a nil plan for a composable body means never-registered.
    @Test func composableResponseBodyWithNilPlanThrowsTyped() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            // UnregisteredPageRequest is deliberately NOT registered — no plan is derived.
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let vmRequest = try UnregisteredPageRequest(query: .init(scopeIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            do {
                try await req.executeRecordLoadPlan(for: vmRequest)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }

    /// Obligation 2 — a ScopedQuery vending an identity whose registered descriptor does not
    /// declare containment of the tuple's first hop throws typed: the misrooted-query
    /// silent-empty mode is dead. (Workspace is registered but contains Board, never Card.)
    @Test func misrootedQueryAgainstRegisteredContainerThrowsTyped() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: MisrootedRequest.self)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            let vmRequest = try MisrootedRequest(query: .init(scopeIdentity: workspace.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            do {
                try await req.executeRecordLoadPlan(for: vmRequest)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }

    /// Spec §9 group 14 — application-scope publicization: a plan within `.application` is usable end-to-end through
    /// the now-PUBLIC `useApplicationScope` registration (`forestLoadsBothTreesIntoTheCache`
    /// and `applicationGrantDescendsThreeLevelsUnderInherits` exercise the happy path). Here the negative:
    /// an application scope that cannot resolve at request time fails the request — its error
    /// propagates with the existing semantics (no silent empty). The resolver queries for a seeded
    /// workspace; none is seeded, so it throws.
    @Test func unresolvedApplicationScopeFailsTheRequest() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApplicationScope(app)
            try app.registerRecordLoadPlan(for: ThreeLevelRequest.self)
        } _: { app, _ in
            // No workspace seeded ⇒ the application scope throws when the plan resolves it.
            let req = makeRequest(on: app)
            await #expect(throws: (any Error).self) {
                try await req.executeRecordLoadPlan(for: ThreeLevelRequest())
            }
        }
    }

    /// Obligation 2 — a ScopedQuery vending an identity of an UNREGISTERED type (Pier is a
    /// DataModel, never a registered container) throws typed at root binding.
    @Test func misrootedQueryAgainstUnregisteredTypeThrowsTyped() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: MisrootedRequest.self)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let pier = try #require(try await Pier.query(on: db).first())
            let vmRequest = try MisrootedRequest(query: .init(scopeIdentity: pier.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            do {
                try await req.executeRecordLoadPlan(for: vmRequest)
                Issue.record("expected ContainmentError.unregisteredNamespace")
            } catch let error as ContainmentError {
                guard case .unregisteredNamespace = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }

    // MARK: - The subject scope (D5)

    /// The subject scope binds the union: the Boards inside the granted Workspace (extension)
    /// plus the Board a grant names with `.read` (model authority) — one query, deposited under
    /// the subject key, no per-container load; every bound identity registers.
    @Test func subjectScopeBindsTheUnionAndRegistersEveryBoundModel() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectBoardsRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            let dock3 = try await seedSecondWorkspaceBoard(on: db)
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace]
                ),
                TestGrant(authorizedModel: dock3.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectBoardsRequest())

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            #expect(try boardNames(req.recordsByTuple()[tuple]) == ["Board 1", "Board 2", "Board 3"])
            #expect(req.containerRecordCache.isEmpty) // the union loaded through ONE subject query
            #expect(try req.registrationSet == Set([dock1.modelIdentity, dock2.modelIdentity, dock3.modelIdentity]))
        }
    }

    /// A subject with no grants loads EMPTY — the tuple still deposits its (empty) entry, so a
    /// projection reads `[]` rather than throwing unplanned — and registers nothing.
    @Test func subjectWithNoGrantsLoadsEmptyAndRegistersNothing() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectBoardsRequest.self)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            app.storage[ExecutorGrantsKey.self] = []

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectBoardsRequest())

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            let boards = try #require(req.recordsByTuple()[tuple])
            #expect(boards.isEmpty)
            #expect(req.registrationSet.isEmpty)
        }
    }

    /// The request's axes refine the UNION: cards of two granted Boards, sorted descending and
    /// windowed to two, page as one set; the total is the whole union's count.
    @Test func subjectScopeRefinementAppliesAcrossTheUnion() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectRefinedCardsRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(authorizedModel: dock1.modelIdentity, operations: [.readRecords], recordTypes: [Card.modelIdentityNamespace]),
                TestGrant(authorizedModel: dock2.modelIdentity, operations: [.readRecords], recordTypes: [Card.modelIdentityNamespace])
            ]

            let request = SubjectRefinedCardsRequest(
                query: .init(pagination: .init(startIndex: 0, maxResults: 2)),
                sort: SortCriteria([.init(key: CardSortKey.number, direction: .descending)])
            )
            let req = try makeRequest(on: app, url: requestURL(for: request))
            try await req.executeRecordLoadPlan(for: request)

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            let numbers = try (req.recordsByTuple()[tuple] ?? []).map { try #require($0 as? Card).number }
            #expect(numbers == [9, 3])
            #expect(req.countsByTuple()[tuple] == 4)
        }
    }

    /// `via:` descends from the bound set, anchored per bound model: the Workspace grant binds
    /// both Boards; only the Board holding a Card grant loads its Cards, the other loads empty.
    @Test func viaDescendsFromEachBoundModelAnchoredThere() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectCardsViaBoardRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            let dock1Identity = try dock1.modelIdentity
            let dock2Identity = try dock2.modelIdentity
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(authorizedModel: workspace.modelIdentity, operations: [.readRecords], recordTypes: [Board.modelIdentityNamespace]),
                TestGrant(authorizedModel: dock1Identity, operations: [.readRecords], recordTypes: [Card.modelIdentityNamespace])
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectCardsViaBoardRequest())

            let dock1Cards = cachedRecords(in: req, of: Card.self, in: dock1Identity, anchoredAt: dock1Identity)
            #expect(try cardNumbers(dock1Cards).sorted() == [1, 2, 3])
            let dock2Cards = try #require(cachedRecords(in: req, of: Card.self, in: dock2Identity, anchoredAt: dock2Identity))
            #expect(dock2Cards.isEmpty) // bound, descended, denied at its own anchor

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            let projected = try (req.recordsByTuple()[tuple] ?? []).map { try #require($0 as? Card).number }
            #expect(projected.sorted() == [1, 2, 3])
            #expect(req.registrationSet == [dock1Identity, dock2Identity])
        }
    }

    /// When the provider vends the subject's identity, the response registers it beside the
    /// bound models — a grant write on a subject-contained grant model then reaches this list.
    @Test func subjectIdentityRegistersWhenVended() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectBoardsRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let alice = try #require(try await Member.query(on: db).filter(\.$name == "Alice").first())
            let subject = try alice.modelIdentity
            app.storage[ExecutorSubjectKey.self] = subject
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(authorizedModel: dock1.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectBoardsRequest())

            #expect(try req.registrationSet == Set([subject, dock1.modelIdentity]))
        }
    }

    /// Exceeding `maxRegistrationsWarningThreshold` warns but NEVER drops a registration —
    /// threshold 1, three bound Boards, all three registered. (Warning emission is observability,
    /// not a public contract — documented rather than logger-captured.)
    @Test func registrationThresholdWarnsButRegistersEverything() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectBoardsRequest.self)
        } _: { app, db in
            app.maxRegistrationsWarningThreshold = 1
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let dock3 = try await seedSecondWorkspaceBoard(on: db)
            app.storage[ExecutorGrantsKey.self] = try [dock1, dock2, dock3].map {
                try TestGrant(authorizedModel: $0.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            }

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectBoardsRequest())

            #expect(req.registrationSet.count == 3)
        }
    }
}
