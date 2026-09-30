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

private struct CountingGrantProvider: ModelAuthorizationProvider {
    func modelAuthorizations(for request: Request) async throws -> [TestGrant] {
        let box = request.application.storage[GrantBoxKey.self] ?? GrantBox()
        box.callCount += 1
        return box.grants
    }
}

private func configureWriteContainers(
    _ app: Application,
    uniqueCardNumber: Bool = false,
    uniqueBoardMember: Bool = false
) throws {
    app.storage[GrantBoxKey.self] = GrantBox()
    app.migrations.add(CreatePier()) // CreateBoard's DDL references piers
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(uniqueCardNumber ? UniqueNumberCardMigration() : CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(uniqueBoardMember ? UniqueBoardMemberMigration() : CreateBoardMember())
    try app.register(Quay.self, migration: CreateQuay())
    try app.register(Mooring.self, migration: CreateMooring()) // a leaf within the subject scope must be registered
    try app.useModelAuthorizationProvider(CountingGrantProvider())
}

/// Two quays, three moorings, and the subject scope's three cases for a write verb:
/// `reachedByExtension` sits in the granted quay; `reachedByName` sits in the other quay and a
/// grant names it; `reachedByNeither` sits beside it with no grant at all.
private struct SubjectWriteFixture {
    let reachedByExtension: Mooring
    let reachedByName: Mooring
    let reachedByNeither: Mooring
}

/// Seeds the fixture and sets grants covering `memberOperation` on the first quay's Moorings and
/// `modelOperation` on the named Mooring (both read too, for the refresh body).
private func seedSubjectWrite(
    _ app: Application,
    on db: any Database,
    memberOperation: ContainerOperation,
    modelOperation: ModelOperation
) async throws -> SubjectWriteFixture {
    let granted = Quay(name: "Granted Quay")
    try await granted.save(on: db)
    let other = Quay(name: "Other Quay")
    try await other.save(on: db)
    let byExtension = try Mooring(tag: "EXT", quayId: granted.requireId())
    let byName = try Mooring(tag: "NAMED", quayId: other.requireId())
    let byNeither = try Mooring(tag: "NEITHER", quayId: other.requireId())
    for mooring in [byExtension, byName, byNeither] {
        try await mooring.save(on: db)
    }
    try setGrants(app, [
        mooringGrant(granted, [.readRecords, memberOperation]),
        TestGrant(authorizedModel: byName.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read, modelOperation])
    ])
    return .init(reachedByExtension: byExtension, reachedByName: byName, reachedByNeither: byNeither)
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

/// Grants `ops` on Card in `board`.
private func cardGrant(_ board: Board, _ ops: [ContainerOperation]) throws -> TestGrant {
    try TestGrant(
        authorizedModel: board.modelIdentity,
        operations: ops,
        recordTypes: [Card.modelIdentityNamespace]
    )
}

private func cards(of board: Board, on db: any Database) async throws -> [Card] {
    try await Card.query(on: db).filter(\.$board.$id == board.requireId()).all()
}

/// Grants `ops` on Mooring in `quay`.
private func mooringGrant(_ quay: Quay, _ ops: [ContainerOperation]) throws -> TestGrant {
    try TestGrant(
        authorizedModel: quay.modelIdentity,
        operations: ops,
        recordTypes: [Mooring.modelIdentityNamespace]
    )
}

/// A quay with three moorings — the deletion fixtures' container.
private func seedQuay(on db: any Database) async throws -> Quay {
    let quay = Quay(name: "East Quay")
    try await quay.save(on: db)
    for tag in ["A", "B", "C"] {
        try await Mooring(tag: tag, quayId: quay.requireId()).save(on: db)
    }
    return quay
}

/// Every mooring row of `quay`, deleted ones included.
private func moorings(of quay: Quay, on db: any Database, includingDeleted: Bool = false) async throws -> [Mooring] {
    let query = try Mooring.query(on: db).filter(\.$quay.$id == quay.requireId())
    return try await (includingDeleted ? query.withDeleted() : query).all()
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
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let base = try #require(URL(string: "http://localhost"))
            let url = try #require(try base.appending(serverRequest: vmRequest))

            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            try buffer.writeBytes(JSONEncoder().encode(UpdateCardBody(number: 88, boardName: "Wired")))
            var headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            headers.contentType = .json
            let httpReq = Request(
                application: app, method: .PATCH, url: URI(string: url.absoluteString),
                headers: headers, collectedBody: buffer, on: app.eventLoopGroup.next()
            )

            let response = try await app.responder.respond(to: httpReq).get()
            #expect(response.status == .ok)
            let data = try #require(response.body.data)
            let refreshed: CardListVM = try data.fromJSON()
            #expect(refreshed.cardNumbers.contains(88))
        }
    }

    /// Happy path: the response IS refreshRequest()'s body reflecting post-write state.
    @Test func updateReflectsPostWriteState() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 99, boardName: "Renamed"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            let body = try #require(vmRequest.requestBody)
            let result = try await req.serveUpdate(vmRequest, body: body)

            #expect(result.cardNumbers.contains(99))
            // Persisted, not echoed: a fresh DB read agrees.
            let reloaded = try #require(try await Card.find(card.requireId(), on: db))
            #expect(reloaded.number == 99)
            #expect(reloaded.boardName == "Renamed")
        }
    }

    /// Candidates only: after commit (before the refresh) the cache holds the write-verb candidate
    /// entry and NO read-verb entry — the page's read plan was never loaded pre-apply.
    @Test func pageReadPlanNotLoadedPreApply() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 5, boardName: "X"),
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
            try app.register(request: UpdateCardRequest.self, app: app)
            // The pre-write prime reads through CardListRequest, so register it as a read too —
            // a write now derives only its OWN response plan, not a separate refresh request's.
            try app.register(request: CardListRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let req = makeRequest(on: app)
            // Prime the read-op cache with pre-write cards.
            try await req.executeRecordLoadPlan(for: CardListRequest(query: .init(scopeIdentity: dock1.modelIdentity)))

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 77, boardName: "Fresh"),
                responseBody: nil
            )
            let result = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            #expect(result.cardNumbers.contains(77)) // fresh, not the stale primed set
        }
    }

    /// The per-Request grant memo survives the write (invalidation touches records, never grants):
    /// the provider is consulted exactly once across the candidate load and the refresh read.
    @Test func grantMemoSurvivesTheWrite() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 3, boardName: "Y"),
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
            try configureWriteContainers(app, uniqueCardNumber: true)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let all = try await cards(of: dock1, on: db).sorted { $0.number < $1.number }
            let first = try #require(all.first) // number 1
            let second = try #require(all.dropFirst().first) // number 2

            // Update card #1 → number 2, colliding with card #2 on the unique index.
            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: first.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: second.number, boardName: "Collide"),
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
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .createRecords])])

            let vmRequest = try CreateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateCardBody(number: 42, boardName: "New Card"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            let result = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))

            #expect(result.cardNumbers.contains(42))
            // The container FK was set from the candidate scope: the new card belongs to dock1.
            let created = try await cards(of: dock1, on: db).filter { $0.number == 42 }
            #expect(created.count == 1)
        }
    }

    /// `.create` accepts no intermediates — compile-audit (a `via:` path would fan out to N
    /// containers; the create scope must be exactly one). This line only compiles because `.create`
    /// has no `via:` parameter.
    @Test func createTakesNoIntermediates() {
        _ = Card.creationPlan(within: .parent)
    }
}

