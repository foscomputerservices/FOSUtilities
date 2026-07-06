# Layer 1 · C7 — Composable Factories & Data-Requirements Aggregation (Design Spec)

**Status:** Reconciled — dual spec review (2 blockers, 6 majors: all folded) + cold-read A/B
naming test (surface B adopted). Pending David's written-spec review.
**Date:** 2026-07-04 (co-designed live with David; all decisions in-session)
**Layer:** 1, component **C7** of `2026-07-03-authorized-container-data-loading-architecture.md`.
**Targets:** FOSMVVM (vocabulary, trait, walk) + FOSMVVMVapor (binding, executor) +
one additive C6 engine parameter. **Companion:** `2026-07-04-c7-surface-sketch.swift`
(the Xcode-readable surface; normative for signatures).
**Depends on:** C1/C4/C6/C3 (shipped). **Blocks:** C8.

> **NOTE (2026-07-05):** `ComposableViewModelFactory` was renamed `ComposableFactory` and un-pinned
> from `ViewModelFactory` in C8 (any `ServerRequestBody` may adopt). This document is a point-in-time
> C7 record; it keeps the original name below. The shipped type is `ComposableFactory` — see
> `2026-07-05-vapor-response-body-factory-design.md` §3.4.

> **The problem C7 solves** — the arc's founding failure: knowledge of *what data a composable
> piece needs* lived with the piece; the *declaration of what to load* lived far away at the
> top-level request. Dropping a child in silently required editing a distant load list;
> forgetting was a **runtime crash at composition time**. C7 derives the load plan *from the
> composition*: co-located declarations, aggregated automatically, loaded once — and composing
> a child that does not declare its data (does not conform to the trait) **fails to compile**.

## Foundational principle (David)

**Only the ServerRequest can truly describe the shape of the data request — by definition.**
The request *type* fixes the shape (request → factory → composition graph → plan);
the request *instance* only parameterizes it (identities, sort, window).
Nothing GraphQL-ish crosses the wire; a hostile client can vary parameters,
never widen the projection.

Pipeline (stage 3 is this spec; stage 6's author surfaces are C8's):

```
0  INTENT      BerthsViewModelRequest (typed intent + parameters)
1  RECEIVE     same shared types re-materialize server-side
2  PROJECT     BerthsViewModel acting as its own factory (Context = hosting axis)
3  SHAPE       ★ declarations walked → RecordLoadPlan (boot, static)
4  GRANTS      ContainerAuthorization via the C3 provider (memoized)
5  LOAD        plan resolved + executed through the C6 engine → request cache
6  PROJECTION  factory composes children; reads cache only          [C8 surfaces]
7  RENDER      client decodes Body; vmId drives SwiftUI identity
```

## The vocabulary (cold-read-tested; signatures normative in the sketch)

| Concept | Name | Home |
|---|---|---|
| the opt-in trait | `ComposableViewModelFactory` | FOSMVVM public |
| the concept a factory lists | `DataRequirement` (protocol) | FOSMVVM public |
| the typed load a factory mints | `LoadRequirement<Record>` (struct) | FOSMVVM public |
| the authority verbs | `.read(…)` now; `.write/.create/.delete/.destroy` with C8 | factories |
| containment descent | `via:` — **intermediate hops only** (terminal type implicit) | factory param |
| a composed child | `ComposedChild` — `.child(T)` / `.child(T, via:)` / `.child(T, rootedAt:)` | FOSMVVM public |
| root placement / source | `RootScope` (`.parentRoot`/`.newRoot`) + `RootSource` (`.query`/`.apex`) | FOSMVVM public |
| Query vends the root | `RootedQuery` — `var rootIdentity: ModelIdentity` *(name provisional)* | FOSMVVM public |
| authority through a container | `AuthorityFlow` — `.inherits` (default) / `.guards` | FOSMVVM public |
| refinement target | `.refinedByRequest` | modifier |
| static plan / bound plan | `RecordLoadPlan` (package) / `ResolvedRecordLoadPlan` (Vapor internal) | — |
| apex container | prose term + `RootSource.apex` | — |

Taxonomy: *a `LoadRequirement` is a `DataRequirement`* — the `Model → DataModel` layering.
`LoadRequirement` is literally true for every future verb: **every requirement loads;
the verb names the authority exercised (`ContainerOperation`), never the SQL**
(a `.delete` requirement loads the candidates a submitted target must belong to).

## Scope (what ships in C7)

**FOSMVVM:**

