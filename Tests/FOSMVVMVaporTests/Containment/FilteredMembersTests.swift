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

/// Seeds one board with three cards whose boardNames DISCRIMINATE the filter: two "North"
/// (numbers 3 and 1) and one "South" (number 2). A filter for "North" must return exactly the
/// two North cards — never all three, never the wrong one.
private func seedBoardWithCards(on db: any Database) async throws -> Board {
    let workspace = Workspace(name: "Filter Workspace")
    try await workspace.save(on: db)
    let pier = Pier(name: "Filter Pier")
    try await pier.save(on: db)
    let board = try Board(name: "Filter Board", pierId: pier.requireId(), workspaceId: workspace.requireId())
    try await board.save(on: db)
    try await Card(number: 3, boardName: "North", boardId: board.requireId()).save(on: db)
    try await Card(number: 2, boardName: "South", boardId: board.requireId()).save(on: db)
    try await Card(number: 1, boardName: "North", boardId: board.requireId()).save(on: db)
    return board
}

@Suite("Filtered containment member loads")
struct FilteredMembersTests {
    /// The request query pushes down into the children query as a WHERE — only the matching rows return.
    @Test func refinedChildrenHonorsFilter() async throws {
        let numbers = try await withFluentTestApp { app in
            addWorkspaceMigrations(app)
        } _: { _, db in
            let board = try await seedBoardWithCards(on: db)
            let refinement = ContainmentQueryRefinement(
                filter: AnyFilter(CardSearchQuery(boardName: "North"))
            )
            let members = try await ContainmentRelation.children(\Board.$cards)
                .members(of: board, on: db, applying: refinement)
            return try members.map { try #require($0 as? Card).number }.sorted()
        }
        #expect(numbers == [1, 3]) // the two North cards; the South card (2) is excluded
    }

    /// Filter, sort, and window compose: filter to North (numbers 3, 1), sort ascending, take the
    /// first — proves the filter narrows BEFORE the sort/window slice.
    @Test func filterComposesWithSortAndWindow() async throws {
        let numbers = try await withFluentTestApp { app in
            addWorkspaceMigrations(app)
        } _: { _, db in
            let board = try await seedBoardWithCards(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: CardSortKey.number, direction: .ascending)]).erasedTerms,
                pagination: Pagination(startIndex: 0, maxResults: 1),
                filter: AnyFilter(CardSearchQuery(boardName: "North"))
            )
            let members = try await ContainmentRelation.children(\Board.$cards)
                .members(of: board, on: db, applying: refinement)
            return try members.map { try #require($0 as? Card).number }
        }
        #expect(numbers == [1]) // North cards ascending = [1, 3]; window [0,1) = [1]
    }

    /// The critical new behavior: the COUNT twin honors the filter. Filter is the first axis that
    /// changes cardinality, so a filtered memberCount must be the FILTERED size (2), while the
    /// unfiltered memberCount stays the full size (3). This is what keeps totalCount honest.
    @Test func memberCountHonorsFilter() async throws {
        let counts = try await withFluentTestApp { app in
            addWorkspaceMigrations(app)
        } _: { _, db in
            let board = try await seedBoardWithCards(on: db)
            let relation = ContainmentRelation.children(\Board.$cards)
            let filtered = try await relation.memberCount(
                of: board, on: db,
                applying: ContainmentQueryRefinement(filter: AnyFilter(CardSearchQuery(boardName: "North")))
            )
            let unfiltered = try await relation.memberCount(of: board, on: db)
            return (filtered: filtered, unfiltered: unfiltered)
        }
        #expect(counts.filtered == 2)
        #expect(counts.unfiltered == 3)
    }

    /// Opportunistic: a query against a relation whose To is not FilterableDataModel (Member) is
    /// simply not narrowed — the full set returns, nothing throws (a query is not a "filter demand").
    @Test func filterAgainstUnfilterableModelIsSkipped() async throws {
        let count = try await withFluentTestApp { app in
            addWorkspaceMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedWorkspace(on: db) // dock1 has 2 members members
            let refinement = ContainmentQueryRefinement(
                filter: AnyFilter(CardSearchQuery(boardName: "North"))
            )
            return try await ContainmentRelation.siblings(\Board.$members)
                .members(of: dock1, on: db, applying: refinement).count
        }
        #expect(count == 2) // Member is not filterable — unfiltered, all members returned
    }

    /// Opportunistic: a filterable To (Card) given a query of a type it does NOT read (its `Filter`
    /// is CardSearchQuery) is not narrowed — a different request's query reaching this model just
    /// loads it unfiltered, never throws.
    @Test func wrongQueryTypeIsSkipped() async throws {
        let count = try await withFluentTestApp { app in
            addWorkspaceMigrations(app)
        } _: { _, db in
            let board = try await seedBoardWithCards(on: db)
            let refinement = ContainmentQueryRefinement(
                filter: AnyFilter(OtherQuery(value: 1))
            )
            return try await ContainmentRelation.children(\Board.$cards)
                .members(of: board, on: db, applying: refinement).count
        }
        #expect(count == 3) // OtherQuery is not Card's Filter type — unfiltered, all cards returned
    }

    /// Cache-key behavior (the value IS the key): equal query meaning ⇒ equal refinements with
    /// equal hashes; a differing query — or a different query TYPE — ⇒ unequal. Behavior only,
    /// no representation.
    @Test func refinementEqualityFollowsFilter() {
        let north = ContainmentQueryRefinement(filter: AnyFilter(CardSearchQuery(boardName: "North")))
        let sameNorth = ContainmentQueryRefinement(filter: AnyFilter(CardSearchQuery(boardName: "North")))
        let south = ContainmentQueryRefinement(filter: AnyFilter(CardSearchQuery(boardName: "South")))
        let otherType = ContainmentQueryRefinement(filter: AnyFilter(OtherQuery(value: 1)))
        #expect(north == sameNorth)
        #expect(north.hashValue == sameNorth.hashValue)
        #expect(north != south)
        #expect(north != otherType)
        #expect(north != .none)
    }
}