// MARK: - Group 7: delete

@Suite("Write route: archive")
struct WriteRouteArchiveTests {
    /// WriteTargetProviding alone (no apply): the target is gone from the refresh body.
    @Test func deleteRemovesRecordFromRefresh() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: ArchiveMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .archiveRecords])])
            let mooring = try #require(try await moorings(of: quay, on: db).first)
            let goneTag = mooring.tag

            let vmRequest = try ArchiveMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: mooring.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let req = makeRequest(on: app)
            let result = try await req.serveArchive(vmRequest)

            #expect(!result.tags.contains(goneTag))
            let remaining = try await moorings(of: quay, on: db)
            #expect(!remaining.contains { $0.tag == goneTag })
        }
    }

    /// Archive is recoverable: the row is still there, carrying the delete timestamp Fluent set.
    @Test func archiveLeavesTheRowWithItsDeleteTimestamp() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: ArchiveMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .archiveRecords])])
            let mooring = try #require(try await moorings(of: quay, on: db).first)
            let archivedTag = mooring.tag

            let vmRequest = try ArchiveMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: mooring.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let req = makeRequest(on: app)
            _ = try await req.serveArchive(vmRequest)

            let all = try await moorings(of: quay, on: db, includingDeleted: true)
            let archived = try #require(all.first { $0.tag == archivedTag })
            #expect(archived.deletedAt != nil)
            #expect(all.count == 3)
        }
    }

    /// The archive verb needs a delete timestamp to mark: a model without one is refused at boot,
    /// naming both fixes.
    @Test func archiveRouteWithoutDeleteTimestampFailsAtBoot() async throws {
        do {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ArchiveCardRequest.self, app: app)
            } _: { _, _ in }
            Issue.record("expected a boot throw for an archive of a model with no delete timestamp")
        } catch let error as ServerRequestControllerError {
            #expect(error == .archiveUnsupported(request: "ArchiveCardRequest", model: "Card"))
            #expect(error.debugDescription.contains("deleted_at"))
            #expect(error.debugDescription.contains("DestroyRequest"))
        }
    }

    /// The same registration with a delete timestamp on the target boots and serves DELETE.
    @Test func archiveRouteWithTimestampBoots() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: ArchiveMooringRequest.self, app: app)
        } _: { app, _ in
            #expect(app.routes.all.contains { $0.method == .DELETE })
        }
    }
}

// MARK: - Group 7 twin: destroy

