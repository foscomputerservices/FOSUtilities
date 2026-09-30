// FormerPlanSpellingsTests.swift
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

// The one file that still SPEAKS the former spellings — `dataRequirements`,
// `LoadRequirement.read(_:in: .newRoot(.query))`, `RootedQuery.rootIdentity`. An app written
// against them must keep booting and serving for one release, so this suite registers such a
// factory through the shipped route door and serves it end to end. Every declaration here is
// `@available(*, deprecated)` so the deprecation warnings it would otherwise raise stay inside
// this file.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor
import VaporTesting

// MARK: - Fixtures in the former spellings

/// A query that names its container under the former protocol and property name.
@available(*, deprecated, message: "exercises the former RootedQuery spelling")
private struct FormerBoardQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

/// A read whose plan is declared the former way: a `LoadRequirement` handle listed in
/// `dataRequirements`, rooted with `.newRoot(.query)`.
@available(*, deprecated, message: "exercises the former dataRequirements spelling")
private struct FormerCardListVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = FormerCardListRequest

    static let cards = LoadRequirement.read(Card.self, in: .newRoot(.query))

    static var dataRequirements: [any DataRequirement] {
        [cards]
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
        try .init(cardNumbers: context.records(Self.cards).map(\.number).sorted())
    }
}

@available(*, deprecated, message: "exercises the former spellings")
private final class FormerCardListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = FormerBoardQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: FormerBoardQuery?
    var responseBody: FormerCardListVM?

    init(query: FormerBoardQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: FormerCardListVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Harness

/// Boots the Workspace → Board → Card graph with the storage-backed grant provider, the YAML
/// localization store, and FOS `ErrorMiddleware` — the same shape the served read tests use.
private func withFormerSpellingsApp(
    configure: @Sendable (Application) throws -> Void,
    _ body: @Sendable (Application, any Database) async throws -> Void
) async throws {
    try await withFluentTestApp { app in
        try app.initYamlLocalization(bundle: Bundle.module, resourceDirectoryName: "TestYAML")
        app.middleware = .init()
        app.middleware.use(FOSMVVMVapor.ErrorMiddleware.default(environment: app.environment))
        app.migrations.add(CreatePier()) // CreateBoard's DDL references piers
        try app.register(Workspace.self, migration: CreateWorkspace())
        try app.register(Board.self, migration: CreateBoard())
        app.migrations.add(CreateCard())
        app.migrations.add(CreateMember())
        app.migrations.add(CreateBoardMember())
        try app.useModelAuthorizationProvider(TestGrantsProvider())
        try configure(app)
    } _: { app, db in
        try await body(app, db)
    }
}

// MARK: - The former grant and provider spellings, through the engine

/// A grant written before the model-level axis: `authorizedContainer`, the member question only.
@available(*, deprecated, message: "exercises the former spellings")
private struct FormerGrant: ContainerAuthorization {
    let authorizedContainer: ModelIdentity
    let operations: [ContainerOperation]
    let recordTypes: [ModelNamespace]

    func authorizes(_ operation: ContainerOperation, ofType recordType: any FOSMVVM.Model.Type, in container: ModelIdentity) -> Bool {
        container == authorizedContainer && operations.authorizes(operation) && recordTypes.contains(recordType.modelIdentityNamespace)
    }
}

private struct FormerGrantsKey: StorageKey {
    typealias Value = [ModelIdentity]
}

/// A provider written before the rename: `containerAuthorizations(for:)` only.
@available(*, deprecated, message: "exercises the former spellings")
private struct FormerGrantsProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [FormerGrant] {
        (request.application.storage[FormerGrantsKey.self] ?? []).map {
            FormerGrant(authorizedContainer: $0, operations: [.readRecords], recordTypes: [Card.modelIdentityNamespace])
        }
    }
}

// MARK: - Tests

@Suite("Former plan spellings still boot and serve")
struct FormerPlanSpellingsTests {
    /// The former `dataRequirements` + `.newRoot(.query)` declaration derives a plan through the
    /// shipped route door, and that plan's one tuple is scoped `within: .request` — the same
    /// tuple the new spelling produces.
    @available(*, deprecated, message: "exercises the former spellings")
    @Test func formerDeclarationDerivesARequestScopedPlan() async throws {
        try await withFormerSpellingsApp { app in
            try app.register(request: FormerCardListRequest.self, app: app)
        } _: { app, _ in
            let plan = try #require(app.recordLoadPlan(for: FormerCardListRequest.self))
            #expect(plan.tuples.count == 1)
            let tuple = try #require(plan.tuples.first)
            #expect(tuple.root == .request)
            #expect(tuple.path.isEmpty)
            #expect(tuple.operation == .readRecords)
            #expect(ObjectIdentifier(tuple.recordType) == ObjectIdentifier(Card.self))
        }
    }

    /// The former spellings LOAD: the query's `rootIdentity` binds the request scope, the
    /// `LoadRequirement` handle reads its records back in the projection, and the served body
    /// carries them.
    @available(*, deprecated, message: "exercises the former spellings")
    @Test func formerDeclarationServesItsRecords() async throws {
        try await withFormerSpellingsApp { app in
            try app.register(request: FormerCardListRequest.self, app: app)
        } _: { app, db in
            let (board1, _) = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedModel: board1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Card.modelIdentityNamespace]
            )]

            let request = try FormerCardListRequest(query: .init(rootIdentity: board1.modelIdentity))
            try await app.testing().test(request) { response in
                #expect(response.status == .ok)
                let body = try #require(response.body)
                #expect(body.cardNumbers == [1, 2, 3])
            }
        }
    }

    /// The former registration spelling forwards: `useApexContainerResolver(_:)` registers the
    /// application scope, so a second registration through either spelling is the duplicate.
    /// A grant declaring only `authorizedContainer`, vended by a provider declaring only
    /// `containerAuthorizations(for:)` and registered through `useContainerAuthorizationProvider(_:)`,
    /// still scopes a load through the engine exactly as before.
    @available(*, deprecated, message: "exercises the former useApexContainerResolver spelling")
    @available(*, deprecated, message: "exercises the former spellings")
    @Test func formerGrantAndProviderStillScopeALoad() async throws {
        try await withFluentTestApp { app in
            app.migrations.add(CreatePier())
            try app.register(Workspace.self, migration: CreateWorkspace())
            try app.register(Board.self, migration: CreateBoard())
            app.migrations.add(CreateCard())
            app.migrations.add(CreateMember())
            app.migrations.add(CreateBoardMember())
            try app.useContainerAuthorizationProvider(FormerGrantsProvider())
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            app.storage[FormerGrantsKey.self] = try [dock1.modelIdentity]
            let req = Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())

            let granted = try await req.authorizedRecords(of: dock1.modelIdentity, containing: Card.self, for: .readRecords)
            #expect(granted.count == 3)
            let denied = try await req.authorizedRecords(of: dock2.modelIdentity, containing: Card.self, for: .readRecords)
            #expect(denied.isEmpty)
        }
    }

    @Test func formerResolverSpellingRegistersTheApplicationScope() async throws {
        try await withFluentTestApp { app in
            let workspace = Workspace(name: "Top Workspace")
            workspace.id = ModelIdType()
            let identity = try workspace.modelIdentity
            try app.useApexContainerResolver { _ in identity }
            #expect(app.applicationScope != nil)
            do {
                try app.useApplicationScope { _ in identity }
                Issue.record("expected ContainmentError.duplicateApplicationScope")
            } catch let error as ContainmentError {
                guard case .duplicateApplicationScope = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        } _: { _, _ in }
    }
}
