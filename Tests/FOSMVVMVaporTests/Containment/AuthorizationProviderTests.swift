// AuthorizationProviderTests.swift
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

// Test-taxonomy discipline (C3 spec §Testing): C3's full contract — "the registered provider's
// grants scope every load" — becomes observable at a *public* surface only once C8's factory ships.
// Test 1 below is the CONTRACT test: it exercises only the public registration API
// (`Application.useContainerAuthorizationProvider(_:)`); its typed `.duplicateAuthorizationProvider`
// case assertion is a labeled COVERAGE RIDER reading package (`ContainmentError`) API. Tests 2-5
// (added in Task 2) are COVERAGE tests of the internal acquisition path via `@testable import
// FOSMVVMVapor` — sanctioned because that path has no public surface yet. No access level is
// widened for tests.

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import NIOConcurrencyHelpers
import Testing
import Vapor

/// Registers Workspace (the apex) + Board and adds the remaining workspace migrations.
/// CreateWorkspace/CreatePier run BEFORE CreateBoard — CreateBoard's DDL references both tables.
private func configureWorkspace(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
}

/// Mints a real Request via Vapor's public initializer — the entry's receiver.
private func makeRequest(on app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

private func cardNumbers(_ records: [any DataModel]) throws -> [Int] {
    try records.map { try #require($0 as? Card).number }
}

/// Vends no authorizations — only its type identity matters for the duplicate-registration test;
/// the scoping test reuses it as the unauthenticated/unprivileged-subject variant.
private struct EmptyProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        []
    }
}

/// A distinct provider TYPE (also vending `TestGrant`) — proves duplicate detection isn't fooled by
/// registering a different conforming type once one is already registered.
private struct OtherProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        []
    }
}

/// Resolves dock1 at request time — grants need the seeded board's identity, which exists only after
/// seeding in the test body — and vends a Card-read grant for that one container.
private struct Dock1CardReadProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        guard let dock1 = try await Board.query(on: request.db).filter(\.$name == "Board 1").first() else {
            return []
        }
        return try [TestGrant(
            authorizedContainer: dock1.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Card.modelIdentityNamespace]
        )]
    }
}

/// Counts invocations behind a lock — a locked class keeps the count synchronously readable in
/// `#expect` assertions (an actor's count would need an `await` the assertion can't take) — proves
/// fetch-when-first-needed-then-reused.
private final class CountingProvider: ContainerAuthorizationProvider {
    let invocations = NIOLockedValueBox(0)

    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        invocations.withLockedValue { $0 += 1 }
        return []
    }
}

/// Awaits real Fluent work (queries every board row) before minting Member-read grants — the
/// async-provider shape an app's session/token lookup takes.
private struct AsyncMembersGrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        try await Board.query(on: request.db).all().map { board in
            try TestGrant(
                authorizedContainer: board.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Member.modelIdentityNamespace]
            )
        }
    }
}

@Suite("ContainerAuthorizationProvider registration + acquisition (C3)")
struct AuthorizationProviderTests {
    /// Spec test 1 (contract): registration succeeds once; a second registration — same or a
    /// different provider type — throws `.duplicateAuthorizationProvider`, never silently replaces.
    @Test func duplicateProviderRegistrationThrows() async throws {
        try await withFluentTestApp { app in
            try app.useContainerAuthorizationProvider(EmptyProvider())
            for duplicate in 0..<2 {
                do {
                    // attempt 0: same type again; attempt 1: a different provider type
                    if duplicate == 0 {
                        try app.useContainerAuthorizationProvider(EmptyProvider())
                    } else {
                        try app.useContainerAuthorizationProvider(OtherProvider())
                    }
                    Issue.record("expected ContainmentError.duplicateAuthorizationProvider")
                } catch let error as ContainmentError {
                    guard case .duplicateAuthorizationProvider = error else {
                        Issue.record("wrong case: \(error)")
                        return
                    }
                }
            }
        } _: { _, _ in }
    }

    /// Spec test 2 (coverage): the registered provider's grants scope the load end-to-end through
    /// acquisition — dock1's cards load; dock2's identity projects empty; and (fresh app) a
    /// provider vending `[]` projects empty — the data-scoping invariant, never an error.
    @Test func providerGrantsScopeTheLoad() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useContainerAuthorizationProvider(Dock1CardReadProvider())
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let req = makeRequest(on: app)

            let dock1Records = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(try cardNumbers(dock1Records).sorted() == [1, 2, 3])

            let dock2Records = try await req.authorizedRecords(
                of: dock2.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(dock2Records.isEmpty)
        }

        // Fresh app: the unauthenticated/unprivileged-subject shape — empty grants, empty loads.
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useContainerAuthorizationProvider(EmptyProvider())
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(records.isEmpty)
        }
    }

    /// Spec test 3 (coverage): the provider is invoked once per `Request` — a second entry call on
    /// the same Request (different contained type) reads the memo; a fresh Request fetches again.
    @Test func providerIsInvokedOncePerRequest() async throws {
        let provider = CountingProvider()
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useContainerAuthorizationProvider(provider)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let req = makeRequest(on: app)

            _ = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            _ = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Member.self,
                for: .readRecords
            )
            #expect(provider.invocations.withLockedValue { $0 } == 1)

            _ = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(provider.invocations.withLockedValue { $0 } == 2)
        }
    }

    /// Spec test 4 (coverage): no registered provider ⇒ the entry throws `.noAuthorizationProvider`
    /// — a configuration bug must never masquerade as universal denial (empty results).
    @Test func missingProviderThrows() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            do {
                _ = try await makeRequest(on: app).authorizedRecords(
                    of: dock1.modelIdentity,
                    containing: Card.self,
                    for: .readRecords
                )
                Issue.record("expected ContainmentError.noAuthorizationProvider")
            } catch let error as ContainmentError {
                guard case .noAuthorizationProvider = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }

    /// Spec test 5 (coverage): a provider that awaits real Fluent work before minting grants
    /// composes with acquisition end-to-end — dock1's members loads; the un-granted Card type
    /// projects empty.
    @Test func asyncFluentProviderScopesEndToEnd() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useContainerAuthorizationProvider(AsyncMembersGrantProvider())
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let req = makeRequest(on: app)

            let members = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Member.self,
                for: .readRecords
            )
            #expect(members.count == 2)

            let cards = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(cards.isEmpty)
        }
    }
}
