// C7 SURFACE SKETCH — rev 2, post cold-read A/B test. NOT compiled by any target.
//
// SUPERSEDED BY C8 (2026-07-05). This sketch shows the C7 surface at its shipping
// point; C8 renamed `ComposableViewModelFactory` -> `ComposableFactory` (un-pinned
// from ViewModels), sealed `DataRequirement` (public marker + internal walk face),
// packified `via:` (parameter packs, call sites identical), and added the write-
// family verbs (.write/.create/.delete). The normative C8 surface is
// `2026-07-05-c8-surface-sketch.swift`; the contract is
// `2026-07-05-vapor-response-body-factory-design.md`. Kept as a point-in-time record.
//
// Locked this session: verb factories (.read; siblings arrive with C8's write
// path), via = INTERMEDIATE hops only, .refinedByRequest, [any DataRequirement]
// + LoadRequirement<Record>, .child with parent-scope default, axes-by-request-
// type, anchor joins tuple identity + cache key, supplemental hook -> C8.
//
// STANDING WAGER: LoadRequirement accepted over David's reservation —
// he holds the told-you-so if year-three proves him right.

import Foundation

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/ComposableViewModelFactory.swift
// ═══════════════════════════════════════════════════════════════════════

/// Declares the data a composable factory projects — co-located with the
/// factory, aggregated automatically, loaded once per request.
public protocol ComposableViewModelFactory: ViewModelFactory {

    /// This factory's own data needs. Empty is meaningful: a pure composer.
    static var dataRequirements: [any DataRequirement] { get }   // default []

    /// The child factories this factory composes. Only trait-conforming
    /// types can appear — an undeclared child cannot be composed.
    static var children: [ComposedChild] { get }                 // default []

    // Adopting the trait and declaring nothing = boot fail-fast.
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/DataRequirement.swift
// ═══════════════════════════════════════════════════════════════════════

/// One declared data need of a composable factory — the concept.
/// `LoadRequirement` is its typed realization (Model → DataModel layering).
public protocol DataRequirement { /* package-facing walk surface */ }

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/LoadRequirement.swift
// ═══════════════════════════════════════════════════════════════════════

/// A typed load: records of one type, in one rooted scope, under one
/// authority. Every requirement LOADS — the verb names the authority
/// exercised (the CRUD-family `ContainerOperation`), never the SQL.
public struct LoadRequirement<Record: Model>: DataRequirement {

    /// Loads the records this scope's grants authorize reading.
    ///     .read(Berth.self, in: .parentRoot)        // one hop: implicit
    ///     .read(SlipAssignment.self, in: .parentRoot,
    ///           via: Berth.self)                    // via = INTERMEDIATE hops only
    public static func read(_ record: Record.Type,
                            in root: RootScope,
                            via intermediates: any Model.Type...)
        -> LoadRequirement<Record> { /* … */ }

    // .write / .create / .delete / .destroy arrive WITH C8's write path
    // (Defer API): e.g. .delete = "load the records I'm authorized to
    // delete" — the candidate set a submitted target must belong to.

    /// The one requirement the request's declared refinement axes land on
    /// (Sort associatedtype + PaginatedQuery conformance — axes live on
    /// the request TYPE; this only picks the target). At most one per plan.
    public var refinedByRequest: LoadRequirement<Record> { /* … */ }
}

/// Where a requirement or composed child roots. (Internal plumbing shape —
/// the public reading is the preposition at the call site.)
public enum RootScope {
    case parentRoot            // shares the declaring factory's scope
    case newRoot(RootSource)   // starts a fresh tree (the forest)
}

/// Where a fresh root's identity comes from.
public enum RootSource {
    case query   // the request's RootedQuery vends it
    case apex    // the app's apex container — server-resolved
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/RootedQuery.swift
// ═══════════════════════════════════════════════════════════════════════

/// A Query that names the container its request is rooted in.
/// (Trait-overlay idiom: PaginatedQuery.)
public protocol RootedQuery: ServerRequestQuery {
    var rootIdentity: ModelIdentity { get }    // provisional lean — David reviews
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/ComposedChild.swift
// ═══════════════════════════════════════════════════════════════════════

/// One composed child: the child factory's type + where it roots.
public struct ComposedChild {

