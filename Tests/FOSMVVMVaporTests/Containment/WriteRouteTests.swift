// WriteRouteTests.swift
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

// The write path (C8 T6): candidates, sealed apply, refresh fall-through. Exercised through the
// internal serve/commit entries (`@testable`): each write serves its refresh body value directly,
// so post-write state is asserted without the HTTP/localization layer. Test groups 5–9, 15, 16.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

// MARK: - Harness

/// Counting grant provider: `callCount` proves the per-Request grant memo survives invalidation.
private final class GrantBox: @unchecked Sendable {
    var grants: [TestGrant] = []
    var callCount = 0
}

private struct GrantBoxKey: StorageKey {
    typealias Value = GrantBox
}

private struct CountingGrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        let box = request.application.storage[GrantBoxKey.self] ?? GrantBox()
        box.callCount += 1
        return box.grants
    }
}

private func configureWriteContainers(
    _ app: Application,
    uniqueBerthNumber: Bool = false,
    uniqueDockCrew: Bool = false
) throws {
    app.storage[GrantBoxKey.self] = GrantBox()
    app.migrations.add(CreatePier()) // CreateDock's DDL references piers
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(uniqueBerthNumber ? UniqueNumberBerthMigration() : CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(uniqueDockCrew ? UniqueDockCrewMigration() : CreateDockCrew())
    try app.useContainerAuthorizationProvider(CountingGrantProvider())
}

private func makeRequest(on app: Application) -> Vapor.Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

private func setGrants(_ app: Application, _ grants: [TestGrant]) {
    app.storage[GrantBoxKey.self]?.grants = grants
}

private func grantCount(_ app: Application) -> Int {
    app.storage[GrantBoxKey.self]?.callCount ?? 0
}

/// Grants `ops` on Berth in `dock`.
private func berthGrant(_ dock: Dock, _ ops: [ContainerOperation]) throws -> TestGrant {
    try TestGrant(
        authorizedContainer: dock.modelIdentity,
        operations: ops,
        recordTypes: [Berth.modelIdentityNamespace]
    )
}

private func berths(of dock: Dock, on db: any Database) async throws -> [Berth] {
    try await Berth.query(on: db).filter(\.$dock.$id == dock.requireId()).all()
}

// MARK: - Group 5: update

@Suite("Write route: update")
struct WriteRouteUpdateTests {
    /// End-to-end through the real route: the PATCH method routes, the middleware binds the query
    /// from the URL, the handler decodes the JSON body, and the response is the refreshed screen.
    @Test func patchRoutesThroughRealPipeline() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let base = try #require(URL(string: "http://localhost"))
            let url = try #require(try base.appending(serverRequest: vmRequest))

            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            try buffer.writeBytes(JSONEncoder().encode(UpdateBerthBody(number: 88, dockName: "Wired")))
            var headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            headers.contentType = .json
            let httpReq = Request(
                application: app, method: .PATCH, url: URI(string: url.absoluteString),
                headers: headers, collectedBody: buffer, on: app.eventLoopGroup.next()
            )

            let response = try await app.responder.respond(to: httpReq).get()
            #expect(response.status == .ok)
            let data = try #require(response.body.data)
            let refreshed: BerthListVM = try data.fromJSON()
            #expect(refreshed.berthNumbers.contains(88))
        }
    }

    /// Happy path: the response IS refreshRequest()'s body reflecting post-write state.
    @Test func updateReflectsPostWriteState() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 99, dockName: "Renamed"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            let body = try #require(vmRequest.requestBody)
            let result = try await req.serveUpdate(vmRequest, body: body)

            #expect(result.berthNumbers.contains(99))
            // Persisted, not echoed: a fresh DB read agrees.
            let reloaded = try #require(try await Berth.find(berth.requireId(), on: db))
            #expect(reloaded.number == 99)
            #expect(reloaded.dockName == "Renamed")
        }
    }

    /// Candidates only: after commit (before the refresh) the cache holds the write-verb candidate
    /// entry and NO read-verb entry — the page's read plan was never loaded pre-apply.
    @Test func pageReadPlanNotLoadedPreApply() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 5, dockName: "X"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            _ = try await req.commitUpdate(vmRequest, body: #require(vmRequest.requestBody))

            let ops = Set(req.containerRecordCache.keys.map(\.operation))
            #expect(ops.contains(.writeRecords)) // the candidate load ran
            #expect(!ops.contains(.readRecords)) // the page read plan did NOT
        }
    }

    /// Invalidation makes a stale read impossible: a read-op entry cached before the write is
    /// dropped, so the refresh re-reads fresh rather than serving the pre-write value.
    @Test func cacheInvalidatedNoStaleRead() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
            // The pre-write prime reads through BerthListRequest, so register it as a read too —
            // a write now derives only its OWN response plan, not a separate refresh request's.
            try app.register(request: BerthListRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let req = makeRequest(on: app)
            // Prime the read-op cache with pre-write berths.
            try await req.executeRecordLoadPlan(for: BerthListRequest(query: .init(rootIdentity: dock1.modelIdentity)))

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 77, dockName: "Fresh"),
                responseBody: nil
            )
            let result = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            #expect(result.berthNumbers.contains(77)) // fresh, not the stale primed set
        }
    }

    /// The per-Request grant memo survives the write (invalidation touches records, never grants):
    /// the provider is consulted exactly once across the candidate load and the refresh read.
    @Test func grantMemoSurvivesTheWrite() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 3, dockName: "Y"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))

            #expect(grantCount(app) == 1)
        }
    }

    /// A save-time DB constraint violation propagates as the request's error.
    @Test func saveConstraintViolationPropagates() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app, uniqueBerthNumber: true)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let all = try await berths(of: dock1, on: db).sorted { $0.number < $1.number }
            let first = try #require(all.first) // number 1
            let second = try #require(all.dropFirst().first) // number 2

            // Update berth #1 → number 2, colliding with berth #2 on the unique index.
            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: first.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: second.number, dockName: "Collide"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: (any Error).self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
        }
    }
}