1. `ComposableViewModelFactory` — `dataRequirements: [any DataRequirement]` (default `[]`,
   meaningful: pure composer) + `children: [ComposedChild]` (default `[]`, meaningful: leaf).
   All-empty conformance = boot fail-fast. `children` factories accept only trait-conforming
   types ⇒ **a child that does not conform (does not declare its data) cannot be listed —
   compile error.** *Honest scope:* a conforming child *omitted* from `children` is not
   compile-caught; closure of that gap is a **named C8 obligation** (the composition/read
   surface) and the macro's eventual job. Same for a declared handle omitted from
   `dataRequirements` (boot-invisible — statics can't be reflected): **C8's read surface
   must fail fast on a plan-absent handle** (obligation recorded below).
2. `DataRequirement` (protocol) + `LoadRequirement<Record>` with the `.read` factory
   (`in:` root, `via:` intermediates — variadic `any Model.Type`, terminal hop implicit)
   and `.refinedByRequest`. **Axes-by-request-type:** the marker only picks the target;
   the axes are the request type's own declarations (`Sort` associatedtype;
   `PaginatedQuery` conformance; future axes arrive as new Query traits — explicit
   opt-in, nothing widens silently). At most one marked requirement per plan.
3. `ComposedChild` (three `.child` factories; parent-scope default). Stores
   `any ComposableViewModelFactory.Type` — existential metatype, the shipped
   `containedRecordTypes` precedent: boot-walked list, no hot-path dispatch.
4. `RootScope` / `RootSource` / `RootedQuery` / `AuthorityFlow`
   (Requirement + Default on `Container`; default `.inherits`; directionality per David:
   *a guards b* — declared on the actor).
5. `RecordLoadPlan` + the walk — **`package`** (definitive statement: consumed by
   FOSMVVMVapor's executor, a different target of this package; no app-facing need;
   `internal` cannot cross modules; `package` is the only level that serves).
   The walk (boot, pure): recurse children, substitute mappings (child-relative →
   absolute), collect tuples, **dedup same-anchor duplicates only**, reject cycles,
   annotate each tuple's authorizing anchor (nearest `.guards` ancestor, else its root),
   compute M2 collapse boundaries. Hop resolution: each step names the *next* Model type;
   v1 semantics for a container with several same-type relations = they concatenate
   (exactly the shipped C6 engine behavior); a choose-one discriminator is additive later.

**FOSMVVMVapor:**

6. **Plan derivation + boot validation at route registration** (the
   `VaporServerRequestHost` path); plans stored in `Application` storage.
   Boot checks (fail-fast unless noted): cycles · same-anchor diamond dedup ·
   every hop resolves to a registered `ContainmentRelation` (C4 invariant-(a),
   generalized) · `.query` roots require the root factory's `Request.Query: RootedQuery`
   (boot-checked — heterogeneous `children` preclude compile enforcement) ·
   `.apex` roots require a registered resolver · at most one `.refinedByRequest` ·
   dead `.refinedByRequest` (request type declares no axes) — **warn** ·
   all-empty conformer · `.guards` type on no declared path — **warn**.
