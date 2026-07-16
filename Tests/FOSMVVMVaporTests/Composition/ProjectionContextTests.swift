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

// MARK: - Configure/seed plumbing (Harbor → Dock → {Berth, CrewMember})

private struct GrantsKey: StorageKey {
    typealias Value = [TestGrant]
}

private struct GrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[GrantsKey.self] ?? []
    }
}

private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier()) // CreateDock's DDL references piers
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useContainerAuthorizationProvider(GrantProvider())
}

private func registerApexResolver(_ app: Application) throws {
    try app.useApexContainerResolver { req in
        guard let harbor = try await Harbor.query(on: req.db).first() else {
            throw Abort(.internalServerError, reason: "no harbor seeded")
        }
        return try harbor.modelIdentity
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

/// Grants dock1 read of both Berth and CrewMember — the two handles the projection reads.
private func grantDockReads(_ app: Application, dock: Dock) throws {
    app.storage[GrantsKey.self] = try [
        TestGrant(
            authorizedContainer: dock.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Berth.modelIdentityNamespace, CrewMember.modelIdentityNamespace]
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

private struct DockRootedQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

/// A composed child that declares its OWN handle — the parent reads it to compose crew.
private struct CrewListVM: ComposableFactory {
    static let crew = LoadRequirement.read(CrewMember.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [crew]
    }
}

/// A composable page: its own Berth handle + a composed CrewListVM child (whose CrewMember
/// handle the page also reads). `body` fails loudly if either handle is invisible — proof the
/// load phase ran before projection.
private struct DockPageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = DockPageRequest

    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [berths]
    }

    static var children: [ComposedChild] {
        [.child(CrewListVM.self)]
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
        let berths = try context.records(Self.berths) //           own handle
        let crew = try context.records(CrewListVM.crew) //          a child's handle
        guard berths.count == 3, crew.count == 2 else {
            throw Abort(.internalServerError, reason: "projection saw \(berths.count) berths, \(crew.count) crew")
        }
        return .init()
    }
}

private final class DockPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: DockPageVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DockPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Blend-contract fixtures: two same-typed Berth loads in ONE plan

/// Two legitimate, distinct Berth loads:
///  - dockBerths: THIS dock's berths (query root, direct)
///  - harborBerths: ALL the harbor's berths (apex root via Dock)
/// Each handle must read back exactly its OWN tuple's records — never the union.
private struct TwoBerthLoadsVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = TwoBerthLoadsRequest

    static let dockBerths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static let harborBerths = LoadRequirement.read(Berth.self, in: .newRoot(.apex), via: Dock.self)

    static var dataRequirements: [any DataRequirement] {
        [dockBerths, harborBerths]
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

private final class TwoBerthLoadsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: TwoBerthLoadsVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: TwoBerthLoadsVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - C-2 regression fixtures: a bare child handle behind a prefix-substituted path

/// The child declares its Berth load BARE (`.parentRoot`, no `via:`) — composition supplies
/// the Dock hop, so its tuple's absolute path is prefix-substituted to [Dock].
private struct BareBerthListVM: ComposableFactory {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [berths]
    }
}

/// Harbor-rooted parent: its own Dock load + the bare-handled child composed via Dock.
private struct HarborPageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = HarborPageRequest

    static let docks = LoadRequirement.read(Dock.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [docks]
    }

    static var children: [ComposedChild] {
        [.child(BareBerthListVM.self, via: Dock.self)]
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

private final class HarborPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: HarborPageVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: HarborPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Genuine-ambiguity fixtures: the SAME child composed twice

private struct TwiceChildVM: ComposableFactory {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [berths]
    }
}

/// Composes the SAME child on two distinct paths — the one declaration walks to TWO tuples,
/// so its handle is genuinely ambiguous.
private struct TwiceParentVM: ComposableFactory {
    static var children: [ComposedChild] {
        [
            .child(TwiceChildVM.self),
            .child(TwiceChildVM.self, via: Dock.self)
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
            try app.registerRecordLoadPlan(for: DockPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try grantDockReads(app, dock: dock1)

            let vmRequest = try DockPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let berthNumbers = try context.records(DockPageVM.berths).map(\.number).sorted()
            #expect(berthNumbers == [1, 2, 3])

            let crewNames = try context.records(CrewListVM.crew).map(\.name).sorted()
            #expect(crewNames == ["Alice", "Bob"])
        }
    }

    /// A handle that never reached the plan THROWS — never returns `[]`. The error names the
    /// handle's record type and points at the forgotten declaration.
    @Test func unplannedHandleThrows() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: DockPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try grantDockReads(app, dock: dock1)

            let vmRequest = try DockPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
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
    /// its own tuple's records. dockBerths sees this dock's [1,2,3]; harborBerths sees the
    /// whole harbor's [1,2,3,9]. No duplication, no union, no false ambiguity.
    @Test func sameTypedLoadsEachResolveTheirOwnRecords() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: TwoBerthLoadsRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[GrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Berth.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace, Berth.modelIdentityNamespace]
                )
            ]

            let vmRequest = try TwoBerthLoadsRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let dockNumbers = try context.records(TwoBerthLoadsVM.dockBerths).map(\.number).sorted()
            #expect(dockNumbers == [1, 2, 3])

            let harborNumbers = try context.records(TwoBerthLoadsVM.harborBerths).map(\.number).sorted()
            #expect(harborNumbers == [1, 2, 3, 9])
        }
    }

    /// Blend contract (b) — the authorization pin: the apex-rooted Berth load is DENIED
    /// (the harbor grant covers Dock only), so its handle reads back `[]` — never the other
    /// tuple's granted records. The dock-rooted handle still reads its own set.
    @Test func deniedHandleReadsEmptyNeverAnotherTuplesRecords() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: TwoBerthLoadsRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[GrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Berth.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace] // Berth DENIED under the harbor anchor
                )
            ]

            let vmRequest = try TwoBerthLoadsRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let harborNumbers = try context.records(TwoBerthLoadsVM.harborBerths).map(\.number)
            #expect(harborNumbers.isEmpty)

            let dockNumbers = try context.records(TwoBerthLoadsVM.dockBerths).map(\.number).sorted()
            #expect(dockNumbers == [1, 2, 3])
        }
    }

    /// C-2 regression pin: a child's BARE `.parentRoot` handle — whose tuple path was
    /// prefix-substituted by composition (to [Dock]) — resolves exactly, in a plan that also
    /// carries the parent's own load. No false ambiguity, no miss.
    @Test func bareChildHandleBehindPrefixSubstitutionResolves() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: HarborPageRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[GrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace, Berth.modelIdentityNamespace]
                )
            ]

            let vmRequest = try HarborPageRequest(query: .init(rootIdentity: harbor.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)
            let context = makeContext(for: vmRequest, on: req)

            let dockNames = try context.records(HarborPageVM.docks).map(\.name).sorted()
            #expect(dockNames == ["Dock 1", "Dock 2"])

            let berthNumbers = try context.records(BareBerthListVM.berths).map(\.number).sorted()
            #expect(berthNumbers == [1, 2, 3, 9]) // every dock's berths — the child's whole tuple
        }
    }

    /// Genuine ambiguity: the SAME child composed onto two distinct paths walks its one
    /// declaration to two tuples — reading its handle throws; the framework never guesses.
    @Test func sameChildComposedTwiceThrowsAmbiguity() throws {
        let plan = try RecordLoadPlan.walk(from: TwiceParentVM.self)

        let context = ProjectionContext<DockPageRequest, Void>(
            vmRequest: DockPageRequest(),
            appState: (),
            plan: plan,
            recordsByTuple: [:],
            dependencySink: { _ in }
        )

        do {
            _ = try context.records(TwiceChildVM.berths)
            Issue.record("expected an ambiguity throw for a twice-composed declaration")
        } catch let error as ContainmentError {
            guard case .ambiguousRequirement = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("Berth"))
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
            try app.register(request: DockPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try grantDockReads(app, dock: dock1)

            let url = try requestURL(for: DockPageRequest(query: .init(rootIdentity: dock1.modelIdentity)))
            let headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            let uri = URI(string: url.absoluteString)
            let req = Request(application: app, method: .GET, url: uri, headers: headers, on: app.eventLoopGroup.next())

            let response = try await app.responder.respond(to: req).get()
            #expect(response.status == .ok)
        }
    }
}