@Suite("Write route: destroy")
struct WriteRouteDestroyTests {
    /// A destroy request registers its own DELETE route — it no longer fails fast as unsupported.
    @Test func destroyRouteRegisters() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: DestroyMooringRequest.self, app: app)
        } _: { app, _ in
            let expected = DestroyMooringRequest.path.pathComponents.map(\.description)
            #expect(app.routes.all.contains { $0.method == .DELETE && $0.path.map(\.description) == expected })
        }
    }

    /// Destroy is unrecoverable: the row is gone even from a query that includes deleted rows.
    @Test func destroyRemovesTheRow() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: DestroyMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .destroyRecords])])
            let mooring = try #require(try await moorings(of: quay, on: db).first)
            let goneTag = mooring.tag

            let vmRequest = try DestroyMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: mooring.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let req = makeRequest(on: app)
            let result = try await req.serveDestroy(vmRequest)

            #expect(!result.tags.contains(goneTag))
            let all = try await moorings(of: quay, on: db, includingDeleted: true)
            #expect(all.count == 2)
            #expect(!all.contains { $0.tag == goneTag })
        }
    }
}

// MARK: - Writes within the subject scope

@Suite("Write route: candidates within the subject scope")
struct WriteRouteSubjectScopeTests {
    /// An update accepts a target reachable by either authority — the Mooring inside the granted
    /// Quay, and the Mooring a grant names — and the refresh lists the new tag: the subject-scope
    /// cache was dropped with the write, so the re-served body reflects post-write state.
    @Test func updateAcceptsEitherAuthorityAndRefreshesTheUnion() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: SubjectUpdateMooringRequest.self, app: app)
        } _: { app, db in
            let fixture = try await seedSubjectWrite(app, on: db, memberOperation: .writeRecords, modelOperation: .write)
            let req = makeRequest(on: app)

            let viaExtension = try SubjectUpdateMooringRequest(
                query: .init(target: fixture.reachedByExtension.modelIdentity),
                sort: nil, fragment: nil, requestBody: .init(tag: "EXT2"), responseBody: nil
            )
            let afterFirst = try await req.serveUpdate(viaExtension, body: #require(viaExtension.requestBody))
            #expect(afterFirst.tags == ["EXT2", "NAMED"])

            let viaName = try SubjectUpdateMooringRequest(
                query: .init(target: fixture.reachedByName.modelIdentity),
                sort: nil, fragment: nil, requestBody: .init(tag: "NAMED2"), responseBody: nil
            )
            let afterSecond = try await req.serveUpdate(viaName, body: #require(viaName.requestBody))
            #expect(afterSecond.tags == ["EXT2", "NAMED2"])
        }
    }

    /// A target reachable by neither authority is not-found — the same shape a missing row
    /// produces — and the row is untouched.
    @Test func updateRejectsATargetReachedByNeither() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: SubjectUpdateMooringRequest.self, app: app)
        } _: { app, db in
            let fixture = try await seedSubjectWrite(app, on: db, memberOperation: .writeRecords, modelOperation: .write)

            let vmRequest = try SubjectUpdateMooringRequest(
                query: .init(target: fixture.reachedByNeither.modelIdentity),
                sort: nil, fragment: nil, requestBody: .init(tag: "X"), responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let untouched = try #require(try await Mooring.find(fixture.reachedByNeither.requireId(), on: db))
            #expect(untouched.tag == "NEITHER")
        }
    }

    /// An archive accepts a target by either authority and rejects one by neither; each archived
    /// row keeps its delete timestamp and drops out of the refreshed list.
    @Test func archiveAcceptsEitherAuthorityRejectsNeither() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: SubjectArchiveMooringRequest.self, app: app)
        } _: { app, db in
            let fixture = try await seedSubjectWrite(app, on: db, memberOperation: .archiveRecords, modelOperation: .archive)
            let req = makeRequest(on: app)

            let afterExtension = try await req.serveArchive(SubjectArchiveMooringRequest(
                query: .init(target: fixture.reachedByExtension.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            ))
            #expect(afterExtension.tags == ["NAMED"])

            let afterName = try await req.serveArchive(SubjectArchiveMooringRequest(
                query: .init(target: fixture.reachedByName.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            ))
            #expect(afterName.tags == [])

            await #expect(throws: Abort.self) {
                _ = try await req.serveArchive(SubjectArchiveMooringRequest(
                    query: .init(target: fixture.reachedByNeither.modelIdentity),
                    sort: nil, fragment: nil, requestBody: nil, responseBody: nil
                ))
            }

            let all = try await Mooring.query(on: db).withDeleted().all()
            #expect(all.count == 3)
            #expect(all.first { $0.tag == "EXT" }?.deletedAt != nil)
            #expect(all.first { $0.tag == "NAMED" }?.deletedAt != nil)
            #expect(all.first { $0.tag == "NEITHER" }?.deletedAt == nil)
        }
    }

    /// A destroy accepts a target by either authority and rejects one by neither; the accepted
    /// rows are gone, the rejected one stays.
    @Test func destroyAcceptsEitherAuthorityRejectsNeither() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: SubjectDestroyMooringRequest.self, app: app)
        } _: { app, db in
            let fixture = try await seedSubjectWrite(app, on: db, memberOperation: .destroyRecords, modelOperation: .destroy)
            let req = makeRequest(on: app)

            let afterExtension = try await req.serveDestroy(SubjectDestroyMooringRequest(
                query: .init(target: fixture.reachedByExtension.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            ))
            #expect(afterExtension.tags == ["NAMED"])

            let afterName = try await req.serveDestroy(SubjectDestroyMooringRequest(
                query: .init(target: fixture.reachedByName.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            ))
            #expect(afterName.tags == [])

            await #expect(throws: Abort.self) {
                _ = try await req.serveDestroy(SubjectDestroyMooringRequest(
                    query: .init(target: fixture.reachedByNeither.modelIdentity),
                    sort: nil, fragment: nil, requestBody: nil, responseBody: nil
                ))
            }

            let remaining = try await Mooring.query(on: db).withDeleted().all()
            #expect(remaining.map(\.tag) == ["NEITHER"])
        }
    }

    /// Not-yours is indistinguishable from not-found: a target reachable by neither authority
    /// and an identity of a row that no longer exists both refuse with the same status.
    @Test func neitherAuthorityMatchesTheMissingRowShape() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: SubjectUpdateMooringRequest.self, app: app)
        } _: { app, db in
            let fixture = try await seedSubjectWrite(app, on: db, memberOperation: .writeRecords, modelOperation: .write)
            let gone = try Mooring(tag: "GONE", quayId: fixture.reachedByNeither.$quay.id)
            try await gone.save(on: db)
            let goneIdentity = try gone.modelIdentity
            try await gone.delete(force: true, on: db)
            let req = makeRequest(on: app)

            func status(for target: ModelIdentity) async -> HTTPResponseStatus? {
                let vmRequest = SubjectUpdateMooringRequest(query: .init(target: target), sort: nil, fragment: nil, requestBody: .init(tag: "X"), responseBody: nil)
                do {
                    _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
                    return nil
                } catch let abort as Abort {
                    return abort.status
                } catch {
                    return nil
                }
            }

            let neither = try await status(for: fixture.reachedByNeither.modelIdentity)
            let missing = await status(for: goneIdentity)
            #expect(neither == .notFound)
            #expect(neither == missing)
        }
    }

    /// A write within the request's container whose refresh body is subject-scoped re-serves
    /// fresh: the subject caches are dropped whichever scope the candidates were within.
    @Test func requestScopedWriteRefreshesASubjectScopedBody() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: MixedArchiveMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .archiveRecords])])
            let tags = try await moorings(of: quay, on: db).map(\.tag).sorted()
            let first = try #require(try await moorings(of: quay, on: db).first { $0.tag == tags[0] })
            let second = try #require(try await moorings(of: quay, on: db).first { $0.tag == tags[1] })
            let req = makeRequest(on: app)

            let afterFirst = try await req.serveArchive(MixedArchiveMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: first.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            ))
            #expect(afterFirst.tags == Array(tags[1...]))

            let afterSecond = try await req.serveArchive(MixedArchiveMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: second.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            ))
            #expect(afterSecond.tags == Array(tags[2...]))
        }
    }

    /// The verb gates both authorities: a read-only container grant and a read-only model grant
    /// make no Mooring a write candidate, so both targets are not-found.
    @Test func readOnlyGrantsAuthorizeNoWriteCandidate() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: SubjectUpdateMooringRequest.self, app: app)
        } _: { app, db in
            let fixture = try await seedSubjectWrite(app, on: db, memberOperation: .readRecords, modelOperation: .read)
            let req = makeRequest(on: app)

            for target in [fixture.reachedByExtension, fixture.reachedByName] {
                let vmRequest = try SubjectUpdateMooringRequest(
                    query: .init(target: target.modelIdentity),
                    sort: nil, fragment: nil, requestBody: .init(tag: "X"), responseBody: nil
                )
                await #expect(throws: Abort.self) {
                    _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
                }
            }
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
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)
            let originalNumber = card.number

            // number == -1 fails UpdateCardBody.validate.
            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: -1, boardName: "Nope"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: ValidationError.self) {
                _ = try await req.commitUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let reloaded = try #require(try await Card.find(card.requireId(), on: db))
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
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            // A card in dock2, but the request roots at dock1 — outside the candidate set.
            let foreignCard = try #require(try await cards(of: dock2, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: foreignCard.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 1, boardName: "Z"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
        }
    }

    /// The candidate set honors the write verb's operation in grant checks: a read-only grant
    /// authorizes no write candidate, so even the request's own card is not-found.
    @Test func candidateHonorsWriteVerbInGrantChecks() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords])]) // NO write grant
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 1, boardName: "Z"),
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
            // NOTE: UpdateCardRequest is deliberately NOT registered — no candidate plan exists.
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 1, boardName: "Z"),
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
        for mirror in [Mirror(reflecting: UpdateCardBody(number: 0, boardName: "")),
                       Mirror(reflecting: CreateCardBody(number: 0, boardName: ""))] {
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
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, _ in
            #expect(app.candidatePlan(for: UpdateCardRequest.self) != nil)
            #expect(app.recordLoadPlan(for: UpdateCardRequest.self) != nil) // its own response plan too
        }
    }

    /// A ReplaceRequest reaches the read door (no write overload) and fails fast: not yet supported.
    @Test func replaceRequestNotYetSupported() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try app.register(request: EchoReplaceRequest.self, app: app)
            } _: { _, _ in }
        }
    }

    /// A write-protocol conformer that misses the write constraints falls through to the read door
    /// and fails fast rather than registering GET-only.
    @Test func writeConformerAtReadDoorFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try app.register(request: SelfRefreshUpdateRequest.self, app: app)
            } _: { _, _ in }
        }
    }

    /// Candidate scope validation: a `.query`-rooted candidate whose query is not ScopedQuery
    /// fails fast at boot.
    @Test func candidateRequestScopeWithoutScopedQueryFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: NoRootUpdateRequest.self, app: app)
            } _: { _, _ in }
        }
    }

    /// Candidate scope validation: a candidate within `.application` with no registered application scope
    /// fails fast at boot.
    @Test func candidateApplicationScopeWithoutRegistrationFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ApplicationUpdateRequest.self, app: app)
            } _: { _, _ in }
        }
    }

    /// A creation plan within `.subject` is refused on the write registration path too — a
    /// create names the container it creates into.
    @Test func subjectScopedCreateCandidatesFailFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: SubjectCreateCardRequest.self, app: app)
            } _: { _, _ in }
        }
    }

    /// A computed `candidates` mints fresh declaration tokens — the token-stability lint rejects it.
    @Test func computedCandidatesFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ComputedCandidatesUpdateRequest.self, app: app)
            } _: { _, _ in }
        }
    }

    /// The read-plan token lint: a `loadingPlans` block minting its plans inline fails fast too.
    @Test func inlineLoadingPlansFailsFast() async throws {
        await #expect(throws: ContainmentError.self) {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: ComputedReadRequest.self, app: app)
            } _: { _, _ in }
        }
    }
}

