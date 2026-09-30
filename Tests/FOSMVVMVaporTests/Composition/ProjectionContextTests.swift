// ProjectionContextTests.swift
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

// Test-taxonomy discipline: ProjectionContext + its records(_:) lookup are internal-facing
// seams, exercised via `@testable import FOSMVVMVapor`. Records land in the engine's cache
// (the executor's observable output); the projection reads them back by declared handle.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// MARK: - Configure/seed plumbing (Workspace → Board → {Card, Member})

private struct GrantsKey: StorageKey {
    typealias Value = [TestGrant]
}

private struct GrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[GrantsKey.self] ?? []
    }
}

private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier()) // CreateBoard's DDL references piers
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useContainerAuthorizationProvider(GrantProvider())
}

private func registerApexResolver(_ app: Application) throws {
    try app.useApexContainerResolver { req in
        guard let workspace = try await Workspace.query(on: req.db).first() else {
            throw Abort(.internalServerError, reason: "no workspace seeded")
        }
        return try workspace.modelIdentity
    }
}

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

/// Grants dock1 read of both Card and Member — the two handles the projection reads.
private func grantBoardReads(_ app: Application, board: Board) throws {
    app.storage[GrantsKey.self] = try [
        TestGrant(
            authorizedContainer: board.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Card.modelIdentityNamespace, Member.modelIdentityNamespace]
        )
    ]
}

/// Builds the context the way `serve` does: after the executor ran on `req`.
private func makeContext<SR: ServerRequest>(
    for vmRequest: SR,
    on req: Vapor.Request
) -> ProjectionContext<SR, Void> {
    guard let plan = req.application.recordLoadPlan(for: SR.self) else {
        return .init(vmRequest: vmRequest, appState: (), dependencySink: { _ in })
    }
    return .init(vmRequest: vmRequest, appState: (), plan: plan, recordsByTuple: req.recordsByTuple(), dependencySink: { _ in })
}

// MARK: - Fixtures

private struct BoardRootedQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

/// A composed child that declares its OWN handle — the parent reads it to compose members.
private struct MembersListVM: ComposableFactory {
    static let members = LoadRequirement.read(Member.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [members]
    }
}

/// A composable page: its own Card handle + a composed MembersListVM child (whose Member
/// handle the page also reads). `body` fails loudly if either handle is invisible — proof the
/// load phase ran before projection.
private struct BoardPageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = BoardPageRequest

    static let cards = LoadRequirement.read(Card.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [cards]
    }

    static var children: [ComposedChild] {
        [.child(MembersListVM.self)]
    }

    var vmId = ViewModelId()
    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        let cards = try context.records(Self.cards) //           own handle
        let members = try context.records(MembersListVM.members) //          a child's handle
        guard cards.count == 3, members.count == 2 else {
            throw Abort(.internalServerError, reason: "projection saw \(cards.count) cards, \(members.count) members")
        }
        return .init()
    }
}

private final class BoardPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardRootedQuery?
    var responseBody: BoardPageVM?

    init(query: BoardRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: BoardPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Blend-contract fixtures: two same-typed Card loads in ONE plan

/// Two legitimate, distinct Card loads:
///  - boardCards: THIS board's cards (query root, direct)
///  - workspaceCards: ALL the workspace's cards (apex root via Board)
/// Each handle must read back exactly its OWN tuple's records — never the union.
private struct TwoCardLoadsVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = TwoCardLoadsRequest

    static let boardCards = LoadRequirement.read(Card.self, in: .parentRoot)
    static let workspaceCards = LoadRequirement.read(Card.self, in: .newRoot(.apex), via: Board.self)

    static var dataRequirements: [any DataRequirement] {
        [boardCards, workspaceCards]
    }

    var vmId = ViewModelId()
    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }
}

private final class TwoCardLoadsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardRootedQuery?
    var responseBody: TwoCardLoadsVM?

    init(query: BoardRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: TwoCardLoadsVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - C-2 regression fixtures: a bare child handle behind a prefix-substituted path

/// The child declares its Card load BARE (`.parentRoot`, no `via:`) — composition supplies
/// the Board hop, so its tuple's absolute path is prefix-substituted to [Board].
private struct BareCardListVM: ComposableFactory {
    static let cards = LoadRequirement.read(Card.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [cards]
    }
}

/// Workspace-rooted parent: its own Board load + the bare-handled child composed via Board.
private struct WorkspacePageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = WorkspacePageRequest

    static let boards = LoadRequirement.read(Board.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [boards]
    }

    static var children: [ComposedChild] {
        [.child(BareCardListVM.self, via: Board.self)]
    }

    var vmId = ViewModelId()
    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }
}

