// RegistrationHeaderTests.swift
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

// Spec §3.4 / §6, test group 5: every served response that executed a RecordLoadPlan carries the
// plan's staleness surface — its resolved roots plus every touched container — as the
// `X-FOS-Registrations` response header (a JSON array of ModelIdentity via the frozen default
// coder). Exercised through the real HTTP responder so the executor's deposit reaches the shared
// `buildResponse` on the same Request the header rides.

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

/// A read within `.application` whose cards load through Board — so its registration set's roots (the
/// Workspace) and touched containers (each Board) are DISTINCT, proving both halves land in the header.
private struct WorkspacePageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = WorkspaceCardsRequest

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
        try .init(cardNumbers: context.records(cards).map(\.number).sorted())
    }
}

private final class WorkspaceCardsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: WorkspacePageVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: WorkspacePageVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

/// A zero-data body: no ``ComposableFactory``, no plan — so serving it executes no
/// RecordLoadPlan and the response carries NO registration header.
private struct PlainVM: RequestableViewModel, VaporResponseBodyFactory {
    typealias Request = PlainRequest

    var vmId = ViewModelId()
    var value: Int = 0

    init() {}
    init(value: Int) {
        self.value = value
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context _: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init(value: 7)
    }
}

private final class PlainRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: PlainVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: PlainVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - The subject scope: the subject's own graph (Account ⊃ Assignment) and a subject-scoped read

/// The subject as a container: an Account holds its Assignments (the grant rows), so a written
/// Assignment inverts to the Account — the identity a subject-scoped response registers.
final class Account: ContainerDataModel, @unchecked Sendable {
    static let schema = "accounts"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Assignment.self]
    }

    static var containment: [ContainmentRelation] {
        [.children(\Account.$assignments)]
    }

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Children(for: \.$account) var assignments: [Assignment]
    init() {}
    init(name: String) {
        self.name = name
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class Assignment: DataModel, @unchecked Sendable {
    static let schema = "assignments"
    @ID(key: .id) var id: UUID?
    @Field(key: "note") var note: String
    @Parent(key: "account_id") var account: Account
    init() {}
    init(note: String, accountId: ModelIdType) {
        self.note = note
        $account.id = accountId
    }

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

struct CreateAccount: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Account.schema).id().field("name", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Account.schema).delete()
    }
}

struct CreateAssignment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Assignment.schema).id()
            .field("note", .string, .required)
            .field("account_id", .uuid, .required, .references(Account.schema, "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Assignment.schema).delete()
    }
}

/// A read with no container to name: the Boards the subject's grants reach.
private struct SubjectBoardsVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = SubjectBoardsRequest

    static let boards = Board.loadingPlan(.read, within: .subject)
    static var loadingPlans: LoadingPlans {
        boards
    }

    var vmId = ViewModelId()
    var boardNames: [String] = []

    init() {}
    init(boardNames: [String]) {
        self.boardNames = boardNames
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        try .init(boardNames: context.records(boards).map(\.name).sorted())
    }
}

private final class SubjectBoardsRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectBoardsVM?

    init(query _: EmptyQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: SubjectBoardsVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

/// The subject's identity a test vends (nil by default — the provider's own default answer).
private struct SubjectKey: StorageKey {
    typealias Value = ModelIdentity
}

/// The shipped provider path plus the vended subject: grants from ``TestGrantsKey``, the subject
/// from ``SubjectKey``.
private struct SubjectVendingProvider: ModelAuthorizationProvider {
    func modelAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[TestGrantsKey.self] ?? []
    }

    func subjectIdentity(for request: Request) async throws -> ModelIdentity? {
        request.application.storage[SubjectKey.self]
    }
}

// MARK: - Harness

/// Registers the Workspace → Board → Card graph and drives auth through the storage-backed grants
/// provider (grants are set per test, after seeding, once identities exist).
private func configureWorkspace(_ app: Application) throws {
    try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.useModelAuthorizationProvider(TestGrantsProvider())
}