    /// A child sharing the parent's scope — the overwhelmingly common case.
    public static func child(_ type: (some ComposableViewModelFactory).Type)
        -> ComposedChild { /* … */ }

    /// A child rooted by containment descent from the parent's scope.
    public static func child(_ type: (some ComposableViewModelFactory).Type,
                             via intermediates: any Model.Type...)
        -> ComposedChild { /* … */ }

    /// A child starting a fresh root (detail + apex list in one request).
    public static func child(_ type: (some ComposableViewModelFactory).Type,
                             rootedAt source: RootSource)
        -> ComposedChild { /* … */ }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  Protocols/AuthorityFlow.swift  (+ Container change)
// ═══════════════════════════════════════════════════════════════════════

/// Whether authority granted on an ancestor flows through this container
/// to its contained records, or stops here.
/// Directionality (David): a guards b; b is guarded by a — the
/// declaration sits on the actor: "Dock guards; Berth inherits."
public enum AuthorityFlow {
    case inherits
    case guards
}

public protocol Container /* : Model — existing, gains: */ {
    /// Requirement + Default. Default: .inherits.
    static var authorityFlow: AuthorityFlow { get }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVM  ·  RecordLoadPlan.swift   (package — not app-visible)
// ═══════════════════════════════════════════════════════════════════════

// package struct RecordLoadPlan
//   The walk's output, per request type: tuples of
//   (root, path, record type, operation, AUTHORIZING ANCHOR).
//   The anchor is part of tuple identity AND the cache key — a guarded
//   path and an unguarded path to the same container are two different
//   security questions ("from where?" bears, exactly through the anchor).
//   package: consumed by FOSMVVMVapor's executor — different target,
//   no app-facing need, internal can't cross modules.

// ═══════════════════════════════════════════════════════════════════════
// MARK: - FOSMVVMVapor  ·  (bindings — orientation)
// ═══════════════════════════════════════════════════════════════════════

// · Executor (internal): RecordLoadPlan -> ResolvedRecordLoadPlan
//   (identities + refinement on the .refinedByRequest tuple + grants);
//   breadth-concurrent levels via TaskGroup, single-writer deposits.
// · Plan derivation + boot validation at route registration; plans in
//   Application storage. Boot checks: cycles, diamonds (same-anchor only),
//   hop resolution vs ContainmentRelations, RootedQuery conformance for
//   .query roots, apex resolver registered, one .refinedByRequest max,
//   all-empty conformer, dead .refinedByRequest marker (request declares
//   no axes), .guards off-path (warn).
// · Apex resolver: (Request) async throws -> ModelIdentity, boot-registered.
// · C6 engine: + authorizedAs anchor: ModelIdentity? = nil (nil = load
//   container); cache key gains the anchor.
// · Supplemental loads: C8 (ServerHostedViewModelFactory owns the hook);
//   C7 keeps the internal executor seam.

// ═══════════════════════════════════════════════════════════════════════
// MARK: - The whole surface, used once  (the cold-read site, rev 2)
// ═══════════════════════════════════════════════════════════════════════

extension BerthsViewModel: ComposableViewModelFactory {

    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
        .refinedByRequest

    static let crew = LoadRequirement.read(CrewMember.self, in: .parentRoot)

    static let slips = LoadRequirement.read(SlipAssignment.self,
                                            in: .parentRoot,
                                            via: Berth.self)

    static var dataRequirements: [any DataRequirement] {
        [berths, crew, slips]
        // Residual gap until the macro: a declared handle forgotten here is
        // boot-invisible; C8's read surface fail-fasts on plan-absent handles.
    }

    static var children: [ComposedChild] {
        [.child(BerthCellViewModel.self),
         .child(HarborBannerViewModel.self, rootedAt: .apex)]
    }

    // The projection — the factory's existing job, unchanged by C7
    // (reads the request cache through C8's narrowed context; no Database):
    static func model(context: Context) async throws -> Self { /* … */ }
}
