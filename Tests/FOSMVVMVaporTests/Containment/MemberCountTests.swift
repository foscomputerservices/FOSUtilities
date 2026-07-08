// MemberCountTests.swift
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

// Test-taxonomy discipline: the memberCount seam is internal (below C8's public surface),
// exercised via `@testable import FOSMVVMVapor`. Behavior only — no representation.

import FluentKit
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("Containment member counts")
struct MemberCountTests {
    /// The full member count of a to-many relation — the whole set, independent of any window.
    @Test func childrenMemberCountIsTheFullSet() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 3 berths
            return try await ContainmentRelation.children(\Dock.$berths).memberCount(of: dock1, on: db)
        }
        #expect(count == 3)
    }

    /// Siblings (pivot) count the whole set the same way.
    @Test func siblingsMemberCountIsTheFullSet() async throws {
        let count = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db) // dock1 has 2 crew
            return try await ContainmentRelation.siblings(\Dock.$crew).memberCount(of: dock1, on: db)
        }
        #expect(count == 2)
    }
}