// MARK: - Group 6: create

@Suite("Write route: create")
struct WriteRouteCreateTests {
    /// Fresh Target() + same apply; the framework sets the container FK from the candidate scope;
    /// the created record is present in the refresh body.
    @Test func createAddsRecordVisibleInRefresh() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .createRecords])])

            let vmRequest = try CreateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateBerthBody(number: 42, dockName: "New Berth"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            let result = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))

            #expect(result.berthNumbers.contains(42))
            // The container FK was set from the candidate scope: the new berth belongs to dock1.
            let created = try await berths(of: dock1, on: db).filter { $0.number == 42 }
            #expect(created.count == 1)
        }
    }

    /// `.create` accepts no intermediates — compile-audit (a `via:` path would fan out to N
    /// containers; the create scope must be exactly one). This line only compiles because `.create`
    /// has no `via:` parameter.
    @Test func createTakesNoIntermediates() {
        _ = LoadRequirement.create(Berth.self, in: .parentRoot)
    }
}

// MARK: - Group 7: delete

@Suite("Write route: delete")
struct WriteRouteDeleteTests {
    /// WriteTargetProviding alone (no apply): the target is gone from the refresh body.
    @Test func deleteRemovesRecordFromRefresh() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: DeleteBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .deleteRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)
            let goneNumber = berth.number

            let vmRequest = try DeleteBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let req = makeRequest(on: app)
            let result = try await req.serveDelete(vmRequest)

            #expect(!result.berthNumbers.contains(goneNumber))
            let remaining = try await berths(of: dock1, on: db)
            #expect(!remaining.contains { $0.number == goneNumber })
        }
    }
}

// MARK: - Group 8: validation gate

@Suite("Write route: validation gate")
struct WriteRouteValidationTests {
    /// A failing validate() never reaches apply: the error propagates and the record is unchanged.
    @Test func failingValidationNeverReachesApply() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)
            let originalNumber = berth.number

            // number == -1 fails UpdateBerthBody.validate.
            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: -1, dockName: "Nope"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: ValidationError.self) {
                _ = try await req.commitUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let reloaded = try #require(try await Berth.find(berth.requireId(), on: db))
            #expect(reloaded.number == originalNumber) // apply never ran
        }
    }
}

