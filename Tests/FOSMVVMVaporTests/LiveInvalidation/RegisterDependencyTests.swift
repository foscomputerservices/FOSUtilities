// RegisterDependencyTests.swift
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

// The read-side twin of invalidateProjections(of:): a factory calls
// context.registerDependency(on:) for data the plan can't see, and that identity rides to the
// client in the X-FOS-Registrations header alongside the plan's own set. Exercised through the
// real HTTP responder so the factory's deposit reaches the shared buildResponse on the same
// Request the header rides — the same served-HTTP pattern as RegistrationHeaderTests.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// MARK: - Fixtures

/// Neutral non-Fluent fixture: an Application-hosted source's state snapshot the plan can't see.
/// FOSMVVM.Model only — deliberately NOT a FluentKit.Model (mirrors InvalidateProjectionsTests).
private struct StatusSnapshot: FOSMVVM.Model {
    let id: ModelIdType?
    var activeSessions: Int = 0
}

/// The stable identity the zero-data dashboard registers (minted once, file-private) — shared by
/// the membership, exactness, and end-to-end tests so register and invalidate name the same value.
private let knownId = ModelIdType()

/// The distinct identity the plan-bearing fixture registers — kept apart from the plan's container
/// identities so the merge test proves both halves land.
private let mergeSnapshotId = ModelIdType()

/// A zero-data body (no ``ComposableFactory`` conformance, no plan) whose factory registers a StatusSnapshot —
/// exercises the serve else-branch sink.
private struct StatusDashboardVM: RequestableViewModel, VaporResponseBodyFactory {
    typealias Request = StatusDashboardRequest

    var vmId = ViewModelId()
    var activeSessions: Int = 0

    init() {}
    init(activeSessions: Int) {
        self.activeSessions = activeSessions
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        let snapshot = StatusSnapshot(id: knownId, activeSessions: 3)
        try context.registerDependency(on: snapshot)
        return .init(activeSessions: snapshot.activeSessions)
    }
}

private final class StatusDashboardRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: StatusDashboardVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: StatusDashboardVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

/// A read within `.application` WITH a plan whose factory ALSO registers a
/// StatusSnapshot — so the header must carry the plan's container identities AND the snapshot's.
private struct WorkspaceStatusVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = WorkspaceStatusRequest

    static let cards = Card.loadingPlan(.read, within: .application, via: Board.self)
    static var loadingPlans: LoadingPlans {
        cards
    }

    var vmId = ViewModelId()
    var cardNumbers: [Int] = []

    init() {}
    init(cardNumbers: [Int]) {
        self.cardNumbers = cardNumbers
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        try context.registerDependency(on: StatusSnapshot(id: mergeSnapshotId))
        return try .init(cardNumbers: context.records(cards).map(\.number).sorted())
    }
}

private final class WorkspaceStatusRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: WorkspaceStatusVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: WorkspaceStatusVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

/// A zero-data body whose factory registers a StatusSnapshot with a `nil` id — the throwing
/// `modelIdentity` getter must surface an error through serve, never a silently-missing deposit.
private struct NilSnapshotVM: RequestableViewModel, VaporResponseBodyFactory {
    typealias Request = NilSnapshotRequest

    var vmId = ViewModelId()

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        try context.registerDependency(on: StatusSnapshot(id: nil))
        return .init()
    }
}

private final class NilSnapshotRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: NilSnapshotVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: NilSnapshotVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - Harness

/// The serving side: localization, the Workspace → Board → Card graph, and the storage-backed grants
/// provider (grants are set per test, after seeding). Mirrors RegistrationHeaderTests' configureWorkspace.
private func configureServe(_ app: Application) throws {
    try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useModelAuthorizationProvider(TestGrantsProvider())
}

/// The serving side PLUS live invalidation — the end-to-end test needs both the header (serving)
/// and the hub (emission). configureWorkspace does not enable live, so this composes the two.
private func configureLiveServe(_ app: Application) throws {
    try configureServe(app)
    try app.useLiveInvalidation(on: app.routes)
}

private func registerWorkspaceApplicationScope(_ app: Application) throws {
    try app.useApplicationScope { req in
        guard let workspace = try await Workspace.query(on: req.db).first() else {
            throw Abort(.internalServerError, reason: "no workspace seeded")
        }
        return try workspace.modelIdentity
    }
}

private func setGrants(_ app: Application, _ grants: [TestGrant]) {
    app.storage[TestGrantsKey.self] = grants
}

