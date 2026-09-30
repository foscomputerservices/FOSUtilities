// TotalCountTests.swift
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

// Test-taxonomy discipline: totalCount(for:) reads the executor's count snapshot back by declared
// handle, via `@testable import FOSMVVMVapor`. Behavior only — no encoded shape asserted.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

private struct GrantsKey: StorageKey { typealias Value = [TestGrant] }

private struct GrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[GrantsKey.self] ?? []
    }
}

private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useContainerAuthorizationProvider(GrantProvider())
}

private func makeRequest(on app: Application, url: URL? = nil) -> Vapor.Request {
    Request(application: app, method: .GET, url: URI(string: url?.absoluteString ?? "/"), on: app.eventLoopGroup.next())
}

private func requestURL(for request: some ServerRequest) throws -> URL {
    let base = try #require(URL(string: "http://localhost"))
    return try #require(try base.appending(serverRequest: request))
}

private func grantBoardReadsCards(_ app: Application, board: Board) throws {
    app.storage[GrantsKey.self] = try [
        TestGrant(
            authorizedContainer: board.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Card.modelIdentityNamespace]
        )
    ]
}

/// A rooted query that ALSO carries a window — the search-window shape.
private struct PagedBoardQuery: RootedQuery, PaginatedQuery {
    let rootIdentity: ModelIdentity
    let pagination: Pagination
}

/// A windowed Card page: its Card requirement is `.refinedByRequest`, so the query's window
/// binds to it. `body` is a no-op; the tests read records + total off the context directly.
private struct PagedBoardVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = PagedBoardRequest

    static let cards = LoadRequirement.read(Card.self, in: .parentRoot).refinedByRequest
    static var dataRequirements: [any DataRequirement] {
        [cards]
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

private final class PagedBoardRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = PagedBoardQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: PagedBoardQuery?
    var responseBody: PagedBoardVM?

    init(query: PagedBoardQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: PagedBoardVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Builds the context the way `serve` does — WITH the count snapshot.
private func makeContext(for vmRequest: PagedBoardRequest, on req: Vapor.Request) -> ProjectionContext<PagedBoardRequest, Void> {
    guard let plan = req.application.recordLoadPlan(for: PagedBoardRequest.self) else {
        return .init(vmRequest: vmRequest, appState: (), dependencySink: { _ in })
    }
    return .init(vmRequest: vmRequest, appState: (), plan: plan, recordsByTuple: req.recordsByTuple(), countsByTuple: req.countsByTuple(), dependencySink: { _ in })
}

@Suite("Paginated total-count")
struct TotalCountTests {
    /// The window returns a slice; the total is the whole authorized set.
    @Test func totalCountIsFullSetWhileRecordsAreWindowed() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: PagedBoardRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db) // dock1 has 3 cards
            try grantBoardReadsCards(app, board: dock1)

            let vmRequest = try PagedBoardRequest(query: .init(rootIdentity: dock1.modelIdentity, pagination: .init(startIndex: 0, maxResults: 1)))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            #expect(try context.records(PagedBoardVM.cards).count == 1) // windowed
            #expect(try context.totalCount(for: PagedBoardVM.cards) == 3) // full set
        }
    }

    /// The total is the AUTHORIZED set — no grant, no count leak (0, not 3).
    @Test func totalCountRespectsAuthorization() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: PagedBoardRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            app.storage[GrantsKey.self] = [] // no grant

            let vmRequest = try PagedBoardRequest(query: .init(rootIdentity: dock1.modelIdentity, pagination: .init(startIndex: 0, maxResults: 1)))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            #expect(try context.records(PagedBoardVM.cards).isEmpty)
            #expect(try context.totalCount(for: PagedBoardVM.cards) == 0)
        }
    }

    /// An unplanned handle throws — never returns 0 (mirrors records(_:)).
    @Test func unplannedHandleThrows() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: PagedBoardRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try grantBoardReadsCards(app, board: dock1)

            let vmRequest = try PagedBoardRequest(query: .init(rootIdentity: dock1.modelIdentity, pagination: .init(startIndex: 0, maxResults: 1)))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let undeclared = LoadRequirement.read(Pier.self, in: .parentRoot)
            do {
                _ = try context.totalCount(for: undeclared)
                Issue.record("expected a throw for an unplanned requirement, not 0")
            } catch let error as ContainmentError {
                guard case .unplannedRequirement = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }

    /// A ViewModel storing a window total round-trips it intact — contract, not encoded shape.
    @Test func storedTotalRoundTrips() throws {
        struct CardSearchVM: Codable, Hashable {
            let totalMatches: Int
        }
        let vm = CardSearchVM(totalMatches: 1204882)
        let restored = try vm.toJSON().fromJSON() as CardSearchVM
        #expect(restored.totalMatches == vm.totalMatches)
    }
}
