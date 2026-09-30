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
/// Workspace (the top container) → Board → Checklist (.guards) → ChecklistItem.
private func configureContainers(_ app: Application) throws {
    try app.register(Workspace.self, migration: CreateWorkspace())
    app.migrations.add(CreatePier()) // CreateBoard's DDL references piers
    try app.register(Board.self, migration: CreateBoard())
    try app.register(Checklist.self, migration: CreateChecklist())
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

/// A ModelIdentity for application-scope fixtures (id minted locally — no DB round-trip needed).
private func mintApplicationIdentity() throws -> ModelIdentity {
    let workspace = Workspace(name: "Top Workspace")
    workspace.id = ModelIdType()
    return try workspace.modelIdentity
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
private struct BoardScopedQuery: ScopedQuery {
    let scopeIdentity: ModelIdentity
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
private struct BoardPageVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = BoardPageRequest

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

    static let cards = Card.loadingPlan(.read, within: .parent, via: Board.self)
    static let checklistItems = ChecklistItem.loadingPlan(.read, within: .parent, via: Board.self, Checklist.self)

    static var loadingPlans: LoadingPlans {
        cards
        checklistItems
    }
}

private final class BoardPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    var responseBody: BoardPageVM?

    init(query: BoardScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: BoardPageVM? = nil) {
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

    static let cards = Card.loadingPlan(.read, within: .parent).refinedByRequest
    static let members = Member.loadingPlan(.read, within: .parent).refinedByRequest

    static var loadingPlans: LoadingPlans {
        cards
        members
    }
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

// MARK: - .query root WITHOUT a ScopedQuery

private struct UnscopedQueryVM: RegistrationFixture, RequestableViewModel {
    typealias Request = UnscopedQueryRequest

    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class UnscopedQueryRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: UnscopedQueryVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: UnscopedQueryVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - .application scope (a registration is required)

private struct ApplicationPageVM: RegistrationFixture, RequestableViewModel {
    typealias Request = ApplicationPageRequest

    static let boards = Board.loadingPlan(.read, within: .application)

    static var loadingPlans: LoadingPlans {
        boards
    }
}

private final class ApplicationPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: ApplicationPageVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ApplicationPageVM? = nil) {
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

/// Board is registered but declares no containment of ChecklistItem — the pair cannot resolve.
private struct BadHopVM: RegistrationFixture, RequestableViewModel {
    typealias Request = BadHopRequest

    static let checklistItems = ChecklistItem.loadingPlan(.read, within: .parent, via: Board.self)

    static var loadingPlans: LoadingPlans {
        checklistItems
    }
}

private final class BadHopRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    var responseBody: BadHopVM?

    init(query: BoardScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: BadHopVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Pier is never registered as a container — an intermediate hop through it cannot resolve.
private struct PierHopVM: RegistrationFixture, RequestableViewModel {
    typealias Request = PierHopRequest

    static let cards = Card.loadingPlan(.read, within: .parent, via: Pier.self)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class PierHopRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    var responseBody: PierHopVM?

    init(query: BoardScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: PierHopVM? = nil) {
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

    static let cards = Card.loadingPlan(.read, within: .parent).refinedByRequest

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class DeadMarkerRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    var responseBody: DeadMarkerVM?

    init(query: BoardScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: DeadMarkerVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Loads ChecklistItem — a record type Checklist (.guards) contains — on a path that
/// never traverses the folder: the guard cannot anchor this load. Warn, never throw.
private struct GuardsOffPathVM: RegistrationFixture, RequestableViewModel {
    typealias Request = GuardsOffPathRequest

    static let checklistItems = ChecklistItem.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        checklistItems
    }
}

private final class GuardsOffPathRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    var responseBody: GuardsOffPathVM?

    init(query: BoardScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: GuardsOffPathVM? = nil) {
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

    static let cards = Card.loadingPlan(.read, within: .parent).refinedByRequest

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class ForeignSortRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias Sort = ForeignSort
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    let sort: ForeignSort?
    var responseBody: ForeignSortVM?

    init(query: BoardScopedQuery? = nil, sort: ForeignSort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: ForeignSortVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.sort = sort
        self.responseBody = responseBody
    }
}

/// `.refinedByRequest` with a `SortCriteria` `Sort` — the standard bridge; no foreign-Sort warn.
private struct CriteriaSortVM: RegistrationFixture, RequestableViewModel {
    typealias Request = CriteriaSortRequest

    static let cards = Card.loadingPlan(.read, within: .parent).refinedByRequest

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class CriteriaSortRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias Sort = SortCriteria<CardSortKey>
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    let sort: SortCriteria<CardSortKey>?
    var responseBody: CriteriaSortVM?

    init(query: BoardScopedQuery? = nil, sort: SortCriteria<CardSortKey>? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: CriteriaSortVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.sort = sort
        self.responseBody = responseBody
    }
}

// MARK: - .subject scope (bound from the subject's grants — no binding to register)

private struct SubjectPageVM: RegistrationFixture, RequestableViewModel {
    typealias Request = SubjectPageRequest

    static let boards = Board.loadingPlan(.read, within: .subject)

    static var loadingPlans: LoadingPlans {
        boards
    }
}

/// A subject-scoped plan on a type this suite never registers (Card has no registration here).
private struct SubjectUnregisteredPageVM: RegistrationFixture, RequestableViewModel {
    typealias Request = SubjectUnregisteredPageRequest

    static let cards = Card.loadingPlan(.read, within: .subject)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class SubjectUnregisteredPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectUnregisteredPageVM?

    init(query _: EmptyQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: SubjectUnregisteredPageVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

private final class SubjectPageRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectPageVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SubjectPageVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

/// A creation plan within `.subject` — a create names the container it creates into, so the
/// subject scope cannot be one.
private struct SubjectCreateVM: RegistrationFixture, RequestableViewModel {
    typealias Request = SubjectCreateRequest

    static let boards = Board.creationPlan(within: .subject)

    static var loadingPlans: LoadingPlans {
        boards
    }
}

private final class SubjectCreateRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectCreateVM?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: SubjectCreateVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

// MARK: - .anyOperation is not a plan

private struct AnyOperationVM: RegistrationFixture, RequestableViewModel {
    typealias Request = AnyOperationRequest

    static let cards = Card.loadingPlan(.anyOperation, within: .request)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private final class AnyOperationRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = BoardScopedQuery
    typealias ResponseError = EmptyError

    let id: String
    let query: BoardScopedQuery?
    var responseBody: AnyOperationVM?

    init(query: BoardScopedQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: AnyOperationVM? = nil) {
        self.id = .random(length: 10)
        self.query = query
        self.responseBody = responseBody
    }
}

/// Mints a bare Vapor.Request — enough for the executor's binding step, which is where a
/// `.subject` plan stops today.
private func makeBareRequest(on app: Application) -> Vapor.Request {
    Request(
        application: app,
        method: .GET,
        url: URI(string: "/"),
        on: app.eventLoopGroup.next()
    )
}

// MARK: - Tests (spec test 7)

@Suite("RecordLoadPlan boot derivation + validation (C7)")
struct PlanRegistrationTests {
    /// A conforming ResponseBody derives a plan at registration; the stored plan is
    /// retrievable by request type and hop-resolves against the registered containment.
    @Test func conformingResponseBodyDerivesAndStoresPlan() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: BoardPageRequest.self)
            let plan = try #require(app.recordLoadPlan(for: BoardPageRequest.self))
            #expect(plan.tuples.count == 2)
            #expect(plan.tuples.allSatisfy { $0.root == .request })
        } _: { _, _ in }
    }

    /// The SHIPPED seam: registering the request's route on the Application derives the
    /// plan as a side effect — no separate derivation step to forget.
    @Test func routeRegistrationSeamDerivesThePlan() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.register(request: BoardPageRequest.self, app: app)
            #expect(app.recordLoadPlan(for: BoardPageRequest.self) != nil)
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
                try grouped.register(request: BoardPageRequest.self, app: app) // no configureContainers
                Issue.record("expected ContainmentError.invalidLoadPlan on a group mount without containers")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: BoardPageRequest.self) == nil)
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

    /// Boot check: loads within `.request` require the request's Query to conform to ScopedQuery.
    @Test func requestScopeWithoutScopedQueryFailsFast() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: UnscopedQueryRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: UnscopedQueryRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: loads within `.application` require a registered application scope.
    @Test func applicationScopeWithoutRegistrationFailsFast() async throws {
        try await withFluentTestApp { app in
            do {
                try app.registerRecordLoadPlan(for: ApplicationPageRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
            #expect(app.recordLoadPlan(for: ApplicationPageRequest.self) == nil)
        } _: { _, _ in }
    }

    /// With a resolver registered, the same `.application` plan derives and stores.
    @Test func applicationScopeWithRegistrationDerives() async throws {
        let applicationIdentity = try mintApplicationIdentity()
        try await withFluentTestApp { app in
            try app.useApplicationScope { _ in applicationIdentity }
            try app.registerRecordLoadPlan(for: ApplicationPageRequest.self)
            let plan = try #require(app.recordLoadPlan(for: ApplicationPageRequest.self))
            #expect(plan.tuples.count == 1)
            #expect(plan.tuples.allSatisfy { $0.root == .application })
        } _: { _, _ in }
    }

    /// Exactly one application scope per application — a second registration throws.
    @Test func duplicateApplicationScopeThrows() async throws {
        let applicationIdentity = try mintApplicationIdentity()
        try await withFluentTestApp { app in
            try app.useApplicationScope { _ in applicationIdentity }
            do {
                try app.useApplicationScope { _ in applicationIdentity }
                Issue.record("expected ContainmentError.duplicateApplicationScope")
            } catch let error as ContainmentError {
                guard case .duplicateApplicationScope = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
            }
        } _: { _, _ in }
    }

    /// Boot check: a conformer declaring neither loadingPlans nor children is meaningless.
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
            #expect(warnings.contains(allOf: "ChecklistItem", "Checklist", ".guards"))
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

    /// Boot check: a plan `within: .subject` needs no binding — its first hop is registered, so
    /// registration succeeds and the tuple carries the subject scope.
    @Test func subjectScopeNeedsNoBindingAndRegisters() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.registerRecordLoadPlan(for: SubjectPageRequest.self)
            let plan = try #require(app.recordLoadPlan(for: SubjectPageRequest.self))
            #expect(plan.tuples.count == 1)
            #expect(plan.tuples.allSatisfy { $0.root == .subject })
        } _: { _, _ in }
    }

    /// Boot check: a subject-scoped plan's first type must be registered — a grant binds it
    /// directly, so the registry must know it. Card is never registered in this suite.
    @Test func subjectScopedUnregisteredFirstTypeFailsFast() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            do {
                try app.registerRecordLoadPlan(for: SubjectUnregisteredPageRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan(_, let reason) = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
                #expect(reason.contains("is declared within the subject scope but is not registered"))
            }
            #expect(app.recordLoadPlan(for: SubjectUnregisteredPageRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: a creation plan within `.subject` is rejected — a create names the container
    /// it creates into.
    @Test func subjectScopedCreationPlanFailsFast() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            do {
                try app.registerRecordLoadPlan(for: SubjectCreateRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan(_, let reason) = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
                #expect(reason.contains("creation plan cannot be within the subject scope"))
            }
            #expect(app.recordLoadPlan(for: SubjectCreateRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Boot check: `.anyOperation` is a grant's wildcard, never a plan — a plan states the one
    /// authority its subject must hold.
    @Test func anyOperationPlanFailsFast() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            do {
                try app.registerRecordLoadPlan(for: AnyOperationRequest.self)
                Issue.record("expected ContainmentError.invalidLoadPlan")
            } catch let error as ContainmentError {
                guard case .invalidLoadPlan(_, let reason) = error else {
                    Issue.record("wrong case: \(error)")
                    return
                }
                #expect(reason.contains("cannot be .anyOperation"))
            }
            #expect(app.recordLoadPlan(for: AnyOperationRequest.self) == nil)
        } _: { _, _ in }
    }

    /// Request time: a `.subject` plan needs no query and no application scope to bind — a bare
    /// request executes it, and the subject's grants alone decide what it holds.
    @Test func subjectScopeBindsFromTheGrantsAlone() async throws {
        try await withFluentTestApp { app in
            try configureContainers(app)
            try app.useModelAuthorizationProvider(TestGrantsProvider())
            try app.registerRecordLoadPlan(for: SubjectPageRequest.self)
        } _: { app, db in
            let workspace = Workspace(name: "Grand Workspace")
            try await workspace.save(on: db)
            let pier = Pier(name: "North Pier")
            try await pier.save(on: db)
            let dock1 = try Board(name: "Board 1", pierId: pier.requireId(), workspaceId: workspace.requireId())
            try await dock1.save(on: db)
            app.storage[TestGrantsKey.self] = try [
                TestGrant(authorizedModel: dock1.modelIdentity, operations: [], recordTypes: [], modelOperations: [.read])
            ]
            let req = makeBareRequest(on: app)
            try await req.executeRecordLoadPlan(for: SubjectPageRequest())

            let tuple = try #require(req.tupleCacheKeys.keys.first)
            #expect(req.recordsByTuple()[tuple]?.count == 1)
            #expect(try req.registrationSet == [dock1.modelIdentity])
        }
    }

    // contract: `register(request:app:)` is a `RoutesBuilder` method, so grouped mounting compiles —
    // it is how a request mounts behind its guarding middleware. Plan derivation runs inside the door
    // regardless of the builder, so no mount path can skip it. A path-prefixing group is caught at
    // boot, not compile time: `try app.grouped("api").register(request: BoardPageRequest.self, app: app)`
    // compiles and throws `ContainmentError.pathPrefixedMount`, because the client derives the served
    // URL from the request type.
}