private func cardReadGrant(container: ModelIdentity, _ ops: [ContainerOperation], types: [ModelNamespace]) -> TestGrant {
    TestGrant(authorizedModel: container, operations: ops, recordTypes: types)
}

private func getResponse(_ app: Application, for request: some ServerRequest) async throws -> Vapor.Response {
    let base = try #require(URL(string: "http://localhost"))
    let url = try #require(try base.appending(serverRequest: request))
    let headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
    let httpReq = Request(
        application: app, method: .GET, url: URI(string: url.absoluteString),
        headers: headers, collectedBody: .init(), on: app.eventLoopGroup.next()
    )
    return try await app.responder.respond(to: httpReq).get()
}

// MARK: - Tests

@Suite("Live invalidation: registerDependency(on:)")
struct RegisterDependencyTests {
    /// Contract 1: a factory register merges with the executed plan's set — no clobber. The header
    /// carries the plan's container identities (Workspace root + every Board) AND the snapshot's.
    @Test func factoryRegisterMergesWithPlanSet() async throws {
        try await withFluentTestApp { app in
            try configureServe(app)
            try registerWorkspaceApplicationScope(app)
            try app.register(request: WorkspaceStatusRequest.self, app: app)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            try setGrants(app, [
                cardReadGrant(
                    container: workspace.modelIdentity,
                    [.readRecords],
                    types: [Board.modelIdentityNamespace, Card.modelIdentityNamespace]
                )
            ])

            let res = try await getResponse(app, for: WorkspaceStatusRequest())
            #expect(res.status == .ok)

            let registered: [ModelIdentity] = try #require(res.headers.first(name: ModelIdentity.registrationsHeader)).fromJSON()
            let carried = Set(registered)

            // The plan's set survived …
            #expect(try carried.contains(workspace.modelIdentity))
            #expect(try carried.contains(dock1.modelIdentity))
            #expect(try carried.contains(dock2.modelIdentity))
            // … and the factory's register joined it.
            #expect(try carried.contains(StatusSnapshot(id: mergeSnapshotId).modelIdentity))
        }
    }

    /// Contract 2: a zero-data body registers too — header present, containing exactly the snapshot
    /// identity (the serve else-branch sink).
    @Test func zeroDataBodyRegisters() async throws {
        try await withFluentTestApp { app in
            try configureServe(app)
            try app.register(request: StatusDashboardRequest.self, app: app)
        } _: { app, _ in
            let res = try await getResponse(app, for: StatusDashboardRequest())
            #expect(res.status == .ok)

            let registered: [ModelIdentity] = try #require(res.headers.first(name: ModelIdentity.registrationsHeader)).fromJSON()
            #expect(try Set(registered) == [StatusSnapshot(id: knownId).modelIdentity])
        }
    }

    /// Contract 3: registering a nil-id model surfaces an error through serve — never a silently
    /// missing registration. The failure arrives as a non-`.ok` response or a thrown error; both
    /// satisfy the contract, silence does not.
    @Test func nilIdSurfacesError() async throws {
        try await withFluentTestApp { app in
            try configureServe(app)
            try app.register(request: NilSnapshotRequest.self, app: app)
        } _: { app, _ in
            var sawFailure = false
            do {
                let res = try await getResponse(app, for: NilSnapshotRequest())
                if res.status != .ok {
                    sawFailure = true
                }
            } catch {
                sawFailure = true
            }
            #expect(sawFailure)
        }
    }

    /// Contract 4 (the invariant): serve the fixture, decode the header, then invalidate the same
    /// model — the emitted set equals the snapshot's identity AND that identity is a member of the
    /// decoded header set. Registration and emission name the same value; that pairing IS the contract.
    @Test func registerAndInvalidateNameTheSameValue() async throws {
        try await withFluentTestApp { app in
            try configureLiveServe(app)
            try app.register(request: StatusDashboardRequest.self, app: app)
        } _: { app, _ in
            let res = try await getResponse(app, for: StatusDashboardRequest())
            #expect(res.status == .ok)
            let registered: [ModelIdentity] = try #require(res.headers.first(name: ModelIdentity.registrationsHeader)).fromJSON()

            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()

            try await app.invalidateProjections(of: StatusSnapshot(id: knownId))

            let snapshotIdentity = try StatusSnapshot(id: knownId).modelIdentity
            #expect(await events.next() == Set([snapshotIdentity]))
            #expect(Set(registered).contains(snapshotIdentity))
        }
    }
}