// MARK: - Group 16: write response ↔ direct-serve parity

@Suite("Write route: response parity")
struct WriteRouteResponseParityTests {
    /// The write re-serves ITSELF through the read pipeline, so its response equals a direct serve
    /// of the same request: one `ResponseBody` factory (`CardListVM`), reached by the write path or
    /// as a read — the generalization that replaced the refresh bridge.
    @Test func writeResponseMatchesDirectServe() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try UpdateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: UpdateCardBody(number: 55, boardName: "Bridged"),
                responseBody: nil
            )
            let writeReq = makeRequest(on: app)
            let viaWrite = try await writeReq.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))

            // The same request served directly as a read builds the same ResponseBody, post-write.
            let readReq = makeRequest(on: app)
            let viaServe = try await readReq.serve(vmRequest)

            #expect(viaWrite.cardNumbers == viaServe.cardNumbers)
            #expect(viaWrite.cardNames.sorted() == viaServe.cardNames.sorted())
        }
    }
}

// MARK: - Boot-fixture: unique-index migration (constraint-violation test)

/// Card schema with a UNIQUE(number) constraint baked in at creation — SQLite cannot add a unique
/// index via ALTER TABLE, so the constraint must exist from the start. Same schema name as Card.
struct UniqueNumberCardMigration: AsyncMigration {
    var name: String {
        "UniqueNumberCardMigration"
    }

