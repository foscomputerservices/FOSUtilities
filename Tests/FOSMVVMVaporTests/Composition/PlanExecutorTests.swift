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
/// Harbor (apex) → Dock → {Berth, CrewMember, PersonnelFolder (.guards) → PersonnelFile}.
private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier()) // CreateDock's DDL references piers
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    try app.register(PersonnelFolder.self, migration: CreatePersonnelFolder())
    app.migrations.add(CreatePersonnelFile())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useContainerAuthorizationProvider(StorageGrantProvider())
}

/// Registers the apex resolver: the one seeded Harbor. Seeding happens after boot, so the
/// resolver queries at request time (the multi-tenant shape from the resolver's contract).
private func registerApexResolver(_ app: Application) throws {
    try app.useApexContainerResolver { req in
        guard let harbor = try await Harbor.query(on: req.db).first() else {
            throw Abort(.internalServerError, reason: "no harbor seeded")
        }
        return try harbor.modelIdentity
    }
}

/// Grants are set per test AFTER seeding (identities exist only then); the provider reads
/// them from Application storage at request time.
private struct ExecutorGrantsKey: StorageKey {
    typealias Value = [TestGrant]
}

private struct StorageGrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[ExecutorGrantsKey.self] ?? []
    }
}

/// Seeds one folder per dock: folder1 (2 files) under dock1, folder2 (1 file) under dock2.
private func seedPersonnel(
    on db: any Database,
    dock1: Dock,
    dock2: Dock
) async throws -> (folder1: PersonnelFolder, folder2: PersonnelFolder) {
    let folder1 = try PersonnelFolder(name: "Folder 1", dockId: dock1.requireId())
    let folder2 = try PersonnelFolder(name: "Folder 2", dockId: dock2.requireId())
    try await folder1.save(on: db)
    try await folder2.save(on: db)
    try await PersonnelFile(name: "File A", folderId: folder1.requireId()).save(on: db)
    try await PersonnelFile(name: "File B", folderId: folder1.requireId()).save(on: db)
    try await PersonnelFile(name: "File C", folderId: folder2.requireId()).save(on: db)
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

private func berthNumbers(_ records: [any DataModel]?) throws -> [Int] {
    try (records ?? []).map { try #require($0 as? Berth).number }
}

private func fileNames(_ records: [any DataModel]?) throws -> [String] {
    try (records ?? []).map { try #require($0 as? PersonnelFile).name }
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

/// The query vending a request-scoped root identity (usually a Dock's).
private struct ExecRootedQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

/// Test 10's query: roots the tree AND declares the window axis.
private struct PagedBerthQuery: RootedQuery, PaginatedQuery {
    let rootIdentity: ModelIdentity
    let pagination: Pagination
}

// MARK: - Test 8: the forest (dock-rooted .query tree + apex-rooted tree, one request)

private struct ApexDockListVM: ExecutorFixture {
    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Dock.self, in: .parentRoot)]
}

private struct ForestPageVM: ExecutorFixture, RequestableViewModel {
    typealias Request = ForestPageRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]

    static var children: [ComposedChild] {
        [.child(ApexDockListVM.self, rootedAt: .apex)]
    }
}

private final class ForestPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecRootedQuery?
    var responseBody: ForestPageVM?

    init(query: ExecRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ForestPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Test 9: three-level .inherits descent under one apex grant

private struct ThreeLevelVM: ExecutorFixture, RequestableViewModel {
    typealias Request = ThreeLevelRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .newRoot(.apex), via: Dock.self)]
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

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(PersonnelFile.self, in: .newRoot(.apex), via: Dock.self, PersonnelFolder.self)]
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

private struct ApexBerthListVM: ExecutorFixture {
    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot, via: Dock.self)]
}

private struct DiamondPageVM: ExecutorFixture, RequestableViewModel {
    typealias Request = DiamondPageRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]

    static var children: [ComposedChild] {
        [.child(ApexBerthListVM.self, rootedAt: .apex)]
    }
}

