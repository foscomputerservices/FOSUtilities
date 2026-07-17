// PlanRegistrationTests.swift
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

// Test-taxonomy discipline: boot derivation/validation is an internal seam, exercised via
// `@testable import FOSMVVMVapor` (sanctioned — same posture as AnchoredEngineTests). Plan
// assertions land at RecordLoadPlan's `package` surface (plain FOSMVVM import — same package).

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

/// Registers the container graph the hop checks resolve against:
/// Harbor (apex) → Dock → PersonnelFolder (.guards) → PersonnelFile.
private func configureContainers(_ app: Application) throws {
    try app.register(Harbor.self, migration: CreateHarbor())
    app.migrations.add(CreatePier()) // CreateDock's DDL references piers
    try app.register(Dock.self, migration: CreateDock())
    try app.register(PersonnelFolder.self, migration: CreatePersonnelFolder())
}

// MARK: - Warning capture (the warn IS the spec §6 contract — assert it fires)

/// Lock-guarded warning sink shared between the handler (inside the app) and the assertion.
private final class CapturedWarnings: @unchecked Sendable {
    private let lock = NIOLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var all: [String] {
        lock.withLock { messages }
    }

    func contains(allOf fragments: String...) -> Bool {
        all.contains { message in fragments.allSatisfy { message.contains($0) } }
    }
}

/// Captures `.warning`+ messages; forwards nothing (tests stay quiet).
private struct CapturingLogHandler: LogHandler {
    let captured: CapturedWarnings

    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .warning

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // swiftlint:disable:next function_parameter_count
    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level >= .warning else {
            return
        }
        captured.append(message.description)
    }
}

/// Rebinds the app's logger to the capturing sink — the boot checks warn through
/// `Application.logger`, so this intercepts exactly what production would emit.
private func captureWarnings(of app: Application) -> CapturedWarnings {
    let captured = CapturedWarnings()
    app.logger = Logger(label: "plan-registration-tests") { _ in
        CapturingLogHandler(captured: captured)
    }
    return captured
}

/// A ModelIdentity for apex-resolver fixtures (id minted locally — no DB round-trip needed).
private func mintApexIdentity() throws -> ModelIdentity {
    let harbor = Harbor(name: "Apex Harbor")
    harbor.id = ModelIdType()
    return try harbor.modelIdentity
}

// MARK: - Factory fixture plumbing (mirrors RecordLoadPlanTests' PlanFixture)

/// Minimal `ViewModelFactoryContext` for trait conformers that never project.
private struct RegistrationFixtureContext: ViewModelFactoryContext {
    var appVersion: SystemVersion {
        .init(major: 1, minor: 0)
    }
}

/// A plain-struct `ComposableFactory` conformer: only the trait's declaration
/// members vary per fixture; everything else defaults here.
private protocol RegistrationFixture: ComposableFactory {
    init()
}

private extension RegistrationFixture {
    var vmId: ViewModelId {
        ViewModelId()
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func model(context: RegistrationFixtureContext) async throws -> Self {
        .init()
    }
}

/// The Query fixture that vends a root — `.query`-rooted plans boot-check for this conformance.
private struct DockRootedQuery: RootedQuery {
    let rootIdentity: ModelIdentity
}

/// A no-op middleware — grouping on it proves the registration door works on a middleware group
/// (not only the `Application`) while changing nothing about the served path.
private struct PassthroughMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        try await next.respond(to: request)
    }
}

// MARK: - The positive pair: hop-validated plan through the REAL registration seam

/// Conforms to VaporResponseBodyFactory (not RegistrationFixture) so `register(request:)` —
/// the shipped seam — accepts it and derives its plan.
private struct DockPageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = DockPageRequest

    var vmId = ViewModelId()

    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }

    static let dataRequirements: [any DataRequirement] = [
        LoadRequirement.read(Berth.self, in: .parentRoot, via: Dock.self),
        LoadRequirement.read(PersonnelFile.self, in: .parentRoot, via: Dock.self, PersonnelFolder.self)
    ]
}

private final class DockPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: DockPageVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DockPageVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Cycle fixtures (walk fail-fast surfaces at registration)

private struct CycleAVM: RegistrationFixture {
    static var children: [ComposedChild] {
        [.child(CycleBVM.self)]
    }
}

private struct CycleBVM: RegistrationFixture {
    static var children: [ComposedChild] {
        [.child(CycleAVM.self)]
    }
}