    func prepare(on database: any Database) async throws {
        try await database.schema(Card.schema).id()
            .field("number", .int, .required)
            .field("board_name", .string, .required)
            .field("board_id", .uuid, .required, .references(Board.schema, "id"))
            .unique(on: "number")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Card.schema).delete()
    }
}

/// Board-members pivot schema with a UNIQUE(board_id) constraint — a board accepts at most ONE pivot
/// row. Pre-seeding one occupying row makes a second attach (into the same board) violate the
/// index, so the create+attach transaction's attach step fails on demand. Same schema name as
/// BoardMember; SQLite needs the unique index baked in at creation.
struct UniqueBoardMemberMigration: AsyncMigration {
    var name: String {
        "UniqueBoardMemberMigration"
    }

    func prepare(on database: any Database) async throws {
        try await database.schema(BoardMember.schema).id()
            .field("board_id", .uuid, .required, .references(Board.schema, "id"))
            .field("member_id", .uuid, .required, .references(Member.schema, "id"))
            .unique(on: "board_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(BoardMember.schema).delete()
    }
}

// MARK: - Create-gate helpers (C1)

/// A fresh, empty board in the seeded workspace — the create gate's probe container.
private func makeEmptyBoard(named name: String, on db: any Database) async throws -> Board {
    let workspace = try #require(try await Workspace.query(on: db).first())
    let pier = try #require(try await Pier.query(on: db).first())
    let board = try Board(name: name, pierId: pier.requireId(), workspaceId: workspace.requireId())
    try await board.save(on: db)
    return board
}

// MARK: - Group 6 additions: the create gate (C1)

@Suite("Write route: create gate")
struct WriteRouteCreateGateTests {
    /// ZERO grants: the create is not-found — no row lands, and the provider was consulted
    /// exactly once (the memo serves both the candidate load and the grant verdict).
    @Test func unauthorizedCreateWithZeroGrantsIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let board = try await makeEmptyBoard(named: "Zero Grant Board", on: db)
            setGrants(app, []) // nothing granted at all

