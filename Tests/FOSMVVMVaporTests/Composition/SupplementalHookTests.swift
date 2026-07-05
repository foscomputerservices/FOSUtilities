// SupplementalHookTests.swift
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

// Spec §9 group 12 — the PUBLIC ``SupplementalRecordLoading`` conformance path. The protocol is
// public in C8, so these conformances need no `@testable` visibility of it; the executor that
// runs the hooks stays an internal seam, exercised via `@testable import FOSMVVMVapor` (sanctioned,
// same posture as PlanExecutorTests). No access level is widened for tests.

import Fluent // app.migrations lives in vapor/fluent
import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import FOSTestingVapor
import Foundation
import NIOConcurrencyHelpers
import Testing
import Vapor

// MARK: - Shared plumbing

/// Registers Harbor (apex) → Dock and a provider vending no grants — the declarative loads land
/// empty (nothing to authorize) but never throw, so execution reaches the supplemental phase.
private func configureContainers(_ app: Application) throws {
    app.migrations.add(CreatePier())
    try app.register(Harbor.self, migration: CreateHarbor())
    try app.register(Dock.self, migration: CreateDock())
    app.migrations.add(CreateBerth())
    app.migrations.add(CreateCrewMember())
    app.migrations.add(CreateDockCrew())
    try app.useContainerAuthorizationProvider(TestGrantsProvider())
}

private func makeRequest(on app: Application, url: URL) -> Vapor.Request {
    Request(application: app, method: .GET, url: URI(string: url.absoluteString), on: app.eventLoopGroup.next())
}

private func requestURL(for request: some ServerRequest) throws -> URL {
    let base = try #require(URL(string: "http://localhost"))
    return try #require(try base.appending(serverRequest: request))
}

/// Lock-guarded ordered sink for hook invocations, shared between the hooks (inside the app) and
/// the assertion. Records each conformer's name in the order its hook ran.
private final class HookRecorder: @unchecked Sendable {
    private let lock = NIOLock()
    private var names: [String] = []

    func record(_ name: String) {
        lock.withLock { names.append(name) }
    }

    var recorded: [String] {
        lock.withLock { names }
    }
}

private struct HookRecorderKey: StorageKey {
    typealias Value = HookRecorder
}

private extension Vapor.Request {
    var hookRecorder: HookRecorder? {
        application.storage[HookRecorderKey.self]
    }
}

// MARK: - Factory fixture plumbing (mirrors PlanExecutorTests' ExecutorFixture)

private struct SupplementalFixtureContext: ViewModelFactoryContext {
    var appVersion: SystemVersion {
        .init(major: 1, minor: 0)
    }
}

private protocol SupplementalFixture: ComposableFactory {
    init()
}

private extension SupplementalFixture {
    var vmId: ViewModelId {
        ViewModelId()
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func model(context: SupplementalFixtureContext) async throws -> Self {
        .init()
    }
}

private struct HookRootedQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

// MARK: - Group 12: walk-order fixtures (a diamond — Shared reachable via Left and Right)

/// Root: reads Berth (dock-rooted) and composes two subtrees that both reach `SharedChildVM`.
private struct ParentPageVM: SupplementalFixture, RequestableViewModel {
    typealias Request = ParentPageRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]

    static var children: [ComposedChild] {
        [.child(LeftChildVM.self), .child(RightChildVM.self)]
    }
}

extension ParentPageVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        request.hookRecorder?.record("Parent")
    }
}

private struct LeftChildVM: SupplementalFixture {
    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(CrewMember.self, in: .parentRoot)]

    static var children: [ComposedChild] {
        [.child(SharedChildVM.self)]
    }
}

extension LeftChildVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        request.hookRecorder?.record("Left")
    }
}

private struct RightChildVM: SupplementalFixture {
    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(CrewMember.self, in: .parentRoot)]

    static var children: [ComposedChild] {
        [.child(SharedChildVM.self)]
    }
}

extension RightChildVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        request.hookRecorder?.record("Right")
    }
}

/// Reachable from both `LeftChildVM` and `RightChildVM` — the runner must visit it ONCE.
private struct SharedChildVM: SupplementalFixture {
    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(CrewMember.self, in: .parentRoot)]
}

extension SharedChildVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        request.hookRecorder?.record("Shared")
    }
}

private final class ParentPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = HookRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: HookRootedQuery?
    var responseBody: ParentPageVM?

    init(query: HookRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ParentPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Group 12: a throwing child hook fails the whole request

private enum HookFailure: Error {
    case deliberate
}

private struct ThrowRootVM: SupplementalFixture, RequestableViewModel {
    typealias Request = ThrowRootRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]

    static var children: [ComposedChild] {
        [.child(ThrowingChildVM.self)]
    }
}

private struct ThrowingChildVM: SupplementalFixture {
    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(CrewMember.self, in: .parentRoot)]
}

extension ThrowingChildVM: SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws {
        throw HookFailure.deliberate
    }
}

private final class ThrowRootRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = HookRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: HookRootedQuery?
    var responseBody: ThrowRootVM?

    init(query: HookRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ThrowRootVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Tests (spec §9 group 12)

@Suite("SupplementalRecordLoading — the public load-phase hook (C8)")
struct SupplementalHookTests {
    /// Public conformers run AFTER the declarative plan, in composition-walk order (parent
    /// before child, declaration order), and each factory runs EXACTLY once — the diamond's
    /// `SharedChildVM`, reachable via both `LeftChildVM` and `RightChildVM`, runs a single time.
    @Test func publicHooksRunPostDeclarativeInWalkOrderEachOnce() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            app.storage[HookRecorderKey.self] = HookRecorder()
            try app.registerRecordLoadPlan(for: ParentPageRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let vmRequest = try ParentPageRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            try await req.executeRecordLoadPlan(for: vmRequest)

            let recorded = try #require(app.storage[HookRecorderKey.self]).recorded
            // Parent-before-child: the root conformer runs before any of its descendants.
            #expect(recorded.first == "Parent")
            // Depth-first, declaration order: Parent, then Left's subtree (Left, Shared), then Right.
            #expect(recorded == ["Parent", "Left", "Shared", "Right"])
            // Each factory once — Shared is reached via two paths but runs a single time.
            #expect(recorded.count(where: { $0 == "Shared" }) == 1)
            #expect(Set(recorded).count == recorded.count)
        }
    }

    /// A throwing hook fails the whole request — the error propagates, never swallowed to an
    /// empty result (the public contract's no-silent-guess discipline).
    @Test func throwingHookFailsTheRequest() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: ThrowRootRequest.self)
        } _: { app, db in
            let (dock1, _) = try await seedHarbor(on: db)
            let vmRequest = try ThrowRootRequest(query: .init(rootIdentity: dock1.modelIdentity))
            let req = try makeRequest(on: app, url: requestURL(for: vmRequest))
            await #expect(throws: HookFailure.self) {
                try await req.executeRecordLoadPlan(for: vmRequest)
            }
        }
    }
}
