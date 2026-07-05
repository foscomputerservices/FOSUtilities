// RefinedMembersTests.swift
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

/// A sort vocabulary Berth does NOT publish — the wrong-key-type fixture.
private enum OtherSortKey: String, SortKey {
    case bogus
}

@Suite("Refined containment member loads (D1)")
struct RefinedMembersTests {
    /// Spec test group 10: sort terms push down into the children query (descending by number —
    /// seed order differs from result order, so ordering proves the push-down).
    @Test func refinedChildrenHonorsSortOrder() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms
            )
            let members = try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock1, on: db, applying: refinement)
            return try members.map { try #require($0 as? Berth).number }
        }
        #expect(numbers == [3, 2, 1])
    }

    /// Spec test group 10: sort and window compose — the middle berth of the descending order.
    @Test func refinedChildrenAppliesWindowOverSortedOrder() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms,
                pagination: Pagination(startIndex: 1, maxResults: 1)
            )
            let members = try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock1, on: db, applying: refinement)
            return try members.map { try #require($0 as? Berth).number }
        }
        #expect(numbers == [2])
    }

    /// Spec test group 10: MULTI-term refinements apply in term order through the refined path.
    ///
    /// Term choice: `.number` first (its mapping is the single `$number` column), `.dockName`
    /// second — NOT the reverse, because `.dockName`'s mapping list carries its own `$number`
    /// tiebreak, which would shadow any later term and make its order unobservable.
    ///
    /// Discriminating properties of the seed (numbers non-unique, names conflict with insertion):
    /// - swapped terms (`terms.reversed()`) would yield numbers [1, 2, 1] — the assertion fails
    ///   (verified by mutation);
    /// - dropping the second term leaves the number=1 tie unordered (insertion gives [B, A, A]) —
    ///   the names assertion fails.
    @Test func multiTermSortAppliesInTermOrder() async throws {
        let ordered = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let harbor = Harbor(name: "Tie Harbor")
            try await harbor.save(on: db)
            let pier = Pier(name: "Tie Pier")
            try await pier.save(on: db)
            let dock = try Dock(name: "Tie Dock", pierId: pier.requireId(), harborId: harbor.requireId())
            try await dock.save(on: db)
            try await Berth(number: 1, dockName: "B", dockId: dock.requireId()).save(on: db)
            try await Berth(number: 1, dockName: "A", dockId: dock.requireId()).save(on: db)
            try await Berth(number: 2, dockName: "A", dockId: dock.requireId()).save(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([
                    SortTerm(key: BerthSortKey.number, direction: .ascending),
                    SortTerm(key: BerthSortKey.dockName, direction: .ascending)
                ]).erasedTerms
            )
            let members = try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock, on: db, applying: refinement)
            let berths = try members.map { try #require($0 as? Berth) }
            return (numbers: berths.map(\.number), names: berths.map(\.dockName))
        }
        #expect(ordered.numbers == [1, 1, 2])
        #expect(ordered.names == ["A", "B", "A"])
    }

    /// Spec test group 10: a window WITHOUT sort terms is valid against a non-sortable To —
    /// only sort demands SortableDataModel; pagination alone must not throw.
    @Test func windowOnlyRefinementSucceedsAgainstUnsortableModel() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 2 crew members
            let refinement = ContainmentQueryRefinement(
                pagination: Pagination(startIndex: 0, maxResults: 1)
            )
            return try await ContainmentRelation.siblings(\Dock.$crew)
                .members(of: dock1, on: db, applying: refinement).count
        }
        #expect(count == 1)
    }

    /// Spec test group 10: a window alone (no sort terms) still narrows the result set.
    @Test func windowAloneNarrowsResultSet() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let refinement = ContainmentQueryRefinement(
                pagination: Pagination(startIndex: 0, maxResults: 2)
            )
            return try await ContainmentRelation.children(\Dock.$berths)
                .members(of: dock1, on: db, applying: refinement).count
        }
        #expect(count == 2)
    }

    /// Spec test group 10: `.parent` ignores sort AND window — one row is lossless, so a refinement
    /// that would otherwise throw (Pier is not sortable) or window past it changes nothing.
    @Test func parentIgnoresSortAndWindow() async throws {
        let names = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms,
                pagination: Pagination(startIndex: 5, maxResults: 1)
            )
            let members = try await ContainmentRelation.parent(\Dock.$pier)
                .members(of: dock1, on: db, applying: refinement)
            return members.map { ($0 as? Pier)?.name }
        }
        #expect(names == ["North Pier"])
    }

    /// Spec test group 5: sort terms against a relation whose To is not SortableDataModel fail
    /// fast — never a silently unsorted result.
    @Test func sortTermsAgainstUnsortableModelThrow() async throws {
        try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .ascending)]).erasedTerms
            )
            do {
                _ = try await ContainmentRelation.siblings(\Dock.$crew)
                    .members(of: dock1, on: db, applying: refinement)
                Issue.record("expected ContainmentError.unsortableContainedType")
            } catch let error as ContainmentError {
                guard case .unsortableContainedType = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }

    /// Spec test group 5: a sortable To with terms of the WRONG key type throws the same error —
    /// the vocabulary is the model's one RequestSortKey, nothing else.
    @Test func wrongKeyTypeAgainstSortableModelThrows() async throws {
        try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let refinement = ContainmentQueryRefinement(
                sortTerms: SortCriteria([SortTerm(key: OtherSortKey.bogus, direction: .ascending)]).erasedTerms
            )
            do {
                _ = try await ContainmentRelation.children(\Dock.$berths)
                    .members(of: dock1, on: db, applying: refinement)
                Issue.record("expected ContainmentError.unsortableContainedType")
            } catch let error as ContainmentError {
                guard case .unsortableContainedType = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }

    /// Cache-key behavior (the value IS the key): same sort meaning + window ⇒ equal refinements
    /// with equal hashes; a differing direction ⇒ unequal. Behavior only — no representation.
    @Test func refinementEqualityFollowsSortMeaning() {
        let descending = ContainmentQueryRefinement(
            sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms,
            pagination: Pagination(startIndex: 1, maxResults: 1)
        )
        let sameMeaning = ContainmentQueryRefinement(
            sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .descending)]).erasedTerms,
            pagination: Pagination(startIndex: 1, maxResults: 1)
        )
        let ascending = ContainmentQueryRefinement(
            sortTerms: SortCriteria([SortTerm(key: BerthSortKey.number, direction: .ascending)]).erasedTerms,
            pagination: Pagination(startIndex: 1, maxResults: 1)
        )
        #expect(descending == sameMeaning)
        #expect(descending.hashValue == sameMeaning.hashValue)
        #expect(descending != ascending)
        #expect(ContainmentQueryRefinement.none == ContainmentQueryRefinement())
    }

    /// C4 contract preserved: the unrefined entry still returns the full, unwindowed set.
    @Test func unrefinedMembersStillReturnsFullSet() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.children(\Dock.$berths).members(of: dock1, on: db)
            return try members.map { try #require($0 as? Berth).number }.sorted()
        }
        #expect(numbers == [1, 2, 3])
    }
}
