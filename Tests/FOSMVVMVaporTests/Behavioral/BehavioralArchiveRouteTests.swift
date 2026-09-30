// BehavioralArchiveRouteTests.swift
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

/// Design 1.11 and DocC 4.12: archiving marks a row deleted through its delete timestamp, so a
/// route for a model without one is refused where the mistake is cheapest — at boot.
@Suite("Behavioral: the archive route's boot check")
struct BehavioralArchiveRouteTests {
    @Test("An archive route registers for a model that declares a delete timestamp")
    func archiveRouteRegistersForATimestampedModel() async throws {
        try await withFluentTestApp { app in
            try registerBehavioralVault(app)
        } _: { app, _ in
            try app.register(request: BehavioralRelicArchiveRequest.self, app: app)
        }
    }

    @Test("An archive route for a model with no delete timestamp fails at boot with archiveUnsupported")
    func archiveRouteRefusesATimestamplessModel() async throws {
        try await withFluentTestApp { app in
            try registerBehavioralVault(app)
        } _: { app, _ in
            var thrown: (any Error)?
            do {
                try app.register(request: BehavioralCurioArchiveRequest.self, app: app)
            } catch {
                thrown = error
            }

            let error = try #require(thrown as? ServerRequestControllerError)
            guard case .archiveUnsupported = error else {
                Issue.record("expected .archiveUnsupported, got \(error)")
                return
            }
        }
    }

    /// negative space: the check names BOTH the request and the model, so a project with several
    /// archive routes can tell which one to fix. Named, not matched on its message text.
    @Test("archiveUnsupported names the request and the model it refused")
    func archiveUnsupportedNamesRequestAndModel() async throws {
        try await withFluentTestApp { app in
            try registerBehavioralVault(app)
        } _: { app, _ in
            var thrown: (any Error)?
            do {
                try app.register(request: BehavioralCurioArchiveRequest.self, app: app)
            } catch {
                thrown = error
            }

            let error = try #require(thrown as? ServerRequestControllerError)
            guard case .archiveUnsupported(let request, let model) = error else {
                Issue.record("expected .archiveUnsupported, got \(error)")
                return
            }
            #expect(request.contains("BehavioralCurioArchiveRequest"))
            #expect(model.contains("BehavioralCurio"))
        }
    }

    /// negative space: the refusal is a value a test (and a boot log) can match on, so the same
    /// case built twice is equal — `ServerRequestControllerError` is `Equatable` for this.
    @Test("Two archiveUnsupported values for one request and model are equal")
    func archiveUnsupportedIsMatchable() {
        let first = ServerRequestControllerError.archiveUnsupported(request: "R", model: "M")
        let second = ServerRequestControllerError.archiveUnsupported(request: "R", model: "M")
        let other = ServerRequestControllerError.archiveUnsupported(request: "R", model: "N")

        #expect(first == second)
        #expect(first != other)
    }
}
