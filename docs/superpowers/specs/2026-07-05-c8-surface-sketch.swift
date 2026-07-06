// C8 SURFACE SKETCH — rev 3, post dual-review. NOT compiled by any target;
// unresolved-symbol errors in Xcode are expected and fine.
//
// Slate (approved rev 2): 2A ComposableFactory · 3A ProjectionContext (merged)
// · 4A DataModelWriter · 5A useAppState · 6A useApexContainerResolver ·
// 7A register(request:) · 7½ SupplementalRecordLoading unchanged.
//
// Decisions: D-C8-1 one factory, narrowed context (BREAKING) · D-C8-2 AppState
// slot (hole accepted per exploitability model) · D-C8-3 write = apply +
// fall-through · D-C8-4 VaporResponseBodyFactory + trait un-pin · D-C8-5
// DataRequirement sealed · D-C8-6 pack-based `via:` · NEW (post-review, David
// "go"): D-C8-7 typed refresh bridge (write requests name + build their
// refresh read request) · D-C8-8 candidate sets live on the WRITE side
// (WriteTargetProviding; GETs never load them) · D-C8-9 apply is SEALED —
// synchronous, no Database (framework owns ALL I/O on both sides; "load in
// the handler" is a worn footpath, unlike the no-gravity AppState slot).
//
// OPEN from rev 2 all resolved as sketched. Remaining open name:
// `WriteTargetProviding` — David may rename on the final spec read.

import FluentKit
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/ComposableFactory.swift   (rename)
// ═══════════════════════════════════════════════════════════════════════

/// Declares the data a composable factory projects — co-located with the
/// factory, aggregated automatically, loaded once per request.
///
/// ```swift
/// extension DockPageViewModel: ComposableFactory {
///     static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
///         .refinedByRequest
///
///     static var dataRequirements: [any DataRequirement] { [berths] }
///     static var children: [ComposedChild] {
///         [.child(BerthCellViewModel.self)]
///     }
/// }
/// ```
///
/// Un-pinned from ViewModels (D-C8-4): ANY `ResponseBody` producer may adopt —
/// a screen's ViewModel, a CLI report body, an export. The C7 boot guard is
/// unchanged: adopting and declaring nothing fails fast at boot.
public protocol ComposableFactory: Sendable {

    /// This factory's own data needs. Empty is meaningful: a pure composer.
    static var dataRequirements: [any DataRequirement] { get }   // default []

    /// The child factories this factory composes. Only trait-conforming
    /// types can appear — an undeclared child cannot be composed.
    static var children: [ComposedChild] { get }                 // default []
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/DataRequirement.swift   (sealed, D-C8-5)
// ═══════════════════════════════════════════════════════════════════════

/// One declared data need of a composable factory — a sealed declaration
/// token. Mint with ``LoadRequirement``; the protocol carries no members.
///
/// A foreign conformance is rejected at boot ("unknown requirement kind") —
/// the walk reads requirements through an internal face only.
public protocol DataRequirement: Sendable {}

// Internal walk face (FOSMVVM-internal; shown for the review only):
//
// protocol DataRequirementWalkFace {
//     var recordType: any Model.Type { get }
//     var rootScope: RootScope { get }
//     var intermediates: [any Model.Type] { get }   // erasure lives HERE,
//     var operation: ContainerOperation { get }     // behind the seal —
//     var isRefinedByRequest: Bool { get }          // never on the API
// }
//
// Cross-module (FOSMVVMVapor) reads go through the already-sanctioned
// RecordLoadPlan package site, which gains a handle→tuple lookup member
// (named consumer: ProjectionContext.records(_:)). Zero new package SITES.

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/LoadRequirement.swift
// MARK:   (write-family verbs NEW · pack-based `via:` per D-C8-6)
// ═══════════════════════════════════════════════════════════════════════

/// A typed load: records of one type, in one rooted scope, under one
/// authority. Every requirement LOADS — the verb names the authority
/// exercised, never the SQL.
///
/// `.read` requirements belong to factories (``ComposableFactory``); the
/// write-family verbs belong to write requests (``WriteTargetProviding``,
/// D-C8-8) and load the CANDIDATE SET the submitted target must belong to.
/// A plain GET never loads a candidate set.
public struct LoadRequirement<Record: Model>: DataRequirement {

