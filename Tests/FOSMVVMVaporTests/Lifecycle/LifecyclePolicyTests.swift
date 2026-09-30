// LifecyclePolicyTests.swift
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

// The policy is observed through the row and through what the refusal carries — never through a log.

import Fluent
import FluentKit
import FOSFoundation
import FOSMVVM
import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("Validation warning policy (plan 1.8, OQ8, OQ28)")
struct LifecyclePolicyTests {
    /// The default: a warning on its own never stops the write.
    @Test func anAdvisoryWarningLeavesTheRowWritten() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            try await Gauge(value: 7).save(on: db)

            let count = try await Gauge.query(on: db).count()
            #expect(count == 1)
        }
    }

    /// Under `.blocking` the same warning refuses, and the client sees it.
    @Test func aBlockingWarningRefusesTheWrite() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            var thrown: (any Error)?
            do {
                try await Quota(value: 7).save(on: db)
            } catch {
                thrown = error
            }

            let error = try #require(thrown as? ValidationError)
            #expect(error.validations.map(\.status) == [.warning])

            let count = try await Quota.query(on: db).count()
            #expect(count == 0)
        }
    }

    /// Warnings are dropped only when the write stands: alongside an error they ride in the refusal.
    @Test func anAdvisoryWarningRidesWithAnError() async throws {
        try await withFluentTestApp { app in
            try registerLifecycleGraph(app)
        } _: { _, db in
            var thrown: (any Error)?
            do {
                try await Gauge(value: -1).save(on: db)
            } catch {
                thrown = error
            }

            let error = try #require(thrown as? ValidationError)
            #expect(error.validations.map(\.status) == [.warning, .error])

            let count = try await Gauge.query(on: db).count()
            #expect(count == 0)
        }
    }
}
