// ModelTypeRegistryTests.swift
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

// Test-taxonomy discipline: coverage tests of the internal ModelTypeRegistry via `@testable import
// FOSMVVMVapor` (sanctioned — below C8's public surface). No access level is widened for tests.

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing

@Suite("ModelTypeRegistry + migration-as-registration")
struct ModelTypeRegistryTests {
    /// Spec test group 1: registry round-trip; unregistered namespace → nil.
    @Test func registrationRoundTripsDescriptor() async throws {
        try await withFluentTestApp { app in
            try app.register(Workspace.self, migration: CreateWorkspace())
            try app.register(Board.self, migration: CreateBoard())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateCard())
            app.migrations.add(CreateMember())
            app.migrations.add(CreateBoardMember())
        } _: { app, _ in
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Board.modelIdentityNamespace))
            // Assertion basis per spec: count + per-element containedType identity (not Equatable).
            #expect(descriptor.containment.count == Board.containment.count)
            #expect(
                Set(descriptor.containment.map { ObjectIdentifier($0.containedType) })
                    == Set(Board.containment.map { ObjectIdentifier($0.containedType) })
            )
            #expect(app.modelTypeRegistry.registered(for: Pier.modelIdentityNamespace) == nil)
        }
    }

    /// Spec test group 2: find by id; missing id → nil.
    @Test func registeredModelFindsById() async throws {
        try await withFluentTestApp { app in
            try app.register(Workspace.self, migration: CreateWorkspace())
            try app.register(Board.self, migration: CreateBoard())
            app.migrations.add(CreatePier())
            app.migrations.add(CreateCard())
            app.migrations.add(CreateMember())
            app.migrations.add(CreateBoardMember())
        } _: { app, db in
            let (dock1, _) = try await seedWorkspace(on: db)
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Board.modelIdentityNamespace))
            let found = try await descriptor.find(dock1.requireId(), on: db)
            #expect(try #require(found as? Board).id == dock1.id)
            let missing = try await descriptor.find(ModelIdType(), on: db)
            #expect(missing == nil)
        }
    }

    /// Spec test group 8: duplicate namespace fail-fast — both a second register of the SAME type
    /// and a second TYPE sharing the namespace; first registration unchanged.
    @Test func duplicateRegistrationThrows() async throws {
        try await withFluentTestApp { app in
            try app.register(Workspace.self, migration: CreateWorkspace()) // CreateBoard's DDL references workspaces
            app.migrations.add(CreatePier()) // and piers — both must exist first
            try app.register(Board.self, migration: CreateBoard())
            for attempt in 0..<2 {
                do {
                    // attempt 0: same type twice; attempt 1: different type, colliding namespace.
                    if attempt == 0 {
                        try app.register(Board.self, migration: CreateBoard())
                    } else {
                        try app.register(RogueBoard.self, migration: CreateBoard())
                    }
                    Issue.record("expected ContainmentError.duplicateNamespace (attempt \(attempt))")
                } catch let error as ContainmentError {
                    guard case .duplicateNamespace = error else {
                        Issue.record("wrong case: \(error)")
                        return
                    }
                }
            }
            // First registration untouched:
            let descriptor = try #require(app.modelTypeRegistry.registered(for: Board.modelIdentityNamespace))
            #expect(descriptor.containment.count == Board.containment.count)
            #expect(
                Set(descriptor.containment.map { ObjectIdentifier($0.containedType) })
                    == Set(Board.containment.map { ObjectIdentifier($0.containedType) })
            )
            // Don't migrate the workspace graph here — this test never touches the DB body.
        } _: { _, _ in }
    }

    /// Spec test group 9: containment from another container's KeyPath fail-fasts.
    @Test func containerTypeMismatchThrows() async throws {
        try await withFluentTestApp { app in
            app.migrations.add(CreatePier()) // CreateBoard's DDL references piers — Pier must exist first
            do {
                try app.register(MismatchedBoard.self, migration: CreateBoard())
                Issue.record("expected ContainmentError.containerTypeMismatch")
            } catch let error as ContainmentError {
                guard case .containerTypeMismatch = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.modelTypeRegistry.registered(for: MismatchedBoard.modelIdentityNamespace) == nil)
        } _: { _, _ in }
    }

    // Spec test group 10: containment ≠ containedRecordTypes fail-fasts in BOTH directions
    // (missing: DriftingBoard; surplus: SpareBoard); a matching declaration registers cleanly.
    @Test func containmentDriftThrows() async throws {
        try await withFluentTestApp { app in
            try app.register(Workspace.self, migration: CreateWorkspace()) // CreateBoard's DDL references workspaces
            app.migrations.add(CreatePier()) // and piers — both must exist first
            // Missing direction: declared Card, containment empty.
            do {
                try app.register(DriftingBoard.self, migration: CreateBoard())
                Issue.record("expected .containmentDrift (missing direction)")
            } catch let error as ContainmentError {
                guard case .containmentDrift = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.modelTypeRegistry.registered(for: DriftingBoard.modelIdentityNamespace) == nil)
            // Surplus direction: containment declares Boat, containedRecordTypes empty.
            do {
                try app.register(SpareBoard.self, migration: CreateBoard())
                Issue.record("expected .containmentDrift (surplus direction)")
            } catch let error as ContainmentError {
                guard case .containmentDrift = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.modelTypeRegistry.registered(for: SpareBoard.modelIdentityNamespace) == nil)
            // The matching declaration (Board) registers cleanly:
            try app.register(Board.self, migration: CreateBoard())
        } _: { _, _ in }
    }
}