/// The Workspace graph beside the subject's own (Account ⊃ Assignment), live enabled, the
/// subject vended by the provider.
private func configureSubjectWorkspace(_ app: Application) throws {
    try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
    try app.register(Account.self, migration: CreateAccount())
    app.migrations.add(CreateAssignment())
    try app.useModelAuthorizationProvider(SubjectVendingProvider())
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

private func registrationSet(from response: Vapor.Response) throws -> Set<ModelIdentity>? {
    guard let value = response.headers.first(name: ModelIdentity.registrationsHeader) else {
        return nil
    }
    let identities: [ModelIdentity] = try value.fromJSON()
    return Set(identities)
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

@Suite("Live invalidation: X-FOS-Registrations header")
struct RegistrationHeaderTests {
    /// A registered GET whose `.application` plan resolves against the Workspace graph carries the
    /// executed plan's set — the Workspace root PLUS every Board the cards loaded from.
    @Test func servedGetCarriesExecutedPlanSet() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try registerWorkspaceApplicationScope(app)
            try app.register(request: WorkspaceCardsRequest.self, app: app)
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

            let response = try await getResponse(app, for: WorkspaceCardsRequest())
            #expect(response.status == .ok)

            let expected: Set<ModelIdentity> = try [
                workspace.modelIdentity,
                dock1.modelIdentity,
                dock2.modelIdentity
            ]
            let carried = try #require(try registrationSet(from: response))
            #expect(carried == expected)
        }
    }

    /// A write door (PATCH) responds with the REFRESHED set: the write re-serves itself through the
    /// genuine read pipeline, whose executor deposits the set the refresh depended on.
    @Test func writeDoorCarriesRefreshedSet() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.register(request: UpdateCardRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [
                cardReadGrant(
                    container: dock1.modelIdentity,
                    [.readRecords, .writeRecords],
                    types: [Card.modelIdentityNamespace]
                )
            ])
            let card = try #require(try await Card.query(on: db).filter(\.$board.$id == dock1.requireId()).first())

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

            let carried = try #require(try registrationSet(from: response))
            #expect(try carried == [dock1.modelIdentity])
        }
    }

    /// §6 round-trip pin: the header value decodes (defaultDecoder), re-encodes (defaultEncoder),
    /// and decodes again to the SAME set — a behavioral round-trip, not a byte assertion.
    @Test func headerValueRoundTrips() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.register(request: CardListRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [
                cardReadGrant(
                    container: dock1.modelIdentity,
                    [.readRecords],
                    types: [Card.modelIdentityNamespace]
                )
            ])

            let response = try await getResponse(app, for: CardListRequest(query: .init(scopeIdentity: dock1.modelIdentity)))
            #expect(response.status == .ok)

            let value = try #require(response.headers.first(name: ModelIdentity.registrationsHeader))
            let decoded: [ModelIdentity] = try value.fromJSON()
            let reencoded = try decoded.toJSON()
            let redecoded: [ModelIdentity] = try reencoded.fromJSON()

            #expect(Set(decoded) == Set(redecoded))
            #expect(try Set(decoded) == [dock1.modelIdentity])
        }
    }

    /// A response within the subject scope registers every bound model — both Boards the
    /// Workspace grant extends to — and the subject the provider vends.
    @Test func subjectScopedResponseRegistersBoundModelsAndSubject() async throws {
        try await withFluentTestApp { app in
            try configureSubjectWorkspace(app)
            try app.register(request: SubjectBoardsRequest.self, app: app)
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let workspace = try #require(try await Workspace.query(on: db).first())
            let account = Account(name: "Alice's account")
            try await account.save(on: db)
            app.storage[SubjectKey.self] = try account.modelIdentity
            try setGrants(app, [
                cardReadGrant(container: workspace.modelIdentity, [.readRecords], types: [Board.modelIdentityNamespace])
            ])

            let response = try await getResponse(app, for: SubjectBoardsRequest())
            #expect(response.status == .ok)

            let expected: Set<ModelIdentity> = try [dock1.modelIdentity, dock2.modelIdentity, account.modelIdentity]
            let carried = try #require(try registrationSet(from: response))
            #expect(carried == expected)
        }
    }

    /// With no subject vended (the provider's default), the response registers the bound models
    /// alone; grant changes then reach a client on its next fetch.
    @Test func subjectScopedResponseWithoutVendedSubjectRegistersBoundModelsOnly() async throws {
        try await withFluentTestApp { app in
            try configureSubjectWorkspace(app)
            try app.register(request: SubjectBoardsRequest.self, app: app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            try setGrants(app, [
                TestGrant(authorizedModel: dock1.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ])

            let response = try await getResponse(app, for: SubjectBoardsRequest())
            #expect(response.status == .ok)

            let carried = try #require(try registrationSet(from: response))
            #expect(try carried == [dock1.modelIdentity])
        }
    }

    /// The grant model declared as the subject's child: writing an Assignment emits the Account's
    /// identity through the existing invert — exactly what the subject-scoped response registered,
    /// so the subject's live lists refresh when a grant changes.
    @Test func grantWriteEmitsTheSubjectIdentity() async throws {
        try await withFluentTestApp { app in
            try configureSubjectWorkspace(app)
            try app.register(request: SubjectBoardsRequest.self, app: app)
        } _: { app, db in
            _ = try await seedWorkspace(on: db)
            let account = Account(name: "Alice's account")
            try await account.save(on: db)
            let accountIdentity = try account.modelIdentity
            app.storage[SubjectKey.self] = accountIdentity
            try setGrants(app, [])

            let response = try await getResponse(app, for: SubjectBoardsRequest())
            #expect(try registrationSet(from: response) == [accountIdentity])

            let hub = try #require(app.invalidationHub)
            var events = await hub.subscribe().makeAsyncIterator()
            let assignment = try Assignment(note: "read Board 1", accountId: account.requireId())
            try await assignment.save(on: db)

            let emitted = try #require(await events.next())
            #expect(emitted.contains(accountIdentity))
            #expect(try emitted == [assignment.modelIdentity, accountIdentity])
        }
    }

    /// A response whose request executed NO plan (a zero-data body) carries no header at all.
    @Test func noPlanCarriesNoHeader() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.register(request: PlainRequest.self, app: app)
        } _: { app, _ in
            let response = try await getResponse(app, for: PlainRequest())
            #expect(response.status == .ok)
            #expect(try registrationSet(from: response) == nil)
        }
    }
}