// MARK: - Group 9: retarget-proofing

@Suite("Write route: retarget-proofing")
struct WriteRouteRetargetTests {
    /// A target outside the candidate set is not-found — indistinguishable from a missing row.
    @Test func targetOutsideCandidateSetIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            // A berth in dock2, but the request roots at dock1 — outside the candidate set.
            let foreignBerth = try #require(try await berths(of: dock2, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: foreignBerth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 1, dockName: "Z"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
        }
    }

    /// The candidate set honors the write verb's operation in grant checks: a read-only grant
    /// authorizes no write candidate, so even the request's own berth is not-found.
    @Test func candidateHonorsWriteVerbInGrantChecks() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords])]) // NO write grant
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 1, dockName: "Z"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
        }
    }

    /// A write request whose candidate plan was never derived fails fast — it never resolves the
    /// target against nothing.
    @Test func missingCandidatePlanFailsFast() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            // NOTE: UpdateBerthRequest is deliberately NOT registered — no candidate plan exists.
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 1, dockName: "Z"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: ContainmentError.self) {
                _ = try await req.commitUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
        }
    }

    /// Body-borne identity is impossible by construction: no RequestBody stores a ModelIdType.
    @Test func requestBodiesCarryNoModelIdType() {
        for mirror in [Mirror(reflecting: UpdateBerthBody(number: 0, dockName: "")),
                       Mirror(reflecting: CreateBerthBody(number: 0, dockName: ""))] {
            for child in mirror.children {
                #expect(!(child.value is ModelIdType))
                #expect(!(child.value is ModelIdType?))
            }
        }
    }
}

// MARK: - Group 15: boot fail-fasts

@Suite("Write route: boot fail-fasts")
struct WriteRouteBootTests {
    /// A fully-constrained write request binds the write door (positive overload selection): the
    /// update happy path already proves this, but pin it — registering it derives a candidate plan.
    @Test func fullyConstrainedWriteRequestBindsWriteDoor() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, _ in
            #expect(app.candidatePlan(for: UpdateBerthRequest.self) != nil)
            #expect(app.recordLoadPlan(for: UpdateBerthRequest.self) != nil) // its own response plan too
        }
    }

    /// A ReplaceRequest reaches the read door (no write overload) and fails fast: not yet supported.
    @Test func replaceRequestNotYetSupported() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try app.register(request: EchoReplaceRequest.self)
            } _: { _, _ in }
        }
    }

    /// A write-protocol conformer that misses the write constraints falls through to the read door
    /// and fails fast rather than registering GET-only.
    @Test func writeConformerAtReadDoorFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try app.register(request: SelfRefreshUpdateRequest.self)
            } _: { _, _ in }
        }
    }

    /// Candidate root-source validation: a `.query`-rooted candidate whose query is not RootedQuery
    /// fails fast at boot.
    @Test func candidateQueryRootWithoutRootedQueryFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: NoRootUpdateRequest.self)
            } _: { _, _ in }
        }
    }

    /// Candidate root-source validation: an `.apex`-rooted candidate with no registered resolver
    /// fails fast at boot.
    @Test func candidateApexRootWithoutResolverFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ApexUpdateRequest.self)
            } _: { _, _ in }
        }
    }

    /// A computed `candidates` mints fresh declaration tokens — the token-stability lint rejects it.
    @Test func computedCandidatesFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ComputedCandidatesUpdateRequest.self)
            } _: { _, _ in }
        }
    }

    /// The read-plan token lint: a computed `dataRequirements` on a read factory fails fast too.
    @Test func computedDataRequirementsFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ComputedReadRequest.self)
            } _: { _, _ in }
        }
    }
}

// MARK: - Group 16: write response ↔ direct-serve parity