    /// Records this scope's grants authorize reading.
    ///
    /// ```swift
    /// .read(Berth.self, in: .parentRoot)              // one hop: implicit
    /// .read(SlipAssignment.self, in: .parentRoot,
    ///       via: Berth.self)                          // via = INTERMEDIATE hops only
    /// ```
    ///
    /// `via:` lists the *intermediate* containment hops from the root — the
    /// terminal hop to `record` is always implicit; never list it.
    public static func read<each Hop: Model>(
        _ record: Record.Type,
        in root: RootScope,
        via intermediates: repeat (each Hop).Type
    ) -> LoadRequirement<Record> {
        fatalError("sketch")
    }

    /// Records this scope's grants authorize updating — an `UpdateRequest`'s
    /// candidate set (D-C8-3 step 4: the resolved target must be a member).
    public static func write<each Hop: Model>(
        _ record: Record.Type,
        in root: RootScope,
        via intermediates: repeat (each Hop).Type
    ) -> LoadRequirement<Record> {
        fatalError("sketch")
    }

    /// The scope a caller may create records into — a `CreateRequest`'s
    /// candidate scope. Restricted to ZERO intermediates (the root container
    /// IS the create scope): a `via:` path can fan out to N container
    /// instances and "which one receives the record" must never be a guess.
    public static func create(
        _ record: Record.Type,
        in root: RootScope
    ) -> LoadRequirement<Record> {
        fatalError("sketch")
    }

    /// Records this scope's grants authorize deleting — a `DeleteRequest`'s
    /// candidate set.
    public static func delete<each Hop: Model>(
        _ record: Record.Type,
        in root: RootScope,
        via intermediates: repeat (each Hop).Type
    ) -> LoadRequirement<Record> {
        fatalError("sketch")
    }

