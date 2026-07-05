// AuthorizedLoadEngineTests.swift
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

// Test-taxonomy discipline: coverage tests of the internal load engine via `@testable import
// FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.
// The C8 audit removed the direct `authorizedBy:` engine entry, so grants reach the engine through
// the shipped provider path: each test seeds `TestGrantsKey` before the load and the registered
// `TestGrantsProvider` vends exactly that set (fetched + memoized once per Request).

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

/// Registers Harbor (the apex) + Dock, adds the remaining harbor migrations, and registers the
/// provider that vends the per-test grants. CreateHarbor/CreatePier run BEFORE CreateDock —
/// CreateDock's DDL references both tables.
private func configureHarbor(_ app: Application, countCallsInto counter: ProviderCallCounter? = nil) throws {
    app.migrations.add(CreatePier())
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    if let counter {
        app.storage[ProviderCallCounterKey.self] = counter
        try app.useContainerAuthorizationProvider(CountingGrantsProvider())
    } else {
        try app.useContainerAuthorizationProvider(TestGrantsProvider())
    }
}

/// Counts how many times the engine actually consulted the provider — proves the missing-container
/// short-circuit fires BEFORE any grant fetch (lazy provider ordering).
private final class ProviderCallCounter: @unchecked Sendable {
    var count = 0
}

private struct ProviderCallCounterKey: StorageKey {
    typealias Value = ProviderCallCounter
}

/// Same vend as ``TestGrantsProvider``, but tallies each consultation into the app's counter.
private struct CountingGrantsProvider: ContainerAuthorizationProvider {
    func containerAuthorizations(for request: Request) async throws -> [TestGrant] {
        request.application.storage[ProviderCallCounterKey.self]?.count += 1
        return request.application.storage[TestGrantsKey.self] ?? []
    }
}

/// Mints a real Request via Vapor's public initializer — the engine's receiver.
private func makeRequest(on app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
}