@Suite("Write route: response parity")
struct WriteRouteResponseParityTests {
    /// The write re-serves ITSELF through the read pipeline, so its response equals a direct serve
    /// of the same request: one `ResponseBody` factory (`BerthListVM`), reached by the write path or
    /// as a read — the generalization that replaced the refresh bridge.
    @Test func writeResponseMatchesDirectServe() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .writeRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)

            let vmRequest = try UpdateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateBerthBody(number: 55, dockName: "Bridged"),
                responseBody: nil
            )
            let writeReq = makeRequest(on: app)
            let viaWrite = try await writeReq.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))

            // The same request served directly as a read builds the same ResponseBody, post-write.
            let readReq = makeRequest(on: app)
            let viaServe = try await readReq.serve(vmRequest)

            #expect(viaWrite.berthNumbers == viaServe.berthNumbers)
            #expect(viaWrite.berthNames.sorted() == viaServe.berthNames.sorted())
        }
    }
}

// MARK: - Boot-fixture: unique-index migration (constraint-violation test)

/// Berth schema with a UNIQUE(number) constraint baked in at creation — SQLite cannot add a unique
/// index via ALTER TABLE, so the constraint must exist from the start. Same schema name as Berth.
struct UniqueNumberBerthMigration: AsyncMigration {
    var name: String {
        "UniqueNumberBerthMigration"
    }

    func prepare(on database: any Database) async throws {
        try await database.schema(Berth.schema).id()
            .field("number", .int, .required)
            .field("dock_name", .string, .required)
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .unique(on: "number")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Berth.schema).delete()
    }
}

/// Dock-crew pivot schema with a UNIQUE(dock_id) constraint — a dock accepts at most ONE pivot
/// row. Pre-seeding one occupying row makes a second attach (into the same dock) violate the
/// index, so the create+attach transaction's attach step fails on demand. Same schema name as
/// DockCrew; SQLite needs the unique index baked in at creation.
struct UniqueDockCrewMigration: AsyncMigration {
    var name: String {
        "UniqueDockCrewMigration"
    }

    func prepare(on database: any Database) async throws {
        try await database.schema(DockCrew.schema).id()
            .field("dock_id", .uuid, .required, .references(Dock.schema, "id"))
            .field("crew_member_id", .uuid, .required, .references(CrewMember.schema, "id"))
            .unique(on: "dock_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(DockCrew.schema).delete()
    }
}

// MARK: - Create-gate helpers (C1)

/// A fresh, empty dock in the seeded harbor — the create gate's probe container.
private func makeEmptyDock(named name: String, on db: any Database) async throws -> Dock {
    let harbor = try #require(try await Harbor.query(on: db).first())
    let pier = try #require(try await Pier.query(on: db).first())
    let dock = try Dock(name: name, pierId: pier.requireId(), harborId: harbor.requireId())
    try await dock.save(on: db)
    return dock
}

// MARK: - Group 6 additions: the create gate (C1)

@Suite("Write route: create gate")
struct WriteRouteCreateGateTests {
    /// ZERO grants: the create is not-found — no row lands, and the provider was consulted
    /// exactly once (the memo serves both the candidate load and the grant verdict).
    @Test func unauthorizedCreateWithZeroGrantsIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateBerthRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let dock = try await makeEmptyDock(named: "Zero Grant Dock", on: db)
            setGrants(app, []) // nothing granted at all