    /// The one requirement the request's declared refinement axes land on
    /// (its `Sort` associatedtype, its ``PaginatedQuery`` conformance).
    /// At most one requirement per plan may carry the mark.
    public var refinedByRequest: LoadRequirement<Record> {
        fatalError("sketch")
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/TargetedQuery.swift   (NEW)
// ═══════════════════════════════════════════════════════════════════════

/// A `Query` that names which loaded record a write request targets.
///
/// The selector is the record's opaque ``ModelIdentity`` — the L0 token the
/// client received inside the ViewModel it displayed, echoed back verbatim.
/// The form body NEVER carries an id (firm rule): the server resolves this
/// selector against the auth-scoped candidate set it loaded itself — a
/// submit cannot retarget. Resolution failure is indistinguishable from
/// not-found (not-yours == not-found; no authorization oracle).
///
/// Sibling of ``RootedQuery`` / ``PaginatedQuery`` — one trait per concern.
/// Required at COMPILE TIME on update/delete registration (`where` clause).
public protocol TargetedQuery: ServerRequestQuery {
    /// The targeted record's opaque identity, from the ViewModel the client
    /// displayed. Resolved server-side against the loaded candidate set.
    var target: ModelIdentity { get }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  write CRUD protocols gain the refresh bridge (D-C8-7)
// MARK:   (amends shipped CreateRequest / UpdateRequest / DeleteRequest)
// ═══════════════════════════════════════════════════════════════════════

// NO NEW TYPE HERE. This block amends the EXISTING shared protocols
// CreateRequest / UpdateRequest / DeleteRequest in place
// (Sources/FOSMVVM/Protocols/) — shown as a comment because this sketch
// file also USES UpdateRequest below and cannot redeclare it. Each of the
// three write CRUD protocols gains exactly these members:
//
//     public protocol UpdateRequest: ServerRequest
//         where ResponseBody == RefreshRequest.ResponseBody {   // NEW constraint
//
//         associatedtype RefreshRequest: ServerRequest          // NEW
//
//         /// Builds the read request pass #2 re-serves after this
//         /// write commits.
//         func refreshRequest() -> RefreshRequest               // NEW
//     }
//
// After the write commits, the server re-serves a READ request — pass #2 is
// the genuine GET pipeline run on refreshRequest(), not a special path.
// The authored bridge is a pure value mapping (shared module):
//
//     func refreshRequest() -> DockPageRequest {
//         DockPageRequest(query: .init(dock: query.dock))
//     }
//
// The write request's ResponseBody is its refresh request's — by
// constraint, not convention: the caller always receives the fresh screen.

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  Protocols/VaporResponseBodyFactory.swift
// MARK:   (replaces VaporViewModelFactory — D-C8-1/D-C8-4, BREAKING)
// ═══════════════════════════════════════════════════════════════════════

/// Produces a request's `ResponseBody` on the server — the one factory for
/// every server-rendered body, ViewModel or not.
///
/// ```swift
/// extension DockPageViewModel: VaporResponseBodyFactory {
///     static func body(context: ProjectionContext<Request, Void>) throws -> Self {
///         .init(berthCells: try context.records(Self.berths)
///             .map { BerthCellViewModel(berth: $0) })
///     }
/// }
/// ```
///
/// The projection is handed a ``ProjectionContext`` — never a `Vapor.Request`,
/// never a `Database`. Records were loaded BEFORE projection began (auth-
/// scoped, cached, per the factory's declared requirements); a data need the
/// factory forgot to declare fails fast instead of loading silently.
///
/// `body` is synchronous — `throws`, never `async`. Loading belongs to the
/// load phase (declare it, or use ``SupplementalRecordLoading``); an
/// awaitable projection is the hole this type exists to close.
public protocol VaporResponseBodyFactory: ServerRequestBody, Vapor.AsyncResponseEncodable {

    associatedtype Request: ServerRequest where Request.ResponseBody == Self
    associatedtype AppState: Sendable = Void

    static func body(context: ProjectionContext<Request, AppState>) throws -> Self
}

public extension VaporResponseBodyFactory {
    /// Serving is unchanged: localization + SystemVersion header have exactly
    /// one home — the shared `ServerRequestBody.buildResponse(_:)`.
    func encodeResponse(for request: Vapor.Request) async throws -> Vapor.Response {
        try buildResponse(request)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  Containment/ProjectionContext.swift   (NEW)
// ═══════════════════════════════════════════════════════════════════════

/// Everything a projection may see: the typed request, the app-declared
/// state, and typed reads of the records the plan loaded. Nothing else.
///
/// ```swift
/// static func body(context: ProjectionContext<Request, SessionBanner>) throws -> Self {
///     let berths = try context.records(Self.berths)              // own handle
///     let crew   = try context.records(CrewListViewModel.crew)   // a child's
///     return .init(..., signedInAs: context.appState.userName)
/// }
/// ```
///
/// Read it inside `body(context:)` and let it go: the context must not
/// escape the projection (no capturing it in a spawned `Task`) — reads are
/// contracted to the request's handler task, like everything request-scoped.
public struct ProjectionContext<Request: ServerRequest, AppState: Sendable>: ViewModelFactoryContext {

    /// The typed request — query, sort, pagination, selectors.
    public let vmRequest: Request

    /// The app-declared per-request value, built by the closure registered
    /// with ``Vapor/Application/useAppState(_:builder:)`` — the sanctioned
    /// home for session-derived display data. `Void` when nothing registered.
    public let appState: AppState

    /// The client's requested SystemVersion (``ViewModelFactoryContext``).
    public var appVersion: SystemVersion {
        get throws { fatalError("sketch") }
    }

    /// The records a declared requirement loaded — read by the SAME static
    /// handle the factory declared. Any handle in the request's plan is
    /// readable, including a child factory's (that is how parents compose).
    ///
    /// A handle that never reached the plan THROWS — never returns `[]`.
    /// A silently-empty screen is a misconfiguration's invisible mode; the
    /// throw names the handle and the factory that forgot to list it.
    public func records<Record: Model>(
        _ handle: LoadRequirement<Record>
    ) throws -> [Record] {
        fatalError("sketch")
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  Protocols/WriteTargetProviding.swift   (NEW,
// MARK:   D-C8-8 — name still open to David's rename)
// ═══════════════════════════════════════════════════════════════════════

/// Declares a write request's CANDIDATE SET: the records the caller is
/// authorized to mutate, loaded auth-scoped BEFORE the write runs. Adopted
/// by the shared `RequestBody` in the SERVER target.
///
/// ```swift
/// extension DeleteBerthRequest.RequestBody: WriteTargetProviding {
///     static let candidates = LoadRequirement.delete(Berth.self, in: .parentRoot)
/// }
/// ```
///
/// Exactly ONE candidate set per write request — by construction, not by
/// convention. On a writer, `.parentRoot` anchors at the write request's own
/// query root (there is no parent factory). The resolved ``TargetedQuery``
/// target must be a member, or the request fails with not-found semantics.
///
/// `DeleteRequest` bodies conform to THIS protocol alone — deletion is
/// framework-owned; there is nothing to apply.
public protocol WriteTargetProviding: Sendable {

    associatedtype Target: DataModel

    /// The write-verb requirement (`.write` / `.create` / `.delete`) naming
    /// what this request may touch, and from where.
    static var candidates: LoadRequirement<Target> { get }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  Protocols/DataModelWriter.swift   (NEW — 4A)
// ═══════════════════════════════════════════════════════════════════════

/// The write half of an update/create request: applies the submitted,
/// validated body onto the target `DataModel`. The mirror of `ResponseBody`
/// adopting ``VaporResponseBodyFactory`` — and its exact symmetric twin:
/// projection is synchronous and cannot load; **apply is synchronous and
/// cannot touch the database** (D-C8-9). The framework owns ALL I/O:
/// loading, saving, FK wiring, deletion, the refresh.
///
/// ```swift
/// extension UpdateBerthRequest.RequestBody: DataModelWriter {
///     static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)
///
///     func apply(to berth: Berth) throws {
///         berth.name = name
///         berth.capacity = capacity
///     }
/// }
/// ```
///
/// The framework brackets `apply` (D-C8-3) — by the time it runs, the body
/// validated (structurally: `apply` is unreachable otherwise), the candidate
/// set loaded, and the target resolved from the Query — never from the body.
/// After it returns: save + commit, cache invalidation (records, never
/// grants), then the refresh request re-serves through the genuine GET
/// pipeline (D-C8-7).
///
/// Create uses the SAME method: the framework instantiates a fresh
/// `Target()` (Fluent's required empty init), calls `apply`, sets the
/// container FK from the candidate scope, saves. One authored method covers
/// update AND create. Field application only — cross-record side effects
/// are supplemental-load / future-verb territory.
public protocol DataModelWriter: WriteTargetProviding {

    func apply(to target: Target) throws
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  Containment/SupplementalRecordLoading.swift
// MARK:   (C7's internal seam — PUBLIC in C8, name unchanged, 7½)
// ═══════════════════════════════════════════════════════════════════════

/// The load-phase escape hatch: data a factory cannot declare as
/// containment tuples loads here, AFTER the declarative plan executed
/// (declared records are already readable). Full request power lives here
/// — this is load phase, not projection.
///
/// A thrown error FAILS THE REQUEST — never swallowed to an empty result
/// (the same no-silent-guess discipline as the declarative path).
public protocol SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  Application registration surface
// MARK:   (Application-only — grouped/Routes registration is structurally
// MARK:   gone, retiring the C7 grouped-path caveat)
// ═══════════════════════════════════════════════════════════════════════

public extension Vapor.Application {

    /// Registers a read request's route (GET). One door for every request,
    /// ViewModel-bodied or not (7A — `register(viewModel:)` is gone).
    ///
    /// ```swift
    /// try app.register(request: DockPageRequest.self)
    /// ```
    ///
    /// Register containers (`app.register(_:migration:)`) first — a
    /// composable body's load plan is derived and validated here.
    ///
    /// BOOT-FAILS on any write-CRUD conformer: Swift overload resolution
    /// sends a write request that misses the write door's constraints HERE
    /// (it still satisfies this door's), and registering it GET-only would
    /// be the silent mode. The error names the unmet constraints.
    func register<SR: ServerRequest>(request: SR.Type) throws
        where SR.ResponseBody: VaporResponseBodyFactory,
        SR.ResponseBody.Request == SR {
        fatalError("sketch")
    }

    /// Registers an update request's routes (PATCH + the refresh's GET).
    /// Compile-time: the Query names its target; the body writes.
    /// Boot-time: candidate tuple derived; refresh plan derived; AppState
    /// builder present when the refresh body declares a non-Void AppState.
    ///
    /// `CreateRequest` (POST) and `DeleteRequest` (DELETE, `RequestBody:
    /// WriteTargetProviding` only) get sibling overloads. `ReplaceRequest`
    /// (PUT) and destroy are DEFERRED (Defer-API): registering one fails
    /// fast at boot — "write protocol not yet supported" — never a silent
    /// read-only registration.
    func register<SR: UpdateRequest>(request: SR.Type) throws
        where SR.RequestBody: DataModelWriter,
        SR.Query: TargetedQuery,
        SR.RefreshRequest.ResponseBody: VaporResponseBodyFactory,
        SR.RefreshRequest.ResponseBody.Request == SR.RefreshRequest {
        fatalError("sketch")
    }

    /// Registers the builder for a factory's `AppState` — the one
    /// sanctioned place session-derived context is computed, with full
    /// request power (load phase). Keyed by the AppState TYPE; registering
    /// the same type twice is a boot error (silent last-wins is a guess).
    ///
    /// ```swift
    /// app.useAppState(SessionBanner.self) { req in
    ///     SessionBanner(userName: try req.auth.require(User.self).displayName)
    /// }
    /// ```
    func useAppState<AppState: Sendable>(
        _ type: AppState.Type,
        builder: @escaping @Sendable (Vapor.Request) async throws -> AppState
    ) throws {
        fatalError("sketch")
    }

    /// PUBLICIZED unchanged (6A): resolves the `.apex` root's identity —
    /// the boot-registered "who is the top container for this caller?"
    ///
    /// ```swift
    /// app.useApexContainerResolver { req in
    ///     try await req.auth.require(User.self).harborIdentity
    /// }
    /// ```
    func useApexContainerResolver(
        _ resolver: @escaping @Sendable (Vapor.Request) async throws -> ModelIdentity
    ) {
        fatalError("sketch")
    }
}

// ═══════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════
// MARK: - USAGE — the Harbor app, all five shapes
// ═══════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────────────
// MARK: 1 · Zero-data screen — factory only, NO trait
// ───────────────────────────────────────────────────────────────────────

extension LandingPageViewModel: VaporResponseBodyFactory {
    static func body(context: ProjectionContext<Request, Void>) throws -> Self {
        .init() // no records, no plan, no boot guard involved
    }
}

// ───────────────────────────────────────────────────────────────────────
// MARK: 2 · Read screen — trait + factory, child composition, appState
// ───────────────────────────────────────────────────────────────────────

extension DockPageViewModel: ComposableFactory {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
        .refinedByRequest // the request's Sort/Pagination land here

    static var dataRequirements: [any DataRequirement] { [berths] }
    static var children: [ComposedChild] {
        [.child(CrewListViewModel.self)] // pulls crew's requirements in
    }
}

extension DockPageViewModel: VaporResponseBodyFactory {
    static func body(context: ProjectionContext<Request, SessionBanner>) throws -> Self {
        .init(
            berthCells: try context.records(Self.berths)
                .map { BerthCellViewModel(berth: $0) },
            // Child composition is authored value construction from the
            // child's OWN loaded handle — there is no framework child-
            // projection API:
            crewList: CrewListViewModel(
                members: try context.records(CrewListViewModel.crew)),
            signedInAs: context.appState.userName // via useAppState
        )
    }
}

// ───────────────────────────────────────────────────────────────────────
// MARK: 3 · Update cycle — one screen, both halves + the refresh bridge
// ───────────────────────────────────────────────────────────────────────

// SHARED module — the request (its CRUD protocol picks the HTTP verb):

final class UpdateBerthRequest: UpdateRequest {
    final class Query: TargetedQuery, RootedQuery {
        let dock: ModelIdentity //   RootedQuery — the .query root
        let target: ModelIdentity // TargetedQuery — WHICH berth (opaque,
    } //                             echoed from the VM the client displayed)

    final class RequestBody: ServerRequestBody, ValidatableModel {
        var name: String //          NO ModelIdType — a submit cannot retarget
        var capacity: Int

        func validate(fields: [any FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
            fatalError("sketch")
        }
    }

    // D-C8-7 — the typed bridge: pass #2 re-serves THIS read request.
    typealias RefreshRequest = DockPageRequest
    typealias ResponseBody = DockPageRequest.ResponseBody // by constraint

    func refreshRequest() -> DockPageRequest {
        DockPageRequest(query: .init(dock: query.dock))
    }
}

// SERVER target — ONE conformance carries candidates + apply:

extension UpdateBerthRequest.RequestBody: DataModelWriter {
    static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)
    // the candidate set — loaded on PATCH only; a GET of the page never
    // loads it (D-C8-8). Target must be a member, or not-found.

    func apply(to berth: Berth) throws { // sync, no Database (D-C8-9)
        berth.name = name
        berth.capacity = capacity
    }
}

// The route the framework runs for PATCH (nothing below is authored):
//   validate() → load candidates (writer's tuple, auth-scoped) → resolve
//   Query.target against candidates → apply → save/commit →
//   invalidateContainerRecords → execute refreshRequest() through the
//   GENUINE GET pipeline (its plan, its refinement) → fresh page out

// ───────────────────────────────────────────────────────────────────────
// MARK: 4 · Delete — candidates only; nothing to apply
// ───────────────────────────────────────────────────────────────────────

final class DeleteBerthRequest: DeleteRequest {
    final class Query: TargetedQuery, RootedQuery {
        let dock: ModelIdentity
        let target: ModelIdentity
    }

    // Concrete, app-owned: conforming a SHARED empty-body type to
    // WriteTargetProviding would collide on the second delete request.
    final class RequestBody: ServerRequestBody {}

    typealias RefreshRequest = DockPageRequest
    typealias ResponseBody = DockPageRequest.ResponseBody

    func refreshRequest() -> DockPageRequest {
        DockPageRequest(query: .init(dock: query.dock))
    }
}

extension DeleteBerthRequest.RequestBody: WriteTargetProviding {
    static let candidates = LoadRequirement.delete(Berth.self, in: .parentRoot)
    // no apply — deletion is framework-owned
}

// ───────────────────────────────────────────────────────────────────────
// MARK: 5 · Non-VM body — a CLI's manifest, same machinery (D-C8-4)
// ───────────────────────────────────────────────────────────────────────

struct DockManifest: ServerRequestBody {
    let lines: [ManifestLine]
}

extension DockManifest: ComposableFactory {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] { [berths] }
}

extension DockManifest: VaporResponseBodyFactory {
    static func body(context: ProjectionContext<ManifestRequest, Void>) throws -> Self {
        .init(lines: try context.records(Self.berths).map(ManifestLine.init))
    }
}

// ───────────────────────────────────────────────────────────────────────
// MARK: 6 · Boot — everything registered in one place
// ───────────────────────────────────────────────────────────────────────

func routes(_ app: Application) throws {
    try app.register(Pier.self, migration: CreatePier()) // containers first
    try app.register(Dock.self, migration: CreateDock())

    app.useApexContainerResolver { req in //                 .apex roots
        try await req.auth.require(User.self).harborIdentity
    }
    try app.useAppState(SessionBanner.self) { req in //      projection appState
        SessionBanner(userName: try req.auth.require(User.self).displayName)
    }

    try app.register(request: LandingPageRequest.self) //    one door,
    try app.register(request: DockPageRequest.self) //       reads and
    try app.register(request: UpdateBerthRequest.self) //    writes alike
    try app.register(request: DeleteBerthRequest.self)
    try app.register(request: ManifestRequest.self)
}
