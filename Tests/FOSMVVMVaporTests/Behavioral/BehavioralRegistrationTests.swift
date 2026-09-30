// BehavioralRegistrationTests.swift
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

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

/// Design 1.9 / OQ19 / DocC 4.7: `register(_:migration:)` is how a `DataModel` enters the
/// registry — container or not — and the lifecycle reaches the container, its contained types
/// and its pivots, once per type.
@Suite("Behavioral: registration and reach")
struct BehavioralRegistrationTests {
    @Test("A DataModel no container declares gets its hooks from the registration overload")
    func registeredUncontainedModelGetsHooks() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralProbes(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            try await BehavioralOrphan(name: "Fred").save(on: db)

            #expect(box.events(of: BehavioralOrphan.self) == [
                "willWrite(create)",
                "validateModel(create)",
                "didWrite(create)",
                "didCommit(create)"
            ])
        }
    }

    @Test("A DataModel added with app.migrations.add alone gets no hooks")
    func unregisteredModelGetsNoHooks() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            app.migrations.add(CreateBehavioralStray())
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            try await BehavioralStray(name: "Fred").save(on: db)

            // The row is written — and not one hook ran.
            let written = try await BehavioralStray.query(on: db).count()
            #expect(written == 1)
            #expect(box.events(of: BehavioralStray.self).isEmpty)
        }
    }

    @Test("A container registered with its migration gets its own hooks")
    func registeredContainerGetsHooks() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralContainment(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)

            try await BehavioralBox(name: "Bedrock").save(on: db)

            #expect(box.events(of: BehavioralBox.self) == [
                "willWrite(create)",
                "validateModel(create)",
                "didWrite(create)",
                "didCommit(create)"
            ])
        }
    }

    @Test("A contained type reached through its container gets hooks")
    func containedTypeGetsHooks() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralContainment(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let container = BehavioralBox(name: "Bedrock")
            try await container.save(on: db)

            try await BehavioralItem(title: "Fred", boxId: container.requireID()).save(on: db)

            #expect(box.events(of: BehavioralItem.self) == [
                "willWrite(create)",
                "validateModel(create)",
                "didWrite(create)",
                "didCommit(create)"
            ])
        }
    }

    @Test("A pivot reached through its container gets hooks")
    func pivotGetsHooks() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try registerBehavioralContainment(app)
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let container = BehavioralBox(name: "Bedrock")
            let tag = BehavioralTag(name: "quarry")
            try await container.save(on: db)
            try await tag.save(on: db)

            try await BehavioralBoxTag(boxId: container.requireID(), tagId: tag.requireID()).save(on: db)

            #expect(box.events(of: BehavioralBoxTag.self) == [
                "willWrite(create)",
                "validateModel(create)",
                "didWrite(create)",
                "didCommit(create)"
            ])
        }
    }

    @Test("A type reached through two containers runs each hook exactly once")
    func doubleReachedTypeRunsHooksOnce() async throws {
        try await withFluentTestApp { app in
            _ = behavioralBox(on: app)
            try app.register(BehavioralBox.self, migration: CreateBehavioralBox())
            try app.register(BehavioralCrate.self, migration: CreateBehavioralCrate())
            app.migrations.add(CreateBehavioralItem())
            app.migrations.add(CreateBehavioralTag())
            app.migrations.add(CreateBehavioralBoxTag())
        } _: { app, db in
            let box = try #require(app.behavioralEvents)
            let container = BehavioralBox(name: "Bedrock")
            try await container.save(on: db)

            try await BehavioralItem(title: "Fred", boxId: container.requireID()).save(on: db)

            #expect(box.count(of: "willWrite(create)", of: BehavioralItem.self) == 1)
            #expect(box.count(of: "validateModel(create)", of: BehavioralItem.self) == 1)
            #expect(box.count(of: "didWrite(create)", of: BehavioralItem.self) == 1)
            #expect(box.count(of: "didCommit(create)", of: BehavioralItem.self) == 1)
        }
    }

    /// negative space: DocC 4.7 says the call "Throws: if the model's namespace is already
    /// registered" — registering one type twice is a configuration mistake, not a second wiring.
    @Test("Registering the same type twice throws")
    func registeringTheSameTypeTwiceThrows() async throws {
        await #expect(throws: (any Error).self) {
            try await withFluentTestApp { app in
                try app.register(BehavioralOrphan.self, migration: CreateBehavioralOrphan())
                try app.register(BehavioralOrphan.self, migration: CreateBehavioralOrphan())
            } _: { _, _ in
            }
        }
    }
}