            let rowsBefore = try await Berth.query(on: db).count()
            let vmRequest = try CreateBerthRequest(
                query: .init(rootIdentity: dock.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateBerthBody(number: 7, dockName: "Nope"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let rowsAfter = try await Berth.query(on: db).count()
            #expect(rowsAfter == rowsBefore)
            #expect(grantCount(app) == 1)
        }
    }

    /// READ-ONLY grant: reading the dock's berths is allowed, creating into it is not —
    /// the create is not-found and no row lands.
    @Test func unauthorizedCreateWithReadOnlyGrantIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateBerthRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let dock = try await makeEmptyDock(named: "Read Only Dock", on: db)
            try setGrants(app, [berthGrant(dock, [.readRecords])]) // read, never create

            let rowsBefore = try await Berth.query(on: db).count()
            let vmRequest = try CreateBerthRequest(
                query: .init(rootIdentity: dock.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateBerthBody(number: 8, dockName: "Nope"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let rowsAfter = try await Berth.query(on: db).count()
            #expect(rowsAfter == rowsBefore)
            #expect(grantCount(app) == 1)
        }
    }

    /// The framework-level distinguishability pin: an EMPTY container with a `.createRecords`
    /// grant accepts the create — emptiness is not denial; the gate reads the grant verdict,
    /// never the (empty) candidate records.
    @Test func authorizedCreateIntoEmptyContainerSucceeds() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateBerthRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let dock = try await makeEmptyDock(named: "Empty Granted Dock", on: db)
            try setGrants(app, [berthGrant(dock, [.createRecords])])

            let vmRequest = try CreateBerthRequest(
                query: .init(rootIdentity: dock.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateBerthBody(number: 21, dockName: "Landed"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            _ = try await req.commitCreate(vmRequest, body: #require(vmRequest.requestBody))

            let created = try await berths(of: dock, on: db)
            #expect(created.count == 1)
            #expect(created.first?.number == 21)
        }
    }

    /// No authorization oracle: a DENIED create and a create into a DELETED container produce
    /// the same error shape (status equality) — denial is indistinguishable from absence.
    @Test func deniedCreateMatchesMissingContainerShape() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateBerthRequest.self)
        } _: { app, db in
            _ = try await seedHarbor(on: db)

            // DENIED: the dock exists; no grant covers it.
            let deniedDock = try await makeEmptyDock(named: "Denied Dock", on: db)
            let deniedIdentity = try deniedDock.modelIdentity

            // MISSING: the grant covers it, but the row is gone.
            let goneDock = try await makeEmptyDock(named: "Gone Dock", on: db)
            let goneIdentity = try goneDock.modelIdentity
            try setGrants(app, [berthGrant(goneDock, [.createRecords])])
            try await goneDock.delete(on: db)

            func createStatus(into root: ModelIdentity) async throws -> HTTPResponseStatus? {
                let vmRequest = CreateBerthRequest(
                    query: .init(rootIdentity: root),
                    sort: nil, fragment: nil,
                    requestBody: CreateBerthBody(number: 1, dockName: "X"),
                    responseBody: nil
                )
                do {
                    _ = try await makeRequest(on: app).commitCreate(vmRequest, body: #require(vmRequest.requestBody))
                    return nil
                } catch let abort as Abort {
                    return abort.status
                }
            }

            let deniedStatus = try await createStatus(into: deniedIdentity)
            let missingStatus = try await createStatus(into: goneIdentity)
            #expect(deniedStatus == .notFound)
            #expect(deniedStatus == missingStatus)
        }
    }
}

// MARK: - I2: verb–door coherence boot fixtures (plan-level probe)

/// A child declaring a `.create` scope, composed via Dock — the ONLY way a walked plan can carry
/// a `.createRecords` tuple with a non-empty path (deriveCandidatePlan's childless CandidateFactory
/// can never produce one); exercises the defense-in-depth branch directly.
private struct CreateLeafFactory: ComposableFactory {
    static let scope = LoadRequirement.create(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [scope]
    }
}

private struct CreateViaParentFactory: ComposableFactory {
    static var children: [ComposedChild] {
        [.child(CreateLeafFactory.self, via: Dock.self)]
    }
}

// MARK: - I2: verb–door coherence boot tests

@Suite("Write route: verb-door coherence")
struct WriteRouteVerbDoorTests {
    /// A delete registration whose candidates use the `.write` verb fails at boot; the message
    /// names both the declared verb and the door's.
    @Test func wrongVerbCandidatesFailFast() async throws {
        do {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: WrongVerbDeleteRequest.self)
            } _: { _, _ in }
            Issue.record("expected a boot throw for a .write candidate at the delete door")
        } catch let error as ContainmentError {
            guard case .invalidLoadPlan = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("writeRecords"))
            #expect(error.debugDescription.contains("deleteRecords"))
        }
    }

