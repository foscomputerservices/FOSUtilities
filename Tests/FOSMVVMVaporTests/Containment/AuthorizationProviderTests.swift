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

/// Registers Harbor (the apex) + Dock and adds the remaining harbor migrations.
/// CreateHarbor/CreatePier run BEFORE CreateDock — CreateDock's DDL references both tables.
private func configureHarbor(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
}

/// Mints a real Request via Vapor's public initializer — the entry's receiver.
private func makeRequest(on app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

private func berthNumbers(_ records: [any DataModel]) throws -> [Int] {
    try records.map { try #require($0 as? Berth).number }
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

/// Resolves dock1 at request time — grants need the seeded dock's identity, which exists only after
/// seeding in the test body — and vends a Berth-read grant for that one container.
private struct Dock1BerthReadProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        guard let dock1 = try await Dock.query(on: request.db).filter(\.$name == "Dock 1").first() else {
            return []
        }
        return try [TestGrant(
            authorizedContainer: dock1.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Berth.modelIdentityNamespace]
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

/// Awaits real Fluent work (queries every dock row) before minting CrewMember-read grants — the
/// async-provider shape an app's session/token lookup takes.
private struct AsyncCrewGrantProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        try await Dock.query(on: request.db).all().map { dock in
            try TestGrant(
                authorizedContainer: dock.modelIdentity,
                operations: [.readRecords],
                recordTypes: [CrewMember.modelIdentityNamespace]
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
    /// acquisition — dock1's berths load; dock2's identity projects empty; and (fresh app) a
    /// provider vending `[]` projects empty — the data-scoping invariant, never an error.
    @Test func providerGrantsScopeTheLoad() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
            try app.useContainerAuthorizationProvider(Dock1BerthReadProvider())
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let req = makeRequest(on: app)

            let dock1Records = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(try berthNumbers(dock1Records).sorted() == [1, 2, 3])

            let dock2Records = try await req.authorizedRecords(
                of: dock2.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(dock2Records.isEmpty)
        }

        // Fresh app: the unauthenticated/unprivileged-subject shape — empty grants, empty loads.
        try await withFluentTestApp { app in
            try configureHarbor(app)
            try app.useContainerAuthorizationProvider(EmptyProvider())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
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
            try configureHarbor(app)
            try app.useContainerAuthorizationProvider(provider)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let req = makeRequest(on: app)

            _ = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            _ = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: CrewMember.self,
                for: .readRecords
            )
            #expect(provider.invocations.withLockedValue { $0 } == 1)

            _ = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(provider.invocations.withLockedValue { $0 } == 2)
        }
    }

    /// Spec test 4 (coverage): no registered provider ⇒ the entry throws `.noAuthorizationProvider`
    /// — a configuration bug must never masquerade as universal denial (empty results).
    @Test func missingProviderThrows() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            do {
                _ = try await makeRequest(on: app).authorizedRecords(
                    of: dock1.modelIdentity,
                    containing: Berth.self,
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
    /// composes with acquisition end-to-end — dock1's crew loads; the un-granted Berth type
    /// projects empty.
    @Test func asyncFluentProviderScopesEndToEnd() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
            try app.useContainerAuthorizationProvider(AsyncCrewGrantProvider())
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let req = makeRequest(on: app)

            let crew = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: CrewMember.self,
                for: .readRecords
            )
            #expect(crew.count == 2)

            let berths = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(berths.isEmpty)
        }
    }
}