private final class WorkspacePageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardRootedQuery?
    var responseBody: WorkspacePageVM?

    init(query: BoardRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: WorkspacePageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Genuine-ambiguity fixtures: the SAME child composed twice

private struct TwiceChildVM: ComposableFactory {
    static let cards = LoadRequirement.read(Card.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [cards]
    }
}

/// Composes the SAME child on two distinct paths — the one declaration walks to TWO tuples,
/// so its handle is genuinely ambiguous.
private struct TwiceParentVM: ComposableFactory {
    static var children: [ComposedChild] {
        [
            .child(TwiceChildVM.self),
            .child(TwiceChildVM.self, via: Board.self)
        ]
    }
}

// MARK: - Tests (spec Task 4 + review-cycle contract pins)

@Suite("ProjectionContext record reads")
struct ProjectionContextTests {
    /// A planned handle — the factory's OWN and a composed CHILD's — reads back exactly the
    /// records the executor cached for it.
    @Test func plannedHandleReadsBackCachedRecords() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: BoardPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try grantBoardReads(app, board: dock1)

            let vmRequest = try BoardPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let cardNumbers = try context.records(BoardPageVM.cards).map(\.number).sorted()
            #expect(cardNumbers == [1, 2, 3])

            let membersNames = try context.records(MembersListVM.members).map(\.name).sorted()
            #expect(membersNames == ["Alice", "Bob"])
        }
    }

    /// A handle that never reached the plan THROWS — never returns `[]`. The error names the
    /// handle's record type and points at the forgotten declaration.
    @Test func unplannedHandleThrows() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: BoardPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try grantBoardReads(app, board: dock1)

            let vmRequest = try BoardPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            // Pier is never declared by any factory in this plan — its handle never reached it.
            let undeclared = LoadRequirement.read(Pier.self, in: .parentRoot)
            do {
                _ = try context.records(undeclared)
                Issue.record("expected a throw for an unplanned requirement, not an empty result")
            } catch let error as ContainmentError {
                guard case .unplannedRequirement = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
                #expect(error.debugDescription.contains("Pier"))
                #expect(error.debugDescription.contains("declare"))
            }
        }
    }

    /// Blend contract (a): two same-typed loads, BOTH granted — each handle returns exactly
    /// its own tuple's records. boardCards sees this board's [1,2,3]; workspaceCards sees the
    /// whole workspace's [1,2,3,9]. No duplication, no union, no false ambiguity.
    @Test func sameTypedLoadsEachResolveTheirOwnRecords() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: TwoCardLoadsRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[GrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace, Card.modelIdentityNamespace]
                )
            ]

            let vmRequest = try TwoCardLoadsRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let boardNumbers = try context.records(TwoCardLoadsVM.boardCards).map(\.number).sorted()
            #expect(boardNumbers == [1, 2, 3])

            let workspaceNumbers = try context.records(TwoCardLoadsVM.workspaceCards).map(\.number).sorted()
            #expect(workspaceNumbers == [1, 2, 3, 9])
        }
    }

    /// Blend contract (b) — the authorization pin: the apex-rooted Card load is DENIED
    /// (the workspace grant covers Board only), so its handle reads back `[]` — never the other
    /// tuple's granted records. The board-rooted handle still reads its own set.
    @Test func deniedHandleReadsEmptyNeverAnotherTuplesRecords() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: TwoCardLoadsRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[GrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace] // Card DENIED under the workspace anchor
                )
            ]

            let vmRequest = try TwoCardLoadsRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let workspaceNumbers = try context.records(TwoCardLoadsVM.workspaceCards).map(\.number)
            #expect(workspaceNumbers.isEmpty)

            let boardNumbers = try context.records(TwoCardLoadsVM.boardCards).map(\.number).sorted()
            #expect(boardNumbers == [1, 2, 3])
        }
    }

    /// C-2 regression pin: a child's BARE `.parentRoot` handle — whose tuple path was
    /// prefix-substituted by composition (to [Board]) — resolves exactly, in a plan that also
    /// carries the parent's own load. No false ambiguity, no miss.
    @Test func bareChildHandleBehindPrefixSubstitutionResolves() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: WorkspacePageRequest.self)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            app.storage[GrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: workspace.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Board.modelIdentityNamespace, Card.modelIdentityNamespace]
                )
            ]

            let vmRequest = try WorkspacePageRequest(query: .init(rootIdentity: workspace.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let boardNames = try context.records(WorkspacePageVM.boards).map(\.name).sorted()
            #expect(boardNames == ["Board 1", "Board 2"])

            let cardNumbers = try context.records(BareCardListVM.cards).map(\.number).sorted()
            #expect(cardNumbers == [1, 2, 3, 9]) // every board's cards — the child's whole tuple
        }
    }

    /// Genuine ambiguity: the SAME child composed onto two distinct paths walks its one
    /// declaration to two tuples — reading its handle throws; the framework never guesses.
    @Test func sameChildComposedTwiceThrowsAmbiguity() throws {
        let plan = try RecordLoadPlan.walk(from: TwiceParentVM.self)

        let context = ProjectionContext<BoardPageRequest, Void>(
            vmRequest: BoardPageRequest(),
            appState: (),
            plan: plan,
            recordsByTuple: [:],
            dependencySink: { _ in }
        )

        do {
            _ = try context.records(TwiceChildVM.cards)
            Issue.record("expected an ambiguity throw for a twice-composed declaration")
        } catch let error as ContainmentError {
            guard case .ambiguousRequirement = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("Card"))
            #expect(error.debugDescription.contains("give each composition its own declaration"))
        }
    }

    /// End-to-end: registering the request wires the executor to run BEFORE `body`, and the
    /// records (own + child) are visible to the projection. `body` aborts if they are not, so a
    /// 200 is proof the load phase ran and the reads resolved.
    @Test func composableScreenLoadsThenProjects() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try configureContainers(app)
            try app.register(request: BoardPageRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try grantBoardReads(app, board: dock1)

            let url = try requestURL(for: BoardPageRequest(query: .init(rootIdentity: dock1.modelIdentity)))
            let headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            let uri = URI(string: url.absoluteString)
            let req = Request(application: app, method: .GET, url: uri, headers: headers, on: app.eventLoopGroup.next())

            let response = try await app.responder.respond(to: req).get()
            #expect(response.status == .ok)
        }
    }
}