private final class DiamondPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecRootedQuery?
    var responseBody: DiamondPageVM?

    init(query: ExecRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DiamondPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Test 10: .refinedByRequest — sort/window on exactly the marked tuple

private struct RefinedBerthsVM: ExecutorFixture, RequestableViewModel {
    typealias Request = RefinedBerthsRequest

    static let dataRequirements: [any DataRequirement] = [
        LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest,
        LoadRequirement.read(CrewMember.self, in: .parentRoot)
    ]
}

private final class RefinedBerthsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = PagedBerthQuery
    typealias ResponseError = EmptyError
    typealias Sort = SortCriteria<BerthSortKey>

    let id: String
    let query: PagedBerthQuery?
    let sort: SortCriteria<BerthSortKey>?
    var responseBody: RefinedBerthsVM?

    init(query: PagedBerthQuery? = nil, sort: SortCriteria<BerthSortKey>? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: RefinedBerthsVM? = nil) {
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

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]
}

/// The hook proves its post-declarative ordering structurally: it reads the declarative
/// berth tuple FROM THE CACHE (throwing if absent) and loads crew through the
/// provider-driven entry using that cached tuple's container.
extension SupplementalPageVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        guard let berthEntry = request.containerRecordCache.first(where: {
            $0.key.containedType == ObjectIdentifier(Berth.self) && !$0.value.isEmpty
        }) else {
            throw SupplementalHookError.declarativeTupleNotCached
        }
        _ = try await request.authorizedRecords(
            of: berthEntry.key.container,
            containing: CrewMember.self,
            for: .readRecords
        )
    }
}

private final class SupplementalPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecRootedQuery?
    var responseBody: SupplementalPageVM?

    init(query: ExecRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SupplementalPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

private struct ThrowingSupplementalVM: ExecutorFixture, RequestableViewModel {
    typealias Request = ThrowingSupplementalRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]
}

extension ThrowingSupplementalVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        throw SupplementalHookError.deliberate
    }
}

private final class ThrowingSupplementalRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecRootedQuery?
    var responseBody: ThrowingSupplementalVM?

    init(query: ExecRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ThrowingSupplementalVM? = nil) {
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

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]
}

private final class UnregisteredPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecRootedQuery?
    var responseBody: UnregisteredPageVM?

    init(query: ExecRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: UnregisteredPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Obligation 2: misrooted query — root descriptor must contain the first hop

private struct MisrootedVM: ExecutorFixture, RequestableViewModel {
    typealias Request = MisrootedRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]
}