private struct CyclePageVM: RegistrationFixture, RequestableViewModel {
    typealias Request = CyclePageRequest

    static var children: [ComposedChild] {
        [.child(CycleAVM.self)]
    }
}

private final class CyclePageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: CyclePageVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: CyclePageVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - Multiple .refinedByRequest fixtures

private struct DoubleMarkVM: RegistrationFixture, RequestableViewModel {
    typealias Request = DoubleMarkRequest

    static let dataRequirements: [any DataRequirement] = [
        LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest,
        LoadRequirement.read(CrewMember.self, in: .parentRoot).refinedByRequest
    ]
}

private final class DoubleMarkRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: DoubleMarkVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DoubleMarkVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - .query root WITHOUT a RootedQuery

private struct UnrootedQueryVM: RegistrationFixture, RequestableViewModel {
    typealias Request = UnrootedQueryRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot)]
}

private final class UnrootedQueryRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: UnrootedQueryVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: UnrootedQueryVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - .apex root (resolver required)

private struct ApexPageVM: RegistrationFixture, RequestableViewModel {
    typealias Request = ApexPageRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Dock.self, in: .newRoot(.apex))]
}

private final class ApexPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: ApexPageVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ApexPageVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - All-empty conformer

private struct EmptyPageVM: RegistrationFixture, RequestableViewModel {
    typealias Request = EmptyPageRequest
}

private final class EmptyPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: EmptyPageVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: EmptyPageVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - Unresolvable hops

/// Dock is registered but declares no containment of PersonnelFile — the pair cannot resolve.
private struct BadHopVM: RegistrationFixture, RequestableViewModel {
    typealias Request = BadHopRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(PersonnelFile.self, in: .parentRoot, via: Dock.self)]
}

private final class BadHopRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: BadHopVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: BadHopVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Pier is never registered as a container — an intermediate hop through it cannot resolve.
private struct PierHopVM: RegistrationFixture, RequestableViewModel {
    typealias Request = PierHopRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot, via: Pier.self)]
}

private final class PierHopRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: PierHopVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: PierHopVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Warn-only fixtures (dead marker; .guards off path)

/// `.refinedByRequest` while the request type declares NO axes (Sort == EmptySort,
/// Query is not PaginatedQuery) — dead marker: warn, never throw.
private struct DeadMarkerVM: RegistrationFixture, RequestableViewModel {
    typealias Request = DeadMarkerRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest]
}

private final class DeadMarkerRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: DeadMarkerVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DeadMarkerVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Loads PersonnelFile — a record type PersonnelFolder (.guards) contains — on a path that
/// never traverses the folder: the guard cannot anchor this load. Warn, never throw.
private struct GuardsOffPathVM: RegistrationFixture, RequestableViewModel {
    typealias Request = GuardsOffPathRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(PersonnelFile.self, in: .parentRoot)]
}

private final class GuardsOffPathRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    var responseBody: GuardsOffPathVM?

    init(query: DockRootedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: GuardsOffPathVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

// MARK: - Sort-bridge warn fixtures (spec §9 group 13)

/// A `Sort` that conforms to `ServerRequestSort` but is neither `EmptySort` nor `SortCriteria` —
/// the executor's refinement bridge produces zero terms for it, so its sort is silently ignored.
private struct ForeignSort: ServerRequestSort {
    let raw: String
}

/// `.refinedByRequest` with a foreign `Sort` — registration derives the plan but WARNS that the
/// sort contributes zero terms.
private struct ForeignSortVM: RegistrationFixture, RequestableViewModel {
    typealias Request = ForeignSortRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest]
}

private final class ForeignSortRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias Sort = ForeignSort
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    let sort: ForeignSort?
    var responseBody: ForeignSortVM?

    init(query: DockRootedQuery? = nil, sort: ForeignSort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ForeignSortVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.sort = sort
        self.responseBody = responseBody
    }
}

/// `.refinedByRequest` with a `SortCriteria` `Sort` — the standard bridge; no foreign-Sort warn.
private struct CriteriaSortVM: RegistrationFixture, RequestableViewModel {
    typealias Request = CriteriaSortRequest

    static let dataRequirements: [any DataRequirement] = [LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest]
}

