// FluentTestHarnessTests.swift
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

import Fluent // app.migrations lives in vapor/fluent, not FluentKit
import FluentKit
import FOSTestingVapor
import Foundation
import Testing

@Suite("Fluent test harness")
struct FluentTestHarnessTests {
    @Test func migratesSeedsAndQueries() async throws {
        let count = try await withFluentTestApp { app in
            app.migrations.add(CreateSmokeRecord())
        } _: { _, db in
            try await SmokeRecord(label: "hello").save(on: db)
            return try await SmokeRecord.query(on: db).count()
        }
        #expect(count == 1)
    }

    @Test func eachCallGetsAFreshDatabase() async throws {
        // Runs the same seed twice; the second call must not see the first call's row.
        for _ in 0..<2 {
            let count = try await withFluentTestApp { app in
                app.migrations.add(CreateSmokeRecord())
            } _: { _, db in
                try await SmokeRecord(label: "solo").save(on: db)
                return try await SmokeRecord.query(on: db).count()
            }
            #expect(count == 1)
        }
    }

    @Test func harborFixturesSeedAndRelate() async throws {
        let names = try await withFluentTestApp { app in
            addHarborMigrations(app)
        } _: { _, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let berths = try await dock1.$berths.query(on: db).all()
            return berths.map(\.number).sorted()
        }
        #expect(names == [1, 2, 3])
    }
}

/// Minimal local fixture — the containment fixtures arrive in Task 3.
final class SmokeRecord: FluentKit.Model, @unchecked Sendable {
    static let schema = "smoke_records"
    @ID(key: .id) var id: UUID?
    @Field(key: "label") var label: String
    init() {}
    init(label: String) {
        self.label = label
    }
}

struct CreateSmokeRecord: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SmokeRecord.schema).id().field("label", .string, .required).create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SmokeRecord.schema).delete()
    }
}
