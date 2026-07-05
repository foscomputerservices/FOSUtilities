// SortMappingTests.swift
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

// Test-taxonomy discipline: coverage tests of the internal SortMapping.apply seam via `@testable
// import FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.

import FluentKit
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("SortMapping meaning→order-by")
struct SortMappingTests {
    /// Spec test group 10: a single-mapping key orders in-database (descending).
    @Test func numberMappingSortsDescendingInDatabase() async throws {
        let numbers = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            var query = try Berth.query(on: db).filter(\.$dock.$id == dock1.requireId())
            for mapping in Berth.sortMappings(for: .number) {
                query = mapping.apply(to: query, direction: .descending)
            }
            return try await query.all().map(\.number)
        }
        #expect(numbers == [3, 2, 1])
    }

    /// Spec test group 10: composite mappings apply in declaration order — dockName groups the docks,
    /// number breaks ties inside dock1.
    @Test func compositeMappingOrdersByNameThenNumberTiebreak() async throws {
        let ordered = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            _ = try await seedHarbor(on: db)
            var query = Berth.query(on: db) // ALL berths, both docks
            for mapping in Berth.sortMappings(for: .dockName) {
                query = mapping.apply(to: query, direction: .ascending)
            }
            let berths = try await query.all()
            return (names: berths.map(\.dockName), numbers: berths.map(\.number))
        }
        #expect(ordered.names == ["Dock 1", "Dock 1", "Dock 1", "Dock 2"])
        #expect(ordered.numbers == [1, 2, 3, 9])
    }

    /// TestGrant sanity (Task 7 consumes it): the value fixture covers a granted operation via the
    /// wildcard, and the wildcard deliberately does NOT grant destroy.
    @Test func grantCoversViaWildcardButNeverDestroy() async throws {
        try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, dock2) = try await seedHarbor(on: db)
            let grant = try TestGrant(
                authorizedContainer: dock1.modelIdentity,
                operations: [.anyOperation],
                recordTypes: [Berth.modelIdentityNamespace]
            )
            try #expect(grant.authorizes(.readRecords, ofType: Berth.self, in: dock1.modelIdentity))
            try #expect(!grant.authorizes(.destroyRecords, ofType: Berth.self, in: dock1.modelIdentity))
            try #expect(!grant.authorizes(.readRecords, ofType: Berth.self, in: dock2.modelIdentity))
        }
    }
}
