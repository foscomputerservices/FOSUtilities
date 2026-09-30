// AnchoredEngineTests.swift
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

// Test-taxonomy discipline: the anchored provider-driven test reads the internal acquisition
// entry via `@testable import FOSMVVMVapor` (sanctioned — that path has no public surface yet,
// same posture as AuthorizationProviderTests). No access level is widened for tests.
// The C8 audit removed the direct `authorizedBy:` engine entry, so grants reach the engine through
// the shipped provider path: each test seeds `TestGrantsKey` before a Request's first load and the
// registered `TestGrantsProvider` vends exactly that set (fetched + memoized once per Request).

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

/// Registers Workspace (the top container) + Board and adds the remaining workspace migrations.
/// CreateWorkspace/CreatePier run BEFORE CreateBoard — CreateBoard's DDL references both tables.
private func configureWorkspace(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Workspace.self, migration: CreateWorkspace())
    try app.register(Board.self, migration: CreateBoard())
    app.migrations.add(CreateCard())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateBoardMember())
}

/// Mints a real Request via Vapor's public initializer — the engine's receiver.
private func makeRequest(on app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

private func cardNumbers(_ records: [any DataModel]) throws -> [Int] {
    try records.map { try #require($0 as? Card).number }
}

private func instanceIds(_ records: [any DataModel]) -> [ObjectIdentifier] {
    records.map { ObjectIdentifier($0 as AnyObject) }
}

/// Vends a Card-read grant on dock2's identity ONLY — the provider-driven anchored path's
/// fixture: nothing ever grants on dock1, so a dock1 load succeeds only through the anchor.
private struct Dock2AnchorGrantProvider: ModelAuthorizationProvider {
    func modelAuthorizations(for request: Request) async throws -> [TestGrant] {
        guard let dock2 = try await Board.query(on: request.db).filter(\.$name == "Board 2").first() else {
            return []
        }
        return try [TestGrant(
            authorizedModel: dock2.modelIdentity,
            operations: [.readRecords],
            recordTypes: [Card.modelIdentityNamespace]
        )]
    }
}

@Suite("Anchored authorization — authorizedAs + anchored cache key (C7/C6)")
struct AnchoredEngineTests {
    /// Spec test 12: the grant check runs against the ANCHOR, not the load container — a grant
    /// naming ONLY dock2's identity authorizes loading dock1's cards when dock2 is passed as
    /// `authorizedAs:`; the same load WITHOUT the anchor (anchor defaults to the load container,
    /// where nothing grants) projects empty. Baseline first: anchor unspecified with a grant on
    /// the load container itself is untouched behavior. Two Requests carry two grant sets — the
    /// provider is memoized per Request, so seeding `TestGrantsKey` before each Request's first
    /// load gives each Request its own set.
    @Test func grantOnAnchorAuthorizesLoadOfDifferentContainer() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useModelAuthorizationProvider(TestGrantsProvider())
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)

            // Baseline: grant on the load container, anchor unspecified — existing behavior.
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedModel: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Card.modelIdentityNamespace]
            )]
            let baseline = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(try cardNumbers(baseline).sorted() == [1, 2, 3])

            // The anchored path: the ONLY grant names dock2's identity (a fresh Request re-reads
            // the provider, so this set replaces the baseline's for the calls below).
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedModel: dock2.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Card.modelIdentityNamespace]
            )]
            let req = makeRequest(on: app)
            let anchored = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords,
                authorizedAs: dock2.modelIdentity
            )
            #expect(try cardNumbers(anchored).sorted() == [1, 2, 3])

            // Same Request, same tuple, NO anchor — a distinct cache entry whose grant check
            // runs against dock1's identity, where the dock2 grant does not apply.
            let unanchored = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(unanchored.isEmpty)
        }
    }

    /// Spec test 12: same (container, type, operation, refinement) under two different anchors
    /// ⇒ two cache entries with independent results — interleaved re-loads return each entry's
    /// own cached instances, and the two entries never share element instances.
    @Test func differentAnchorsKeyIndependentCacheEntries() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useModelAuthorizationProvider(TestGrantsProvider())
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(
                    authorizedModel: dock1.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace]
                ),
                TestGrant(
                    authorizedModel: dock2.modelIdentity,
                    operations: [.readRecords],
                    recordTypes: [Card.modelIdentityNamespace]
                )
            ]
            let req = makeRequest(on: app)

            let selfAnchored = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            let dock2Anchored = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords,
                authorizedAs: dock2.modelIdentity
            )
            #expect(try cardNumbers(selfAnchored).sorted() == [1, 2, 3])
            #expect(try cardNumbers(dock2Anchored).sorted() == [1, 2, 3])
            // Two entries — the anchored call recomputed rather than reading the nil-anchor entry.
            #expect(Set(instanceIds(selfAnchored)).isDisjoint(with: Set(instanceIds(dock2Anchored))))

            // Interleaved re-loads: each anchor's entry survives the other's writes.
            let selfAgain = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(instanceIds(selfAgain) == instanceIds(selfAnchored))

            let dock2Again = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords,
                authorizedAs: dock2.modelIdentity
            )
            #expect(instanceIds(dock2Again) == instanceIds(dock2Anchored))
        }
    }

    /// Spec test 12 (normalization pin): `authorizedAs: nil` and an explicit anchor EQUAL to the
    /// load container are the same security question — one cache entry (same instances back).
    @Test func explicitAnchorEqualToContainerSharesTheNilAnchorEntry() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useModelAuthorizationProvider(TestGrantsProvider())
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedModel: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Card.modelIdentityNamespace]
            )]
            let req = makeRequest(on: app)

            let nilAnchor = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            let explicitAnchor = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords,
                authorizedAs: dock1.modelIdentity
            )
            #expect(instanceIds(explicitAnchor) == instanceIds(nilAnchor))
        }
    }

    /// Spec test 12 (coverage): the anchor threads through the provider-driven entry and the
    /// opened-generic core — a provider granting ONLY on dock2 authorizes dock1's cards when
    /// dock2 anchors the call, and projects empty without the anchor.
    @Test func providerDrivenEntryThreadsTheAnchor() async throws {
        try await withFluentTestApp { app in
            try configureWorkspace(app)
            try app.useModelAuthorizationProvider(Dock2AnchorGrantProvider())
        } _: { app, db in
            let (dock1, dock2) = try await seedWorkspace(on: db)
            let req = makeRequest(on: app)

            let anchored = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords,
                authorizedAs: dock2.modelIdentity
            )
            #expect(try cardNumbers(anchored).sorted() == [1, 2, 3])

            let unanchored = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Card.self,
                for: .readRecords
            )
            #expect(unanchored.isEmpty)
        }
    }
}