            let rowsBefore = try await Card.query(on: db).count()
            let vmRequest = try CreateCardRequest(
                query: .init(scopeIdentity: board.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateCardBody(number: 7, boardName: "Nope"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let rowsAfter = try await Card.query(on: db).count()
            #expect(rowsAfter == rowsBefore)
            #expect(grantCount(app) == 1)
        }
    }

    /// READ-ONLY grant: reading the board's cards is allowed, creating into it is not —
    /// the create is not-found and no row lands.
    @Test func unauthorizedCreateWithReadOnlyGrantIsNotFound() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let board = try await makeEmptyBoard(named: "Read Only Board", on: db)
            try setGrants(app, [cardGrant(board, [.readRecords])]) // read, never create

            let rowsBefore = try await Card.query(on: db).count()
            let vmRequest = try CreateCardRequest(
                query: .init(scopeIdentity: board.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateCardBody(number: 8, boardName: "Nope"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: Abort.self) {
                _ = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))
            }
            let rowsAfter = try await Card.query(on: db).count()
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
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let board = try await makeEmptyBoard(named: "Empty Granted Board", on: db)
            try setGrants(app, [cardGrant(board, [.createRecords])])

            let vmRequest = try CreateCardRequest(
                query: .init(scopeIdentity: board.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateCardBody(number: 21, boardName: "Landed"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            _ = try await req.commitCreate(vmRequest, body: #require(vmRequest.requestBody))

            let created = try await cards(of: board, on: db)
            #expect(created.count == 1)
            #expect(created.first?.number == 21)
        }
    }

    /// No authorization oracle: a DENIED create and a create into a DELETED container produce
    /// the same error shape (status equality) — denial is indistinguishable from absence.
    @Test func deniedCreateMatchesMissingContainerShape() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)

            // DENIED: the board exists; no grant covers it.
            let deniedBoard = try await makeEmptyBoard(named: "Denied Board", on: db)
            let deniedIdentity = try deniedBoard.modelIdentity

            // MISSING: the grant covers it, but the row is gone.
            let goneBoard = try await makeEmptyBoard(named: "Gone Board", on: db)
            let goneIdentity = try goneBoard.modelIdentity
            try setGrants(app, [cardGrant(goneBoard, [.createRecords])])
            try await goneBoard.delete(on: db)

            func createStatus(into root: ModelIdentity) async throws -> HTTPResponseStatus? {
                let vmRequest = CreateCardRequest(
                    query: .init(scopeIdentity: root),
                    sort: nil, fragment: nil,
                    requestBody: CreateCardBody(number: 1, boardName: "X"),
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

/// A child declaring a `.create` scope, composed via Board — the ONLY way a walked plan can carry
/// a `.createRecords` tuple with a non-empty path (deriveCandidatePlan's childless CandidateFactory
/// can never produce one); exercises the defense-in-depth branch directly.
private struct CreateLeafFactory: ComposableFactory {
    static let scope = Card.creationPlan(within: .parent)
    static var loadingPlans: LoadingPlans {
        scope
    }
}

private struct CreateViaParentFactory: ComposableFactory {
    static var children: [ComposedChild] {
        [.child(CreateLeafFactory.self, via: Board.self)]
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
                try app.register(request: WrongVerbArchiveRequest.self, app: app)
            } _: { _, _ in }
            Issue.record("expected a boot throw for a .write candidate at the archive door")
        } catch let error as ContainmentError {
            guard case .invalidLoadPlan = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(error.debugDescription.contains("writeRecords"))
            #expect(error.debugDescription.contains("archiveRecords"))
        }
    }

    /// A `.refinedByRequest`-marked candidate set fails at boot — a windowed candidate set would
    /// fabricate not-found for targets outside the window's page.
    @Test func refinedCandidatesFailFast() async throws {
        do {
            try await withFluentTestApp { app in
                try configureWriteContainers(app)
                try app.register(request: RefinedCandidatesUpdateRequest.self, app: app)
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
                    writer: CreateCardBody.self,
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

    /// A DestroyRequest whose Query/RequestBody miss the destroy overload's constraints reaches the
    /// read registration and fails fast — registering it GET-only would silently drop the write.
    @Test func destroyConformerAtReadRouteFailsFast() async throws {
        do {
            try await withFluentTestApp { app in
                try app.register(request: EchoDestroyRequest.self, app: app)
            } _: { _, _ in }
            Issue.record("expected a boot throw for a DestroyRequest at the read door")
        } catch let error as ContainmentError {
            guard case .writeRequestAtReadDoor = error else {
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
            let (dock1, _) = try await seedWorkspace(on: db)
            let newMembers = Member(name: "Zed")

            let req = makeRequest(on: app)
            try await req.createMember(newMembers, in: dock1.modelIdentity, on: db)

            let attached = try #require(try await Board.find(dock1.requireId(), on: db))
            let names = try await attached.$members.query(on: db).all().map(\.name)
            #expect(names.contains("Zed"))
        }
    }

    /// The create+attach transaction is atomic: when the pivot attach fails (the board's unique
    /// pivot slot is already occupied by a pre-seeded row), the freshly-created sibling is rolled
    /// back — NO orphan members row is committed. The members table's row count is unchanged.
    @Test func siblingsAttachFailureRollsBackCreate() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app, uniqueBoardMember: true)
        } _: { app, db in
            // Minimal graph: one board whose single unique pivot slot is already taken.
            let workspace = Workspace(name: "H")
            try await workspace.save(on: db)
            let pier = Pier(name: "P")
            try await pier.save(on: db)
            let board = try Board(name: "D", pierId: pier.requireId(), workspaceId: workspace.requireId())
            try await board.save(on: db)
            let occupant = Member(name: "Occupant")
            try await occupant.save(on: db)
            try await BoardMember(boardId: board.requireId(), memberId: occupant.requireId()).save(on: db)

            let membersBefore = try await Member.query(on: db).count()
            let newMembers = Member(name: "Would-be Orphan")
            let req = makeRequest(on: app)
            await #expect(throws: (any Error).self) {
                try await req.createMember(newMembers, in: board.modelIdentity, on: db)
            }

            // The attach violated UNIQUE(board_id); the transaction rolled back the created members row.
            let membersAfter = try await Member.query(on: db).count()
            #expect(membersAfter == membersBefore)
        }
    }

    /// A `.parent` relation is not a create scope — typed rejection, never a silent FK write.
    @Test func parentRelationIsNotACreateScope() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
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
            _ = try await seedWorkspace(on: db)
            let board = try await makeEmptyBoard(named: "Ephemeral Board", on: db)
            let identity = try board.modelIdentity
            try await board.delete(on: db)

            let fresh = Card()
            fresh.number = 1
            fresh.boardName = "X"
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
            let (dock1, _) = try await seedWorkspace(on: db)
            // A Card is a record, never a registered container — its identity has no descriptor.
            let card = try #require(try await cards(of: dock1, on: db).first)
            let fresh = Member(name: "Lost")

            let req = makeRequest(on: app)
            do {
                try await req.createMember(fresh, in: card.modelIdentity, on: db)
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
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .createRecords])])