private func berthNumbers(_ records: [any DataModel]) throws -> [Int] {
    try records.map { try #require($0 as? Berth).number }
}

private func instanceIds(_ records: [any DataModel]) -> [ObjectIdentifier] {
    records.map { ObjectIdentifier($0 as AnyObject) }
}

@Suite("Authorized container load engine (C6)")
struct AuthorizedLoadEngineTests {
    // MARK: - Group 1: instance scoping

    /// Spec test group 1: a grant names ONE container instance — dock1's grant loads dock1's
    /// berths and projects nothing for dock2's identity.
    @Test func grantScopedToInstanceLoadsOnlyThatContainer() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
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
    }

    /// Spec test group 1: empty authorizations ⇒ empty result — brute force projects empty
    /// (the data-scoping invariant), never an error the caller could confuse with "not found".
    @Test func emptyAuthorizationsLoadEmpty() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = []
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(records.isEmpty)
        }
    }

    // MARK: - Group 2: operation × type scoping

    /// Spec test group 2: a `.readRecords`-on-Berth grant loads Berths, projects nothing for
    /// CrewMember, and projects nothing for `.createRecords` on Berth.
    @Test func operationAndTypeScopingGateTheLoad() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let req = makeRequest(on: app)

            let berths = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(berths.count == 3)

            let crew = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: CrewMember.self,
                for: .readRecords
            )
            #expect(crew.isEmpty)

            let creations = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .createRecords
            )
            #expect(creations.isEmpty)
        }
    }

    // MARK: - Group 3: sort applied in-DB

    /// Spec test group 3: sort terms push down into the database query — seed order [1,2,3]
    /// differs from the descending result, so ordering proves the push-down.
    @Test func sortAppliesInDatabase() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                sortedBy: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms
            )
            #expect(try berthNumbers(records) == [3, 2, 1])
        }
    }

    /// Spec test group 3: the composite key (`dockName` → dockName then number) yields the
    /// composite order. dock1's berths share one dockName, so descending [3,2,1] can only come
    /// from the number tiebreak — a single-mapping sort would leave insertion order [1,2,3].
    @Test func compositeSortKeyAppliesTiebreakOrder() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                sortedBy: SortCriteria([SortTerm(key: BerthSortKey.dockName, direction: .descending)]).erasedTerms
            )
            #expect(try berthNumbers(records) == [3, 2, 1])
        }
    }

    // MARK: - Group 4: pagination window

    /// Spec test group 4: the window applies over the sorted set — the middle record of the
    /// descending order; `nil` pagination returns the full set.
    @Test func paginationWindowsTheSortedSet() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let sort = SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms
            let req = makeRequest(on: app)

            let middle = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                sortedBy: sort,
                pagination: Pagination(startIndex: 1, maxResults: 1)
            )
            #expect(try berthNumbers(middle) == [2])

            let full = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                sortedBy: sort,
                pagination: nil
            )
            #expect(try berthNumbers(full) == [3, 2, 1])
        }
    }

    /// Spec test group 4: negative pagination components are normalized to absent — a negative
    /// `startIndex`/`maxResults` decoded from client input must never reach FluentKit's
    /// `range(lower:upper:)`, which treats negative bounds as a crashing/garbage query. The full
    /// authorized set comes back, same as `pagination: nil`.
    @Test func negativePaginationComponentsBehaveAsAbsent() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                pagination: Pagination(startIndex: -3, maxResults: -1)
            )
            #expect(try berthNumbers(records).sorted() == [1, 2, 3])
        }
    }

    /// Spec test group 4: `maxResults: 0` is a deliberately empty page, not "absent" — it must
    /// return `count == 0` without throwing, distinct from the negative-normalizes-to-absent case
    /// above.
    @Test func zeroMaxResultsYieldsEmptyPageWithoutThrowing() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                pagination: Pagination(startIndex: 0, maxResults: 0)
            )
            #expect(records.count == 0)
        }
    }

    // MARK: - Group 6: compute-once cache

    /// Spec test group 6: identical calls on one Request return the SAME element instances
    /// (`ObjectIdentifier` — C4's pinned equality basis); a call differing only in sort
    /// recomputes (the OQ-L1-4 collision test).
    @Test func identicalCallsShareInstancesDifferingSortRecomputes() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let req = makeRequest(on: app)

            let first = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            let second = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(instanceIds(first) == instanceIds(second))

            let sorted = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords,
                sortedBy: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms
            )
            #expect(Set(instanceIds(sorted)).isDisjoint(with: Set(instanceIds(first))))
        }
    }

    /// Spec test group 6: the cached snapshot survives row deletion between identical calls;
    /// `invalidateContainerRecords` makes the next call recompute and observe reality.
    @Test func cachedResultSurvivesDeletionUntilInvalidated() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let req = makeRequest(on: app)

            let first = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(first.count == 3)

            try await Berth.query(on: db).delete()

            let cached = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(instanceIds(cached) == instanceIds(first))

            try req.invalidateContainerRecords(of: dock1.modelIdentity)
            let recomputed = try await req.authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(recomputed.isEmpty)
        }
    }

    /// Spec test group 6: an EMPTY result is cached too — rows inserted between identical calls
    /// stay invisible until `invalidateContainerRecords` drops the entry.
    @Test func emptyResultIsCachedUntilInvalidated() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let harbor = Harbor(name: "Empty Harbor")
            try await harbor.save(on: db)
            let pier = Pier(name: "Empty Pier")
            try await pier.save(on: db)
            let dock = try Dock(name: "Empty Dock", pierId: pier.requireId(), harborId: harbor.requireId())
            try await dock.save(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let req = makeRequest(on: app)

            let first = try await req.authorizedRecords(
                of: dock.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(first.isEmpty)

            try await Berth(number: 42, dockName: dock.name, dockId: dock.requireId()).save(on: db)

            let cached = try await req.authorizedRecords(
                of: dock.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(cached.isEmpty)

            try req.invalidateContainerRecords(of: dock.modelIdentity)
            let recomputed = try await req.authorizedRecords(
                of: dock.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(try berthNumbers(recomputed) == [42])
        }
    }

    /// Spec test group 6: a FRESH Request owns a fresh cache — same call, new instances.
    @Test func freshRequestOwnsFreshCache() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]

            let first = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            let second = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(try berthNumbers(first).sorted() == berthNumbers(second).sorted())
            #expect(Set(instanceIds(first)).isDisjoint(with: Set(instanceIds(second))))
        }
    }

    // MARK: - Group 7: missing vs unregistered

    /// Spec test group 7: a valid-namespace identity whose row is deleted loads `[]` — a data
    /// condition, indistinguishable from unauthorized by design (never a throw).
    @Test func missingContainerRowLoadsEmpty() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let harbor = Harbor(name: "Ghost Harbor")
            try await harbor.save(on: db)
            let pier = Pier(name: "Ghost Pier")
            try await pier.save(on: db)
            let dock = try Dock(name: "Ghost Dock", pierId: pier.requireId(), harborId: harbor.requireId())
            try await dock.save(on: db)
            let identity = try dock.modelIdentity
            app.storage[TestGrantsKey.self] = [TestGrant(
                authorizedContainer: identity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            try await dock.delete(on: db)

            let records = try await makeRequest(on: app).authorizedRecords(
                of: identity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(records.isEmpty)
        }
    }

    /// Spec test group 7: lazy provider ordering — a missing container row returns `[]` WITHOUT
    /// consulting the authorization provider. The pipeline finds no row and short-circuits before
    /// it would fetch grants, so a valid-namespace-but-deleted container never pays the grant fetch.
    @Test func missingContainerLoadsEmptyWithoutConsultingProvider() async throws {
        let counter = ProviderCallCounter()
        try await withFluentTestApp { app in
            try configureHarbor(app, countCallsInto: counter)
        } _: { app, db in
            let harbor = Harbor(name: "Vanished Harbor")
            try await harbor.save(on: db)
            let pier = Pier(name: "Vanished Pier")
            try await pier.save(on: db)
            let dock = try Dock(name: "Vanished Dock", pierId: pier.requireId(), harborId: harbor.requireId())
            try await dock.save(on: db)
            let identity = try dock.modelIdentity
            app.storage[TestGrantsKey.self] = [TestGrant(
                authorizedContainer: identity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            try await dock.delete(on: db)

            let records = try await makeRequest(on: app).authorizedRecords(
                of: identity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(records.isEmpty)
            #expect(counter.count == 0) // the grant fetch never happened
        }
    }

    /// Spec test group 7: an UNREGISTERED namespace throws `.unregisteredNamespace` —
    /// misconfiguration must not hide as empty (≠ unauthorized). Pier is never registered.
    @Test func unregisteredNamespaceThrows() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            let pier = Pier(name: "Rogue Pier")
            try await pier.save(on: db)
            let identity = try pier.modelIdentity
            app.storage[TestGrantsKey.self] = [TestGrant(
                authorizedContainer: identity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            do {
                _ = try await makeRequest(on: app).authorizedRecords(
                    of: identity,
                    containing: Berth.self,
                    for: .readRecords
                )
                Issue.record("expected ContainmentError.unregisteredNamespace")
            } catch let error as ContainmentError {
                guard case .unregisteredNamespace = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }

    // MARK: - Group 8: threshold never truncates

    /// Spec test group 8: exceeding `maxRecordsWarningThreshold` warns but NEVER truncates —
    /// threshold 2, three berths, all three returned. (Warning emission is observability, not a
    /// public contract — documented rather than logger-captured.)
    @Test func thresholdWarnsButNeverTruncates() async throws {
        try await withFluentTestApp { app in
            try configureHarbor(app)
        } _: { app, db in
            app.maxRecordsWarningThreshold = 2
            let (dock1, _) = try await seedHarbor(on: db)
            app.storage[TestGrantsKey.self] = try [TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.readRecords],
                recordTypes: [Berth.modelIdentityNamespace]
            )]
            let records = try await makeRequest(on: app).authorizedRecords(
                of: dock1.modelIdentity,
                containing: Berth.self,
                for: .readRecords
            )
            #expect(try berthNumbers(records).sorted() == [1, 2, 3])
        }
    }
}
