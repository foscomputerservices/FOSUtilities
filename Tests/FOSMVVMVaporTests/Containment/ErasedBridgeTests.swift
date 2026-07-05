// ErasedBridgeTests.swift
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

// Test-taxonomy discipline: coverage tests of the internal registry→relation bridge via `@testable
// import FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("End-to-end erased bridge")
struct ErasedBridgeTests {
    /// Spec test group 6: from a bare ModelIdentity, reach every contained record — parent,
    /// siblings, and children — without naming Dock/Berth/CrewMember/Pier at the loading call sites.
    @Test func identityReachesContainedRecordsWithoutConcreteTypes() async throws {
        let membersByRelation = try await withFluentTestApp { app in
            try app.register(Harbor.self, migration: CreateHarbor()) // CreateDock's DDL references harbors
            app.migrations.add(CreatePier()) // and piers — both must exist first
            try app.register(Dock.self, migration: CreateDock())
            app.migrations.add(CreateBerth())
            app.migrations.add(CreateCrewMember())
            app.migrations.add(CreateDockCrew())
            app.migrations.add(CreatePersonnelFolder()) // Dock's containment now spans folders too
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let identity = try dock1.modelIdentity
            // From here down: NO concrete container/record type names — the erased path only.
            return try await loadAllMembers(of: identity, registry: app.modelTypeRegistry, on: db)
        }
        // dock1: 3 berths (children), 2 crew (siblings), 1 pier (parent), 0 personnel folders.
        #expect(membersByRelation.sorted() == [0, 1, 2, 3])
    }
}

/// The C4 flow, generically: identity → registry → find → containment → members.
/// Deliberately references no concrete model type.
private func loadAllMembers(
    of identity: ModelIdentity,
    registry: ModelTypeRegistry,
    on db: any Database
) async throws -> [Int] {
    guard let descriptor = registry.registered(for: identity.namespace) else {
        throw LoadAllMembersError.unregisteredNamespace
    }
    guard let container = try await descriptor.find(identity.id, on: db) else {
        throw LoadAllMembersError.containerNotFound
    }
    var counts: [Int] = []
    for relation in descriptor.containment {
        try await counts.append(relation.members(of: container, on: db).count)
    }
    return counts
}

/// Plain thrown errors keep the helper free of Testing macros and name the exact failing step.
private enum LoadAllMembersError: Error {
    case unregisteredNamespace
    case containerNotFound
}