    /// A `.refinedByRequest`-marked candidate set fails at boot — a windowed candidate set would
    /// fabricate not-found for targets outside the window's page.
    @Test func refinedCandidatesFailFast() async throws {
        do {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: RefinedCandidatesUpdateRequest.self)
            } _: { _, _ in }
            Issue.record("expected a boot throw for .refinedByRequest candidates")
        } catch let error as ContainmentError {
            guard case .invalidLoadPlan = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("refinedByRequest"))
        }
    }

    /// A `.createRecords` tuple with intermediate hops is rejected (probe: the walked plan of a
    /// via-composed `.create` leaf — unreachable through deriveCandidatePlan, pinned directly).
    @Test func createCandidatesWithPathFailFast() async throws {
        try await withFluentTestApp { _ in } _: { app, _ in
            let plan = try RecordLoadPlan.walk(from: CreateViaParentFactory.self)
            do {
                try app.requireVerbDoorCoherence(
                    of: plan,
                    request: "CreatePathProbe",
                    writer: CreateBerthBody.self,
                    expectedOperation: .createRecords
                )
                Issue.record("expected a throw for a .create tuple with intermediate hops")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
                #expect(error.debugDescription.contains("intermediate hops"))
            }
        }
    }

    /// A DestroyRequest reaches the read door (no write overload) and fails fast: not yet supported.
    @Test func destroyRequestNotYetSupported() async throws {
        do {
            try await withFluentTestApp { app in
                try app.register(request: EchoDestroyRequest.self)
            } _: { _, _ in }
            Issue.record("expected a boot throw for a DestroyRequest at the read door")
        } catch let error as ContainmentError {
            guard case .unsupportedWriteProtocol = error else {
                Issue.record("wrong case: \(error)")
                return
            }
        }
    }
}

// MARK: - I3: createMember capability

@Suite("Write route: createMember capability")
struct CreateMemberCapabilityTests {
    /// `.siblings` create happy path: the new record persists and the attach is visible through
    /// the pivot (the container's siblings query returns it).
    @Test func siblingsCreateAttachesViaPivot() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let newCrew = CrewMember(name: "Zed")

            let req = makeRequest(on: app)
            try await req.createMember(newCrew, in: dock1.modelIdentity, on: db)

