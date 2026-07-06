// ContainmentRelationTests.swift
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

// Test-taxonomy discipline: coverage tests of the internal members(of:on:) seam via `@testable
// import FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.

import FluentKit
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("ContainmentRelation member loads")
struct ContainmentRelationTests {
    /// Spec test group 3: children of THIS dock only.
    @Test func childrenLoadsOnlyThisContainersMembers() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.children(\Dock.$berths).members(of: dock1, on: db)
            return try members.map { try #require($0 as? Berth).number }.sorted()
        }
        #expect(numbers == [1, 2, 3])
    }

    /// Spec test group 4: siblings through the pivot, this container only.
    @Test func siblingsLoadsThroughPivotForThisContainerOnly() async throws {
        let names = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (_, dock2) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.siblings(\Dock.$crew).members(of: dock2, on: db)
            return try members.map { try #require($0 as? CrewMember).name }.sorted()
        }
        #expect(names == ["Alice"])
    }

    /// Spec test group 5: parent (to-one) returns a single-element array.
    @Test func parentLoadsSingleElementArray() async throws {
        let parents = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let members = try await ContainmentRelation.parent(\Dock.$pier).members(of: dock1, on: db)
            return members.map { ($0 as? Pier)?.name }
        }
        #expect(parents == ["North Pier"])
    }

    /// Cast backstop: wrong container type throws, never a silent [].
    @Test func mismatchedContainerThrowsTyped() async throws {
        try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let berth = try #require(try await dock1.$berths.query(on: db).first())
            let relation = ContainmentRelation.children(\Dock.$berths)
            do {
                _ = try await relation.members(of: berth, on: db) // a Berth is not a Dock
                Issue.record("expected ContainmentError.containerTypeMismatch")
            } catch let error as ContainmentError {
                guard case .containerTypeMismatch = error else {
                    Issue.record("wrong ContainmentError case: \(error)")
                    return
                }
            }
        }
    }
}
