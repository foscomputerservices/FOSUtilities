// FilteredMembersTests.swift
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

// Test-taxonomy discipline: coverage tests of the internal refined-members seam via `@testable
// import FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.

import FluentKit
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

/// Seeds one dock with three berths whose dockNames DISCRIMINATE the filter: two "North"
/// (numbers 3 and 1) and one "South" (number 2). A filter for "North" must return exactly the
/// two North berths — never all three, never the wrong one.
private func seedDockWithBerths(on db: any Database) async throws -> Dock {
    let harbor = Harbor(name: "Filter Harbor")
    try await harbor.save(on: db)
    let pier = Pier(name: "Filter Pier")
    try await pier.save(on: db)
    let dock = try Dock(name: "Filter Dock", pierId: pier.requireId(), harborId: harbor.requireId())
    try await dock.save(on: db)
    try await Berth(number: 3, dockName: "North", dockId: dock.requireId()).save(on: db)
    try await Berth(number: 2, dockName: "South", dockId: dock.requireId()).save(on: db)
    try await Berth(number: 1, dockName: "North", dockId: dock.requireId()).save(on: db)
    return dock
}

@Suite("Filtered containment member loads")
struct FilteredMembersTests {
    /// The request query pushes down into the children query as a WHERE — only the matching rows return.
    @Test func refinedChildrenHonorsFilter() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let dock = try await seedDockWithBerths(on: db)
            let refinement = ContainmentQueryRefinement(
                filter: AnyFilter(BerthSearchQuery(dockName: "North"))
            )
            let members = try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock, on: db, applying: refinement)
            return try members.map { try #require($0 as? Berth).number }.sorted()
        }
        #expect(numbers == [1, 3]) // the two North berths; the South berth (2) is excluded
    }

    /// Filter, sort, and window compose: filter to North (numbers 3, 1), sort ascending, take the
    /// first — proves the filter narrows BEFORE the sort/window slice.
    @Test func filterComposesWithSortAndWindow() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let dock = try await seedDockWithBerths(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .ascending)]).erasedTerms,
                pagination: Pagination(startIndex: 0, maxResults: 1),
                filter: AnyFilter(BerthSearchQuery(dockName: "North"))
            )
            let members = try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock, on: db, applying: refinement)
            return try members.map { try #require($0 as? Berth).number }
        }
        #expect(numbers == [1]) // North berths ascending = [1, 3]; window [0,1) = [1]
    }

    /// The critical new behavior: the COUNT twin honors the filter. Filter is the first axis that
    /// changes cardinality, so a filtered memberCount must be the FILTERED size (2), while the
    /// unfiltered memberCount stays the full size (3). This is what keeps totalCount honest.
    @Test func memberCountHonorsFilter() async throws {
        let counts = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let dock = try await seedDockWithBerths(on: db)
            let relation = ContainmentRelation.children(\Dock.$berths)
            let filtered = try await relation.memberCount(
                of: dock, on: db,
                applying: ContainmentQueryRefinement(filter: AnyFilter(BerthSearchQuery(dockName: "North")))
            )
            let unfiltered = try await relation.memberCount(of: dock, on: db)
            return (filtered: filtered, unfiltered: unfiltered)
        }
        #expect(counts.filtered == 2)
        #expect(counts.unfiltered == 3)
    }

    /// Opportunistic: a query against a relation whose To is not FilterableDataModel (CrewMember) is
    /// simply not narrowed — the full set returns, nothing throws (a query is not a "filter demand").
    @Test func filterAgainstUnfilterableModelIsSkipped() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 2 crew members
            let refinement = ContainmentQueryRefinement(
                filter: AnyFilter(BerthSearchQuery(dockName: "North"))
            )
            return try await ContainmentRelation.siblings(\Dock.$crew)
                .members(of: dock1, on: db, applying: refinement).count
        }
        #expect(count == 2) // CrewMember is not filterable — unfiltered, all crew returned
    }

    /// Opportunistic: a filterable To (Berth) given a query of a type it does NOT read (its `Filter`
    /// is BerthSearchQuery) is not narrowed — a different request's query reaching this model just
    /// loads it unfiltered, never throws.
    @Test func wrongQueryTypeIsSkipped() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let dock = try await seedDockWithBerths(on: db)
            let refinement = ContainmentQueryRefinement(
                filter: AnyFilter(OtherQuery(value: 1))
            )
            return try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock, on: db, applying: refinement).count
        }
        #expect(count == 3) // OtherQuery is not Berth's Filter type — unfiltered, all berths returned
    }

    /// Cache-key behavior (the value IS the key): equal query meaning ⇒ equal refinements with
    /// equal hashes; a differing query — or a different query TYPE — ⇒ unequal. Behavior only,
    /// no representation.
    @Test func refinementEqualityFollowsFilter() {
        let north = ContainmentQueryRefinement(filter: AnyFilter(BerthSearchQuery(dockName: "North")))
        let sameNorth = ContainmentQueryRefinement(filter: AnyFilter(BerthSearchQuery(dockName: "North")))
        let south = ContainmentQueryRefinement(filter: AnyFilter(BerthSearchQuery(dockName: "South")))
        let otherType = ContainmentQueryRefinement(filter: AnyFilter(OtherQuery(value: 1)))
        #expect(north == sameNorth)
        #expect(north.hashValue == sameNorth.hashValue)
        #expect(north != south)
        #expect(north != otherType)
        #expect(north != .none)
    }
}