            let attached = try #require(try await Dock.find(dock1.requireId(), on: db))
            let names = try await attached.$crew.query(on: db).all().map(\.name)
            #expect(names.contains("Zed"))
        }
    }

    /// The create+attach transaction is atomic: when the pivot attach fails (the dock's unique
    /// pivot slot is already occupied by a pre-seeded row), the freshly-created sibling is rolled
    /// back — NO orphan crew row is committed. The crew table's row count is unchanged.
    @Test func siblingsAttachFailureRollsBackCreate() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app, uniqueDockCrew: true)
        } _: { app, db in
            // Minimal graph: one dock whose single unique pivot slot is already taken.
            let harbor = Harbor(name: "H")
            try await harbor.save(on: db)
            let pier = Pier(name: "P")
            try await pier.save(on: db)
            let dock = try Dock(name: "D", pierId: pier.requireId(), harborId: harbor.requireId())
            try await dock.save(on: db)
            let occupant = CrewMember(name: "Occupant")
            try await occupant.save(on: db)
            try await DockCrew(dockId: dock.requireId(), crewMemberId: occupant.requireId()).save(on: db)

            let crewBefore = try await CrewMember.query(on: db).count()
            let newCrew = CrewMember(name: "Would-be Orphan")
            let req = makeRequest(on: app)
            await #expect(throws: (any Error).self) {
                try await req.createMember(newCrew, in: dock.modelIdentity, on: db)
            }

            // The attach violated UNIQUE(dock_id); the transaction rolled back the created crew row.
            let crewAfter = try await CrewMember.query(on: db).count()
            #expect(crewAfter == crewBefore)
        }
    }

    /// A `.parent` relation is not a create scope — typed rejection, never a silent FK write.
    @Test func parentRelationIsNotACreateScope() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let pier = Pier(name: "Orphan Pier")

            let req = makeRequest(on: app)
            do {
                try await req.createMember(pier, in: dock1.modelIdentity, on: db)
                Issue.record("expected invalidCreateScope for a .parent relation")
            } catch let error as ContainmentError {
                guard case .invalidCreateScope = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }

    /// A container whose row is gone is not-found — a data condition, not a typed config error.
    @Test func containerRowGoneIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
        } _: { app, db in
            _ = try await seedHarbor(on: db)
            let dock = try await makeEmptyDock(named: "Ephemeral Dock", on: db)
            let identity = try dock.modelIdentity
            try await dock.delete(on: db)

            let fresh = Berth()
            fresh.number = 1
            fresh.dockName = "X"
            let req = makeRequest(on: app)
            do {
                try await req.createMember(fresh, in: identity, on: db)
                Issue.record("expected not-found for a gone container row")
            } catch let abort as Abort {
                #expect(abort.status == .notFound)
            }
        }
    }

    /// An unregistered container namespace is a configuration bug — its existing typed error.
    @Test func unregisteredNamespaceThrowsTyped() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            // A Berth is a record, never a registered container — its identity has no descriptor.
            let berth = try #require(try await berths(of: dock1, on: db).first)
            let fresh = CrewMember(name: "Lost")

            let req = makeRequest(on: app)
            do {
                try await req.createMember(fresh, in: berth.modelIdentity, on: db)
                Issue.record("expected unregisteredNamespace for a non-container identity")
            } catch let error as ContainmentError {
                guard case .unregisteredNamespace = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        }
    }
}

// MARK: - M2: POST + DELETE through the real HTTP pipeline

@Suite("Write route: HTTP pipeline")
struct WriteRouteHTTPPipelineTests {
    /// End-to-end POST: routes, binds the query, decodes the JSON body, creates, refreshes.
    @Test func postRoutesThroughRealPipeline() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try configureWriteContainers(app)
            try app.register(request: CreateBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .createRecords])])

            let vmRequest = try CreateBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let base = try #require(URL(string: "http://localhost"))
            let url = try #require(try base.appending(serverRequest: vmRequest))

            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            try buffer.writeBytes(JSONEncoder().encode(CreateBerthBody(number: 66, dockName: "Posted")))
            var headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            headers.contentType = .json
            let httpReq = Request(
                application: app, method: .POST, url: URI(string: url.absoluteString),
                headers: headers, collectedBody: buffer, on: app.eventLoopGroup.next()
            )

            let response = try await app.responder.respond(to: httpReq).get()
            #expect(response.status == .ok)
            let data = try #require(response.body.data)
            let refreshed: BerthListVM = try data.fromJSON()
            #expect(refreshed.berthNumbers.contains(66))
        }
    }

    /// End-to-end DELETE: routes, binds root + target from the URL, deletes, refreshes.
    @Test func deleteRoutesThroughRealPipeline() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try configureWriteContainers(app)
            try app.register(request: DeleteBerthRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            try setGrants(app, [berthGrant(dock1, [.readRecords, .deleteRecords])])
            let berth = try #require(try await berths(of: dock1, on: db).first)
            let goneNumber = berth.number

            let vmRequest = try DeleteBerthRequest(
                query: .init(rootIdentity: dock1.modelIdentity, target: berth.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let base = try #require(URL(string: "http://localhost"))
            let url = try #require(try base.appending(serverRequest: vmRequest))

            let headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            let httpReq = Request(
                application: app, method: .DELETE, url: URI(string: url.absoluteString),
                headers: headers, collectedBody: .init(), on: app.eventLoopGroup.next()
            )

            let response = try await app.responder.respond(to: httpReq).get()
            #expect(response.status == .ok)
            let data = try #require(response.body.data)
            let refreshed: BerthListVM = try data.fromJSON()
            #expect(!refreshed.berthNumbers.contains(goneNumber))
        }
    }
}