            let vmRequest = try CreateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let base = try #require(URL(string: "http://localhost"))
            let url = try #require(try base.appending(serverRequest: vmRequest))

            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            try buffer.writeBytes(JSONEncoder().encode(CreateCardBody(number: 66, boardName: "Posted")))
            var headers = HTTPHeaders([(HTTPHeaders.Name.acceptLanguage.description, "en")])
            headers.contentType = .json
            let httpReq = Request(
                application: app, method: .POST, url: URI(string: url.absoluteString),
                headers: headers, collectedBody: buffer, on: app.eventLoopGroup.next()
            )

            let response = try await app.responder.respond(to: httpReq).get()
            #expect(response.status == .ok)
            let data = try #require(response.body.data)
            let refreshed: CardListVM = try data.fromJSON()
            #expect(refreshed.cardNumbers.contains(66))
        }
    }

    /// End-to-end DELETE: routes, binds root + target from the URL, deletes, refreshes.
    @Test func deleteRoutesThroughRealPipeline() async throws {
        try await withFluentTestApp { app in
            try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
            try configureWriteContainers(app)
            try app.register(request: ArchiveMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .archiveRecords])])
            let mooring = try #require(try await moorings(of: quay, on: db).first)
            let goneTag = mooring.tag

            let vmRequest = try ArchiveMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: mooring.modelIdentity),
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
            let refreshed: MooringListVM = try data.fromJSON()
            #expect(!refreshed.tags.contains(goneTag))
        }
    }
}

// MARK: - The request's own error type, and the commit's transaction

/// Lets the update reach the database, then refuses it the way the model's own rules do — the
/// route must answer with the *request's* error type, and the write must not survive.
private struct RefusingCardUpdate: ModelMiddleware {
    func update(model: Card, on db: any Database, next: any AnyModelResponder) -> EventLoopFuture<Void> {
        next.update(model, on: db).flatMapThrowing {
            throw ValidationError(
                validation: .init(
                    status: .error,
                    fieldId: #fieldId(\Card.number),
                    message: .constant("the model refused this card")
                )
            )
        }
    }
}

/// Inserts the new row, then throws for the one number the rollback test creates — so that row
/// exists inside the transaction and nowhere after it, while the seed creates cards normally.
private struct FailingCardCreate: ModelMiddleware {
    static let refusedNumber = 77