private final class MisrootedRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = ExecRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: ExecRootedQuery?
    var responseBody: MisrootedVM?

    init(query: ExecRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: MisrootedVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Tests (spec tests 8–11 + 13)

@Suite("RecordLoadPlan execution through the authorized engine (C7)")
struct PlanExecutorTests {
    /// Spec test 8 — the forest: a dock-rooted `.query` tree and an apex-rooted tree execute
    /// in ONE request; both trees' records land in the engine's cache.
    @Test func forestLoadsBothTreesIntoTheCache() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: ForestPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Berth.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace]
                )
            ]

            let vmRequest = try ForestPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            let berths = try cachedRecords(in: req, of: Berth.self, in: dock1.modelIdentity)
            #expect(try berthNumbers(berths).sorted() == [1, 2, 3])

            let docks = try cachedRecords(in: req, of: Dock.self, in: harbor.modelIdentity)
            #expect(docks?.count == 2)
        }
    }

    /// Spec test 9 — `.inherits` descent: ONE grant on the harbor (apex) covering Dock and
    /// Berth loads the whole three-level tree (harbor → docks → berths, all docks' berths).
    @Test func apexGrantDescendsThreeLevelsUnderInherits() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: ThreeLevelRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            let harborIdentity = try harbor.modelIdentity
            app.storage[ExecutorGrantsKey.self] = [
                TestGrant(
                    authorizedContainer: harborIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace, Berth.modelIdentityNamespace]
                )
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: ThreeLevelRequest())

            let docks = cachedRecords(in: req, of: Dock.self, in: harborIdentity)
            #expect(docks?.count == 2)

            // Every level's grant check ran against the ROOT anchor (harbor), never the dock.
            let dock1Berths = try cachedRecords(
                in: req, of: Berth.self, in: dock1.modelIdentity, anchoredAt: harborIdentity
            )
            let dock2Berths = try cachedRecords(
                in: req, of: Berth.self, in: dock2.modelIdentity, anchoredAt: harborIdentity
            )
            #expect(try berthNumbers(dock1Berths).sorted() == [1, 2, 3])
            #expect(try berthNumbers(dock2Berths) == [9])
        }
    }

    /// Spec test 9 — `.guards` denial: an apex grant covering PersonnelFile does NOT descend
    /// past the folder guard; the folders themselves (above the guard) still load.
    @Test func apexGrantDoesNotDescendPastTheGuard() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: GuardedFilesRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let (folder1, folder2) = try await seedPersonnel(on: db, dock1: dock1, dock2: dock2)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [
                        Dock.modelIdentityNamespace,
                        PersonnelFolder.modelIdentityNamespace,
                        PersonnelFile.modelIdentityNamespace // deliberately covered — must not descend
                    ]
                )
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: GuardedFilesRequest())

            let folders = try cachedRecords(in: req, of: PersonnelFolder.self, in: dock1.modelIdentity)
            #expect(folders?.count == 1)

            let files1 = try cachedRecords(in: req, of: PersonnelFile.self, in: folder1.modelIdentity)
            let files2 = try cachedRecords(in: req, of: PersonnelFile.self, in: folder2.modelIdentity)
            #expect(files1?.isEmpty == true)
            #expect(files2?.isEmpty == true)
        }
    }

    /// Spec test 9 — `.guards` allow: a grant anchored on the FOLDER instance loads that
    /// folder's files; the other folder's subtree stays empty (per-branch anchoring).
    @Test func folderAnchoredGrantLoadsExactlyThatSubtree() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: GuardedFilesRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let (folder1, folder2) = try await seedPersonnel(on: db, dock1: dock1, dock2: dock2)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace, PersonnelFolder.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: folder1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [PersonnelFile.modelIdentityNamespace]
                )
            ]

            let req = makeRequest(on: app)
            try await req.executeRecordLoadPlan(for: GuardedFilesRequest())

            // The file loads' cache entries are anchored at each branch's own folder.
            let files1 = try cachedRecords(
                in: req, of: PersonnelFile.self, in: folder1.modelIdentity, anchoredAt: folder1.modelIdentity
            )
            let files2 = try cachedRecords(in: req, of: PersonnelFile.self, in: folder2.modelIdentity)
            #expect(try fileNames(files1).sorted() == ["File A", "File B"])
            #expect(files2?.isEmpty == true)
        }
    }

    /// Spec test 9 — anchor-conflict diamond: the SAME (container, type) reached through the
    /// query root (anchor = dock) and through the apex root (anchor = harbor) keys TWO cache
    /// entries with independent outcomes — one authorized, one empty.
    @Test func anchorConflictDiamondKeysIndependentEntries() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: DiamondPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            let harborIdentity = try harbor.modelIdentity
            // Berths granted on dock1 ONLY — the harbor grant covers docks, not berths.
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Berth.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedContainer: harborIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace]
                )
            ]

            let vmRequest = try DiamondPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            let dockAnchored = try cachedRecords(
                in: req, of: Berth.self, in: dock1.modelIdentity, anchoredAt: dock1.modelIdentity
            )
            let harborAnchored = try cachedRecords(
                in: req, of: Berth.self, in: dock1.modelIdentity, anchoredAt: harborIdentity
            )
            #expect(try berthNumbers(dockAnchored).sorted() == [1, 2, 3])
            #expect(harborAnchored?.isEmpty == true)
        }
    }

    /// Spec test 10 — `.refinedByRequest`: the request's sort + window land on exactly the
    /// marked tuple (berths, descending, first 2); the unmarked tuple (crew) stays unrefined.
    @Test func requestRefinementAppliesToExactlyTheMarkedTuple() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: RefinedBerthsRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let dock1Identity = try dock1.modelIdentity
            app.storage[ExecutorGrantsKey.self] = [
                TestGrant(
                    authorizedContainer: dock1Identity,
                    operations: [.readRecords],
                    recordTypes: [Berth.modelIdentityNamespace, CrewMember.modelIdentityNamespace]
                )
            ]

            let request = RefinedBerthsRequest(
                query: .init(rootIdentity: dock1Identity, pagination: .init(startIndex: 0, maxResults: 2)),
                sort: SortCriteria([.init(key: BerthSortKey.number, direction: .descending)])
            )
            let req = try makeRequest(on: app, url: requestURL(for: request))
            try await req.executeRecordLoadPlan(for: request)

            let berths = cachedRecords(in: req, of: Berth.self, in: dock1Identity)
            #expect(try berthNumbers(berths) == [3, 2]) // sorted desc, windowed to 2

            let crew = cachedRecords(in: req, of: CrewMember.self, in: dock1Identity)
            #expect(crew?.count == 2) // full set — no window leaked onto the unmarked tuple

            let crewKey = req.containerRecordCache.keys.first {
                $0.containedType == ObjectIdentifier(CrewMember.self)
            }
            #expect(crewKey?.refinement == ContainmentQueryRefinement.none)
        }
    }

    /// Spec test 11 — supplemental seam: the conformer's hook runs AFTER the declarative
    /// tuples (it reads the cached berth tuple; a miss throws) and loads extra records
    /// through the provider-driven entry.
    @Test func supplementalHookRunsPostDeclarative() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SupplementalPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let dock1Identity = try dock1.modelIdentity
            app.storage[ExecutorGrantsKey.self] = [
                TestGrant(
                    authorizedContainer: dock1Identity,
                    operations: [.readRecords],
                    recordTypes: [Berth.modelIdentityNamespace, CrewMember.modelIdentityNamespace]
                )
            ]

            let vmRequest = SupplementalPageRequest(query: .init(rootIdentity: dock1Identity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            // The hook completed (no declarativeTupleNotCached throw) and its load deposited.
            let crew = cachedRecords(in: req, of: CrewMember.self, in: dock1Identity)
            #expect(crew?.count == 2)
        }
    }

    /// Spec test 11 — a throwing supplemental hook fails the request (propagates, never
    /// swallow-to-empty).
    @Test func throwingSupplementalHookFailsExecution() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: ThrowingSupplementalRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let vmRequest = try ThrowingSupplementalRequest(query: .init(rootIdentity: dock1.modelIdentity))
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
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: ThreeLevelRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            app.storage[ExecutorGrantsKey.self] = try [
                TestGrant(
                    authorizedContainer: harbor.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Dock.modelIdentityNamespace, Berth.modelIdentityNamespace]
                )
            ]

            let first = makeRequest(on: app)
            try await first.executeRecordLoadPlan(for: ThreeLevelRequest())
            let second = makeRequest(on: app)
            try await second.executeRecordLoadPlan(for: ThreeLevelRequest())

            // All sibling deposits present: one dock entry + one berth entry per dock.
            #expect(first.containerRecordCache.count == 3)
            for dock in [dock1, dock2] {
                let firstRun = try cachedRecords(in: first, of: Berth.self, in: dock.modelIdentity)
                let secondRun = try cachedRecords(in: second, of: Berth.self, in: dock.modelIdentity)
                #expect(firstRun != nil)
                // Determinism: both executions produced the same records in the same order.
                #expect(try berthNumbers(firstRun) == berthNumbers(secondRun))
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
            let (dock1, _) = try await seedHarbor(on: db)
            let vmRequest = try UnregisteredPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
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

    /// Obligation 2 — a RootedQuery vending an identity whose registered descriptor does not
    /// declare containment of the tuple's first hop throws typed: the misrooted-query
    /// silent-empty mode is dead. (Harbor is registered but contains Dock, never Berth.)
    @Test func misrootedQueryAgainstRegisteredContainerThrowsTyped() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: MisrootedRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let harbor = try #require(try await Harbor.query(on: db).first())
            let vmRequest = try MisrootedRequest(query: .init(rootIdentity: harbor.modelIdentity))
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

    /// Spec §9 group 14 — apex publicization: an `.apex`-rooted plan is usable end-to-end through
    /// the now-PUBLIC `useApexContainerResolver` registration (`forestLoadsBothTreesIntoTheCache`
    /// and `apexGrantDescendsThreeLevelsUnderInherits` exercise the happy path). Here the negative:
    /// an apex that cannot resolve at request time fails the request — the resolver's error
    /// propagates with the existing semantics (no silent empty). The resolver queries for a seeded
    /// harbor; none is seeded, so it throws.
    @Test func unresolvedApexFailsTheRequest() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try registerApexResolver(app)
            try app.registerRecordLoadPlan(for: ThreeLevelRequest.self)
        } _: { app, _ in
            // No harbor seeded ⇒ the apex resolver throws when the plan resolves its apex root.
            let req = makeRequest(on: app)
            await #expect(throws: (any Error).self) {
                try await req.executeRecordLoadPlan(for: ThreeLevelRequest())
            }
        }
    }

    /// Obligation 2 — a RootedQuery vending an identity of an UNREGISTERED type (Pier is a
    /// DataModel, never a registered container) throws typed at root binding.
    @Test func misrootedQueryAgainstUnregisteredTypeThrowsTyped() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: MisrootedRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let pier = try #require(try await Pier.query(on: db).first())
            let vmRequest = try MisrootedRequest(query: .init(rootIdentity: pier.modelIdentity))
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
}