private final class CriteriaSortRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = DockRootedQuery
    typealias Sort = SortCriteria<BerthSortKey>
    typealias ResponseError = EmptyError

    let id: String
    let query: DockRootedQuery?
    let sort: SortCriteria<BerthSortKey>?
    var responseBody: CriteriaSortVM?

    init(query: DockRootedQuery? = nil, sort: SortCriteria<BerthSortKey>? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: CriteriaSortVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.sort = sort
        self.responseBody = responseBody
    }
}

// MARK: - Tests (spec test 7)

@Suite("RecordLoadPlan boot derivation + validation (C7)")
struct PlanRegistrationTests {
    /// A conforming ResponseBody derives a plan at registration; the stored plan is
    /// retrievable by request type and hop-resolves against the registered containment.
    @Test func conformingResponseBodyDerivesAndStoresPlan() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: DockPageRequest.self)
            let plan = try #require(app.recordLoadPlan(for: DockPageRequest.self))
            #expect(plan.tuples.count == 2)
            #expect(plan.tuples.allSatisfy { $0.root == .query })
        } _: { _, _ in }
    }

    /// The SHIPPED seam: registering the request's route on the Application derives the
    /// plan as a side effect — no separate derivation step to forget.
    @Test func routeRegistrationSeamDerivesThePlan() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.register(request: DockPageRequest.self, app: app)
            #expect(app.recordLoadPlan(for: DockPageRequest.self) != nil)
        } _: { _, _ in }
    }

    /// Contract 5: registering on a middleware group derives and validates the plan exactly as the
    /// root form does — a composable body mounted on a group WITHOUT its containers registered
    /// throws the same boot error as `try app.register(request:app:)`. Where a request mounts is the
    /// caller's decision; that its plan is derived is not.
    @Test func groupMountDerivesPlanAndFailsFastWithoutContainers() async throws {
        try await withFluentTestApp { app in
            let grouped = app.grouped(PassthroughMiddleware())
            do {
                try grouped.register(request: DockPageRequest.self, app: app) // no configureContainers
                Issue.record("expected ContainmentError.invalidLoadPlan on a group mount without containers")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: DockPageRequest.self) == nil)
        } _: { _, _ in }
    }

    /// A non-conforming (legacy) ResponseBody derives nothing: no plan, no throw.
    @Test func nonConformingResponseBodyStoresNoPlan() async throws {
        try await withFluentTestApp { app in
            try app.registerRecordLoadPlan(for: TestViewModelRequest.self)
            #expect(app.recordLoadPlan(for: TestViewModelRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: a composition cycle fails registration with the walk's typed error.
    @Test func cycleFailsFastAtRegistration() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: CyclePageRequest.self)
                Issue.record("expected RecordLoadPlan.WalkError.cycle")
            } catch let error as RecordLoadPlan.WalkError {
                guard case .cycle = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: CyclePageRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: more than one `.refinedByRequest` mark fails registration.
    @Test func multipleRefinedByRequestFailsFastAtRegistration() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: DoubleMarkRequest.self)
                Issue.record("expected RecordLoadPlan.WalkError.multipleRefinedByRequest")
            } catch let error as RecordLoadPlan.WalkError {
                guard case .multipleRefinedByRequest = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: DoubleMarkRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: `.query`-rooted loads require the request's Query to conform to RootedQuery.
    @Test func queryRootWithoutRootedQueryFailsFast() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: UnrootedQueryRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: UnrootedQueryRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: `.apex`-rooted loads require a registered apex container resolver.
    @Test func apexRootWithoutResolverFailsFast() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: ApexPageRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: ApexPageRequest.self) == nil)
        } _: { _, _ in }
    }

    /// With a resolver registered, the same `.apex`-rooted plan derives and stores.
    @Test func apexRootWithResolverDerives() async throws {
        let apexIdentity = try mintApexIdentity()
        try await withFluentTestApp { app in
            try app.useApexContainerResolver { _ in apexIdentity }
            try app.registerRecordLoadPlan(for: ApexPageRequest.self)
            let plan = try #require(app.recordLoadPlan(for: ApexPageRequest.self))
            #expect(plan.tuples.count == 1)
            #expect(plan.tuples.allSatisfy { $0.root == .apex })
        } _: { _, _ in }
    }

    /// Exactly one apex resolver per application — a second registration throws.
    @Test func duplicateApexResolverThrows() async throws {
        let apexIdentity = try mintApexIdentity()
        try await withFluentTestApp { app in
            try app.useApexContainerResolver { _ in apexIdentity }
            do {
                try app.useApexContainerResolver { _ in apexIdentity }
                Issue.record("expected ContainmentError.duplicateApexContainerResolver")
            } catch let error as ContainmentError {
                guard case .duplicateApexContainerResolver = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        } _: { _, _ in }
    }

    /// Boot check: a conformer declaring neither dataRequirements nor children is meaningless.
    @Test func allEmptyConformerFailsFast() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: EmptyPageRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: EmptyPageRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: a hop pair with no registered ContainmentRelation fails registration.
    @Test func unresolvableHopFailsFast() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            do {
                try app.registerRecordLoadPlan(for: BadHopRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: BadHopRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: an intermediate hop through an unregistered container fails registration.
    @Test func unregisteredHopContainerFailsFast() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            do {
                try app.registerRecordLoadPlan(for: PierHopRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: PierHopRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Warn-only: a dead `.refinedByRequest` (request type declares no axes) still derives —
    /// and the warning FIRES (the warn is the spec §6 contract, not a courtesy).
    @Test func deadRefinementMarkerWarnsButDerives() async throws {
        try await withFluentTestApp { app in
            let warnings = captureWarnings(of: app)
            try app.registerRecordLoadPlan(for: DeadMarkerRequest.self)
            let plan = try #require(app.recordLoadPlan(for: DeadMarkerRequest.self))
            #expect(plan.tuples.contains { $0.isRefinedByRequest })
            #expect(warnings.contains(allOf: ".refinedByRequest", "DeadMarkerRequest", "no refinement axes"))
        } _: { _, _ in }
    }

    /// Warn-only: a `.guards` container bypassed by every declared path still derives —
    /// and the warning FIRES, naming the bypassed guard and the bypassing record type.
    @Test func guardsOffPathWarnsButDerives() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            let warnings = captureWarnings(of: app)
            try app.registerRecordLoadPlan(for: GuardsOffPathRequest.self)
            #expect(app.recordLoadPlan(for: GuardsOffPathRequest.self) != nil)
            #expect(warnings.contains(allOf: "PersonnelFile", "PersonnelFolder", ".guards"))
        } _: { _, _ in }
    }

    /// Spec §9 group 13 — Sort-bridge boot warn: a `.refinedByRequest` plan whose request `Sort`
    /// is a foreign conformer (neither `EmptySort` nor `SortCriteria`) still derives, and the
    /// warning FIRES naming the request and the ignored `Sort` type — the silent zero-terms no-op
    /// becomes visible.
    @Test func foreignSortOnRefinedPlanWarnsAtRegistration() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            let warnings = captureWarnings(of: app)
            try app.registerRecordLoadPlan(for: ForeignSortRequest.self)
            #expect(app.recordLoadPlan(for: ForeignSortRequest.self) != nil)
            #expect(warnings.contains(allOf: "ForeignSortRequest", "ForeignSort", "zero sort terms"))
        } _: { _, _ in }
    }

    /// Spec §9 group 13 — the foreign-Sort warn stays SILENT for the two recognized bridges:
    /// `EmptySort` (returns early) and `SortCriteria` (the `ErasedSortTermsProviding` conformer),
    /// even on `.refinedByRequest` plans.
    @Test func emptySortAndSortCriteriaStaySilentOnTheSortBridge() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            let warnings = captureWarnings(of: app)
            try app.registerRecordLoadPlan(for: DeadMarkerRequest.self) // EmptySort + .refinedByRequest
            try app.registerRecordLoadPlan(for: CriteriaSortRequest.self) // SortCriteria + .refinedByRequest
            #expect(app.recordLoadPlan(for: CriteriaSortRequest.self) != nil)
            // Neither recognized bridge emits the foreign-Sort (zero-terms) warning.
            #expect(!warnings.contains(allOf: "zero sort terms"))
        } _: { _, _ in }
    }

    // contract: `register(request:app:)` is a `RoutesBuilder` method, so grouped mounting compiles —
    // it is how a request mounts behind its guarding middleware. Plan derivation runs inside the door
    // regardless of the builder, so no mount path can skip it. A path-prefixing group is caught at
    // boot, not compile time: `try app.grouped("api").register(request: DockPageRequest.self, app: app)`
    // compiles and throws `ContainmentError.pathPrefixedMount`, because the client derives the served
    // URL from the request type.
}