    func create(model: Card, on db: any Database, next: any AnyModelResponder) -> EventLoopFuture<Void> {
        next.create(model, on: db).flatMapThrowing {
            guard model.number == Self.refusedNumber else {
                return
            }
            throw Abort(.conflict)
        }
    }
}

@Suite("Write route: typed refusals and the commit transaction")
struct WriteRouteTypedErrorTests {
    /// The body's own rules refuse: the client decodes `CardWriteRefusal`, not `ValidationError`.
    @Test func bodyValidationRethrowsRequestResponseError() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: TypedErrorUpdateRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)

            let vmRequest = try TypedErrorUpdateRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: TypedErrorUpdateBody(number: -1, boardName: "Refused"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            let refusal = await #expect(throws: CardWriteRefusal.self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
            #expect(refusal?.validations.count == 1)
        }
    }

    /// A refusal raised during the save arrives as the request's error type too, and the write is
    /// rolled back with it.
    @Test func writeRouteRethrowsRequestResponseError() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            app.databases.middleware.use(RefusingCardUpdate(), on: .sqlite)
            try app.register(request: TypedErrorUpdateRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .writeRecords])])
            let card = try #require(try await cards(of: dock1, on: db).first)
            let originalNumber = card.number

            let vmRequest = try TypedErrorUpdateRequest(
                query: .init(scopeIdentity: dock1.modelIdentity, target: card.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: TypedErrorUpdateBody(number: 55, boardName: "Refused"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            let refusal = await #expect(throws: CardWriteRefusal.self) {
                _ = try await req.serveUpdate(vmRequest, body: #require(vmRequest.requestBody))
            }
            #expect(refusal?.validations.count == 1)

            let after = try await cards(of: dock1, on: db)
            #expect(after.contains { $0.number == originalNumber })
            #expect(!after.contains { $0.number == 55 })
        }
    }

    /// The model's own rules refuse the archive: the client decodes `MooringWriteRefusal`, the
    /// message inside is about the model, and the row is untouched.
    @Test func archiveRefusedByTheModelArrivesAsTheRequestError() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: TypedErrorArchiveMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .archiveRecords])])
            let refused = try Mooring(tag: Mooring.refusedTag, quayId: quay.requireId())
            try await refused.save(on: db)

            let vmRequest = try TypedErrorArchiveMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: refused.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let req = makeRequest(on: app)
            let refusal = await #expect(throws: MooringWriteRefusal.self) {
                _ = try await req.serveArchive(vmRequest)
            }

            #expect(refusal?.validations.count == 1)
            #expect(refusal?.validations.first?.messages.first?.addressesModel == true)

            let still = try #require(try await moorings(of: quay, on: db).first { $0.tag == Mooring.refusedTag })
            #expect(still.deletedAt == nil)
        }
    }

    /// The destroy twin: the same refusal, the same typed error, and the row is still there.
    @Test func destroyRefusedByTheModelArrivesAsTheRequestError() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            try app.register(request: TypedErrorDestroyMooringRequest.self, app: app)
        } _: { app, db in
            let quay = try await seedQuay(on: db)
            try setGrants(app, [mooringGrant(quay, [.readRecords, .destroyRecords])])
            let refused = try Mooring(tag: Mooring.refusedTag, quayId: quay.requireId())
            try await refused.save(on: db)

            let vmRequest = try TypedErrorDestroyMooringRequest(
                query: .init(scopeIdentity: quay.modelIdentity, target: refused.modelIdentity),
                sort: nil, fragment: nil, requestBody: nil, responseBody: nil
            )
            let req = makeRequest(on: app)
            let refusal = await #expect(throws: MooringWriteRefusal.self) {
                _ = try await req.serveDestroy(vmRequest)
            }

            #expect(refusal?.validations.count == 1)
            #expect(refusal?.validations.first?.messages.first?.addressesModel == true)

            let all = try await moorings(of: quay, on: db, includingDeleted: true)
            #expect(all.contains { $0.tag == Mooring.refusedTag })
        }
    }

    /// The create commit is one transaction: a throw after the row lands leaves no row behind.
    @Test func createRollsBackWhenTheWriteThrows() async throws {
        try await withFluentTestApp { app in
            try configureWriteContainers(app)
            app.databases.middleware.use(FailingCardCreate(), on: .sqlite)
            try app.register(request: CreateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [cardGrant(dock1, [.readRecords, .createRecords])])

            let vmRequest = try CreateCardRequest(
                query: .init(scopeIdentity: dock1.modelIdentity),
                sort: nil, fragment: nil,
                requestBody: CreateCardBody(number: 77, boardName: "Rolled Back"),
                responseBody: nil
            )
            let req = makeRequest(on: app)
            await #expect(throws: (any Error).self) {
                _ = try await req.serveCreate(vmRequest, body: #require(vmRequest.requestBody))
            }

            let all = try await cards(of: dock1, on: db)
            #expect(!all.contains { $0.number == 77 })
        }
    }
}