7. **The executor** (internal): `RecordLoadPlan` → `ResolvedRecordLoadPlan`
   (root identities + the instance refinement on the marked tuple + grants) →
   levels breadth-concurrent via `TaskGroup`, **deposits single-writer sequential**
   (the shipped cache's documented contract; test-pinned) — depth sequences only on
   data dependency; intermediate hops land in the cache too. Every call through the
   provider-driven `authorizedRecords`. Unauthorized/missing ⇒ empty subtree, never an error.

   > **RECONCILIATION NOTE (dated 2026-07-04, Task 6 review).** v1 executes ALL tuples
   > SEQUENTIALLY, not breadth-concurrent — verified in code, not merely reconsidered: the
   > C6 engine writes the container-record cache *inside* `authorizedRecords`, and the
   > cache's `@unchecked Sendable` contract (`ContainerRecordCache.swift`) holds only under
   > sequential access within the request's handler task, so an executor-level `TaskGroup`
   > across siblings would race that cache's read-modify-write. Breadth concurrency's real
   > precondition is either a concurrent-writer cache contract or a query/deposit split
   > (query concurrently, deposit sequentially) — neither exists yet, and the M2 collapse
   > optimization (one query per collapsed run) changes this calculus anyway, so breadth
   > concurrency is revisited alongside M2, not before it.
8. **Apex resolver** — boot-registered; `(Request) async throws -> ModelIdentity`
   (constant apps return a constant; multi-tenant apps resolve per request).
9. **C6 engine, additive:** `authorizedAs anchor: ModelIdentity? = nil`
   (nil ⇒ the load container) on the package entries, **and the cache key gains the
   anchor** (normalized nil → load container). Stated explicitly: the anchor is an
   engine parameter, NOT a refinement field — the refinement's "additive fields join
   the key automatically" posture does not cover it. *"From where?" bears on
   authorization exactly through the anchor* (David): same-anchor paths are the same
   security question (dedup-safe); different anchors must never merge nor share a
   cache entry.
10. **Supplemental loads: moved to C8** (its declaring protocol is
    `ServerHostedViewModelFactory`'s business; C7 keeps the internal executor seam +
    coverage test). C8 obligations recorded: the hook's public surface; throwing hook
    ⇒ propagate (fail the request — never swallow-to-empty); the plan-absent-handle
    fail-fast; the conforming-but-unlisted-child closure.

## Non-goals (each with its landing zone)

- **M2 eager-load execution** — deferred; landing zone proven (David: *"here's where you
  figure out what `.with {}` clauses to add"*): the plan's paths derive the eager clauses;
  anchors compute collapse legality (same-anchor+op runs collapse; `.guards` = boundaries);
  lands as a pure executor optimization via the refinement's additive-field seam +
  a `.with`-applying capability on `ContainmentRelation`. Zero API movement.
- **The generating macro** — declared values now; the macro later closes both
  residual listing gaps.
- **Verbs beyond `.read`** — arrive with C8's write path (Defer API).
- **C8 surfaces** — narrowed projection context (no `Vapor.Request`, no `Database`),
  typed read subscript, `ProjectionState` + `projectionState(from:)`,
  `ServerHostedViewModelFactory`, pass #2, form binding.
- **Client-hosted conformance** — named future seam (prefetch, offline, client L2, stubs);
  today's obligation already met: zero server types in the vocabulary.
- **L2** — dividend banked: the plan is the per-request-type dependency map;
  supplemental-load factories statically known.

## Customer DocC (drafted first; full set in the sketch/plan)

```swift
/// Declares the data a composable factory projects — co-located with the
/// factory, aggregated automatically, loaded once per request.
///
/// ```swift
/// extension BerthsViewModel: ComposableViewModelFactory {
///     static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
///         .refinedByRequest
///     static let crew   = LoadRequirement.read(CrewMember.self, in: .parentRoot)
///
///     static var dataRequirements: [any DataRequirement] { [berths, crew] }
///     static var children: [ComposedChild] {
///         [.child(BerthCellViewModel.self),
///          .child(HarborBannerViewModel.self, rootedAt: .apex)]
///     }
/// }
/// ```
///
/// A child that does not declare its data — does not conform to
/// ``ComposableViewModelFactory`` — cannot be composed: it fails to compile.
/// Declarations are aggregated automatically at boot and loaded once,
/// before projection begins.
public protocol ComposableViewModelFactory: ViewModelFactory { … }
```

```swift
/// Whether authority granted on an ancestor flows through this container
/// to its contained records, or stops here.
///
/// The default — `.inherits` — means one grant at the apex (or any ancestor)
/// covers the descent; nothing to declare. Declare `.guards` on a container
/// whose records need authority anchored at *it*:
///
/// ```swift
/// extension PersonnelFolder {
///     static var authorityFlow: AuthorityFlow { .guards }
/// }
/// ```
///
/// Reads from the declaration site: *"PersonnelFolder guards; everything else inherits."*
public enum AuthorityFlow { case inherits, guards }
```

## Testing

**Shared — FOSMVVMTests, no database** (contract: declared via the public trait,
asserted at the plan's `package` surface — which *is* the contract its consumer,
the executor, binds):
1. walk substitution (all three placements; `via` intermediates; terminal implicit)
2. same-anchor diamond dedup — and the **anchor-conflict diamond: two tuples,
   never merged**
3. cycle rejection (typed error names the cycle)
4. anchor resolution (`.guards` mid-path re-anchors its subtree)
5. `.refinedByRequest` uniqueness + dead-marker detection; plan determinism
6. collapse-boundary computation (M2 legality map — data only)

**Vapor — FOSMVVMVaporTests, SQLite harness** (fixtures gain the `Harbor` apex,
a three-level path, a `.guards` container):
7. boot checks — each throws/warns per Scope §6
8. end-to-end: request type → plan → resolved → engine → cache; dock-rooted +
   apex-rooted trees in one request (the forest)
9. authority: apex grant descends three levels under `.inherits`; `.guards` mid-path
   denies without an anchored grant, loads with one; **anchor-conflicting diamond:
   two cache entries, independent outcomes**
10. `.refinedByRequest`: instance sort/window on exactly that tuple
11. supplemental seam (coverage, internal): runs post-declarative, reads cached
    tuples, deposits authorized; throwing hook fails the request
12. `authorizedAs` + anchored cache key: additive tests; existing suites untouched-green
13. concurrency (RECONCILED — see the Scope §7 note: v1 runs sequentially, not
    breadth-`TaskGroup`): the pin is sibling-deposit COMPLETENESS + DETERMINISM — a level
    with N siblings all cached, no lost writes, same result on repeat — not a race test

## Constraint ledger

- **Every scope is rooted** (David): "all docks" = docks *of the apex*; permissions to
  landing-page-style data are ordinary grants on the apex. No second grant kind, ever.
- **The no-DB-in-projection rule's true history** (David): a pre-async/await mechanism
  whose valuable offspring (rooted permission + caching) we keep and whose fragility
  C7 kills. The hard invariant was never "no DB": it is **every read goes through the
  authorized entry**. async/await re-admits one-off pulls as *declared, load-phase*
  overrides (C8's hook), never projection-time ambient access.
- **The cold-read test is the decisive naming instrument** (David): both surfaces were
  A/B-tested on context-free readers; surface B won (`.refinedByRequest` inferred
  nearly exactly; `[berths, crew]` frictionless; `.child` default self-explanatory).
  The test also caught a real grammar bug: `via` listing the terminal type read as
  self-referential to both readers → **via = intermediates only**. Accepted trade:
  the authority axis is invisible while `.read` is the only verb; it becomes
  self-evident when C8's verbs land beside it.
- **STANDING WAGER — `LoadRequirement`** (2026-07-04): accepted on cold-read evidence
  over David's reservation that it lacks meaning sans context. David holds the
  told-you-so; if year-three proves him right, rename with the full workshop.
- **`Fragment` rejected** — shipped API (`ServerRequest.Fragment`). **`*Binding` rejected** —
  SwiftUI owns the word. **`Authority`, not `Authorization`** — OAuth owns "authorization
  flow". **`.guards` over `.guarded`** — directionality: the declaration sits on the actor.
  **`RecordRequirement` rejected** — signature stutter. **apex, not root/top** — "root"
  belongs to per-request roots. **`Action` rejected for the requirement** — it is the
  wire tier's word (`ServerRequestAction`); the requirement's verb is the authority tier's.
- **`.via(\Dock.$crew)` (Fluent KeyPath) can never appear on a shared surface** —
  the DoD grep now hunts `$`-projections in FOSMVVM sources *and comments*.

## Decisions (all with David, live, 2026-07-04)

D-C7-1  request type describes the shape; instance parameterizes
D-C7-2  fragments live on factories, aggregated from the request's factory
D-C7-3  vocabulary is FOSMVVM's; Vapor is one implementation
D-C7-4  declared static values now; macro later
D-C7-5  authority `.inherits` default / `.guards` opt-in (Requirement + Default)
D-C7-6  every scope rooted; apex pattern; no second grant kind
D-C7-7  trait layered under C8's ServerHostedViewModelFactory ("keep layering")
D-C7-8  escape = static override in the load phase; no async down projection
D-C7-9  M2 deferred with the `.with {}` landing zone
D-C7-10 `RecordLoadPlan`/`ResolvedRecordLoadPlan` ("Plan" alone too generic)
D-C7-11 C7 spec first, C8 after
D-C7-12 `ProjectionState` shape settled; C8 owns it
D-C7-13 verb factories; `.read` alone ships (verbs = authority axis, arrive with C8)
D-C7-14 refinement axes live on the request type; `.refinedByRequest` targets only
D-C7-15 `[any DataRequirement]` + `LoadRequirement<Record>` (wager recorded)
D-C7-16 the anchor joins tuple identity AND the C6 cache key ("from where?" bears)
D-C7-17 supplemental hook moves to C8; C7 keeps the internal seam

## Definition of done

- Test groups 1–13 green; full suite green; swiftformat/swiftlint clean.
- DocC with examples on every public symbol; no `package` symbol named on any public
  surface; `RecordLoadPlan` carries its definitive `package` statement in a `//` note.
- Zero other `package` additions (grep); no Fluent/Vapor types — **including
  `$`-projection KeyPaths in code or comments** — in FOSMVVM (grep).
- The walk pure (no I/O imports in its file); plans derived + validated at route
  registration; executor deposits single-writer.
- Arch doc §C7: TBD → SPECIFIED; M1 = placement grammar, M2 = deferred w/ landing zone,
  M3 = declared values + trait. C8 obligations appended to the arch's C8 section
  (hook surface + throw posture; plan-absent-handle fail-fast; unlisted-child closure;
  `ProjectionState`).
- CHANGELOG: public vocabulary + the additive C6 parameter/key change.
