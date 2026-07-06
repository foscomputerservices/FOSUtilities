# L1 C7 — Composable Factories & Data-Requirements Implementation Plan

> **NOTE (2026-07-05):** `ComposableViewModelFactory` was renamed `ComposableFactory` and un-pinned
> from `ViewModelFactory` in C8 (any `ServerRequestBody` may adopt). This is a point-in-time C7 plan;
> it keeps the original name throughout. The shipped type is `ComposableFactory` — see
> `2026-07-05-vapor-response-body-factory-design.md` §3.4.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved C7 spec — the `ComposableViewModelFactory` vocabulary, the pure walk producing `RecordLoadPlan`, the anchored C6 engine change, boot derivation/validation, and the Vapor executor.

**Architecture:** Vocabulary + walk live in FOSMVVM (walk is a pure function; `RecordLoadPlan` is the single `package` addition, statement required); FOSMVVMVapor binds hops to `ContainmentRelation`s at route registration (boot fail-fast) and executes resolved plans breadth-concurrent/single-writer through the provider-driven authorized engine. Anchor joins tuple identity and the C6 cache key.

**Tech Stack:** Swift 6, Vapor 4, shipped C1/C3/C4/C6, Swift Testing + `withFluentTestApp`.

**NORMATIVE SOURCES — read BOTH before any task:**
- Spec: `docs/superpowers/specs/2026-07-04-composable-factory-data-requirements-design.md`
- Sketch (signatures): `docs/superpowers/specs/2026-07-04-c7-surface-sketch.swift`
WORKTREE: all work in `/Users/david/Repository/FOS/FOSUtilities-model-identity`.

---

## Plan prose — wiring knowledge & gotchas

- **Access levels:** everything public per the sketch EXCEPT `RecordLoadPlan` + walk (`package`,
  with the definitive `//` statement from spec Scope §5) and the whole executor (internal).
  ZERO other package. `.guards` case: legal Swift (only `guard` is reserved), never bare.
- **`via:` variadic + trailing modifier:** `read(_:in:via:)` — variadic must be last param, so
  spelling is `read(_ record:, in root:, via intermediates: any Model.Type...)`; `via` empty =
  one implicit hop to `Record`. `.refinedByRequest` returns a copy with the flag set.
- **The walk's inputs are protocol statics reached through existential metatypes**
  (`any ComposableViewModelFactory.Type`) — plain existential-metatype static access; neither
  member returns Self, so no opening machinery is needed (it just compiles). Tuple identity for dedup: (root binding, absolute path, record type,
  operation, **anchor**) — synthesize `Hashable` on a package tuple struct.
- **Anchor computation needs `authorityFlow`** of each path step's *container* type:
  walk from the tuple's root down its absolute path; the LAST `.guards` container passed
  (including the root's own type? NO — the root container's own flow is irrelevant to records
  *it* anchors; guards apply to containers *traversed below* the root) re-anchors. The anchor
  is a *type-position* at walk time; it binds to an identity at resolve time (the identity of
  the guard-typed record on the loaded path — note: depth-sequencing already exists for
  ANY containment hop (child queries need parent ids); the anchor changes only WHICH identity
  is passed as `authorizedAs:` at each level — it binds to the guard-typed record's identity
  once that level has loaded. Spec test 9 pins this).
- **C6 key change:** `ContainerRecordCacheKey` gains `anchor: ModelIdentity` (normalized:
  callers passing nil store the load container). This CHANGES the shipped cache-key type —
  in-package only (no public surface), all existing tests must stay green with the default.
- **Boot derivation trigger:** `VaporServerRequestHost<Request>` registration
  (`Sources/FOSMVVMVapor/.../VaporServerRequestHost*.swift` — find the existing registration
  path; plans stored via private `StorageKey` in `Application` storage, keyed by request path
  or `ObjectIdentifier(Request.self)`). If `Request.ResponseBody` doesn't conform to the trait,
  no plan (nil) — legacy requests unaffected.
- **`.query` root boot check:** `Request.Query.self is any RootedQuery.Type`-style check at
  registration; executor decodes via shipped `serverRequestQuery(ofType:)` then reads
  `rootIdentity` through the opened existential.
- **Fixtures ripple:** harbor gains `Harbor` (apex, Container, containedRecordTypes [Dock]),
  `Dock` gains parent `harbor`? NO — keep FK graph as-is; apex containment resolves through a
  NEW `Harbor` container with `@Children` to Dock: requires Dock gaining `@OptionalParent`?
  Simplest: `Harbor` table + `harbor_id` on Dock (required, seeded). Update `CreateDock`,
  `seedHarbor`, and expect ripple in ModelTypeRegistry/engine tests' configure blocks
  (CreateHarbor before CreateDock). A `.guards` container: add `SlipAssignment`
  (child of Berth, `authorityFlow = .guards` on Berth? NO — the GUARD is the container type
  that guards: set `Berth.authorityFlow = .guards` in fixtures? Berth is used everywhere —
  instead add `PersonnelFolder` guard-container under Dock with `PersonnelFile` children,
  isolated from existing suites).
- **swiftformat/lint conventions:** as established (docComments ///, redundantSendable
  disabled, no trailing prose on directives).
- **Do NOT build:** verbs beyond `.read`, the macro, C8 surfaces (context, ProjectionState,
  ServerHostedViewModelFactory, public supplemental hook), eager-load execution, discriminators.

## File structure

| File | Responsibility |
|---|---|
| `Sources/FOSMVVM/Protocols/AuthorityFlow.swift` (create) | enum + `Container` gains requirement+default (modify `Container.swift`) |
| `Sources/FOSMVVM/Protocols/RootScope.swift` (create) | `RootScope`, `RootSource` |
| `Sources/FOSMVVM/Protocols/RootedQuery.swift` (create) | the Query trait |
| `Sources/FOSMVVM/Protocols/DataRequirement.swift` (create) | protocol + `LoadRequirement<Record>` + `.read` + `.refinedByRequest` |
| `Sources/FOSMVVM/Protocols/ComposedChild.swift` (create) | struct + three `.child` factories |
| `Sources/FOSMVVM/Protocols/ComposableViewModelFactory.swift` (create) | the trait + defaults |
| `Sources/FOSMVVM/RecordLoadPlan.swift` (create) | `package` plan + walk (pure; no I/O imports) |
| `Sources/FOSMVVMVapor/Containment/ContainerRecordCache.swift` (modify) | key gains anchor |
| `Sources/FOSMVVMVapor/Extensions/Request+ContainerLoad.swift` (modify) | `authorizedAs` param threading |
| `Sources/FOSMVVMVapor/Containment/PlanRegistration.swift` (create) | boot derivation + validation + storage + apex resolver registration |
| `Sources/FOSMVVMVapor/Containment/PlanExecutor.swift` (create) | resolve + execute (internal; supplemental internal seam) |
| `Tests/FOSMVVMTests/Composition/*` (create) | shared tests 1–6 (+ vocabulary contract tests) |
| `Tests/FOSMVVMVaporTests/Composition/*` (create) | Vapor tests 7–13 |
| fixtures (modify/extend) | Harbor apex, PersonnelFolder guard, three-level path |

---

### Task 1: Shared vocabulary — AuthorityFlow, RootScope, RootSource, RootedQuery

TDD. Tests (`Tests/FOSMVVMTests/Composition/AuthorityFlowTests.swift`): `Container` default is
`.inherits` (fixture container with no declaration); an override to `.guards` reads back;
`RootedQuery` conformance vends `rootIdentity` (fixture query + minted identity). Implement per
sketch (DocC verbatim from sketch/spec incl. the directionality sentence). Full suite green
(count grows; report). Commit: `feat(FOSMVVM): add AuthorityFlow + root vocabulary (C7)`.

### Task 2: LoadRequirement + ComposedChild + the trait

TDD. Tests (`.../Composition/LoadRequirementTests.swift`): `.read` builds with implicit
terminal hop (`via` empty); `via:` stores intermediates in order; `.refinedByRequest` marks
(readable via package surface later — for now assert the modifier returns a distinct value:
equality/flag via its `DataRequirement` package face if needed, else defer flag assertion to
Task 3's plan tests and keep construction-only here); three `.child` factories construct;
trait defaults ([] + []) compile for a bare conformer. Implement per sketch: protocol
`DataRequirement` (package-facing members minimal — the walk's needs only), struct, factories,
trait. Commit: `feat(FOSMVVM): add ComposableViewModelFactory + LoadRequirement (C7)`.

### Task 3: RecordLoadPlan + the walk (the meat)

TDD — spec tests 1–6 in `Tests/FOSMVVMTests/Composition/RecordLoadPlanTests.swift`, package
access (contract at the plan's package surface — label per spec Testing note). Fixture factory
graph: plain structs conforming to the trait (no DB, no Vapor): parent with own requirements +
`.child` (parent-scope), a `via:` child, a `.newRoot(.apex)` child, a diamond (same child via
two parents — same anchor), an anchor-CONFLICT diamond (one path through a `.guards` container
type), a cycle pair (A composes B composes A) for rejection, and a two-marked-requirements case.
(Dead-marker detection is request-type-specific — Task 5's boot check, NOT the walk.) Walk implement per spec Scope §5 + prose (anchor = last `.guards` container
type traversed BELOW the root; tuple Hashable incl. anchor; collapse boundaries computed —
test asserts the boundary set as data). Typed errors for cycle/multi-marked: NEST them as `RecordLoadPlan.WalkError`
(package by nesting — the DoD's zero-other-package rule counts TOP-LEVEL symbols; Vapor's boot
check pattern-matches the nested cases cross-module). Determinism: two walks ⇒ equal plans. Commit:
`feat(FOSMVVM): add RecordLoadPlan walk — aggregation, anchors, fail-fasts (C7)`.

### Task 4: C6 engine — authorizedAs + anchored cache key

TDD — spec test 12 (`Tests/FOSMVVMVaporTests/Composition/AnchoredEngineTests.swift`):
grant on the ANCHOR identity (not the load container) authorizes the load when
`authorizedAs:` passed; without the param, existing behavior byte-identical (existing suites
untouched-green is the gate); two calls same (container,type,op,refinement) but different
anchors ⇒ two cache entries, independent results. Implement: thread
`anchor: ModelIdentity? = nil` through the package + internal + provider-driven entries;
grant filter + `authorizes(in:)` use `anchor ?? container`; `ContainerRecordCacheKey` gains
the normalized anchor. Commit: `feat(FOSMVVMVapor): anchored authorization — authorizedAs + keyed cache (C7/C6)`.

### Task 5: Boot derivation + validation + apex + fixtures

TDD — spec test 7. Fixtures first: `Harbor` (apex container; `harbor_id` on Dock — REQUIRED, so this ripples;
migrations + seed updates), `PersonnelFolder` (`.guards`) + `PersonnelFile` under Dock (isolated).
KNOWN EDIT SITES beyond the shared helpers (verified by the plan reviewer — fix all five, expect
compile errors until done): private `configureHarbor` in `AuthorizationProviderTests.swift` AND
`AuthorizedLoadEngineTests.swift` (each manually lists migrations — insert `CreateHarbor()` before
`CreateDock`); direct `Dock(name:pierId:)` constructions at `AuthorizedLoadEngineTests.swift:374`,
`:451`, and `RefinedMembersTests.swift:82` (gain the `harborId:` argument). ALL existing Vapor
suites must end green.
`PlanRegistration.swift`: derivation at `VaporServerRequestHost` registration (find the shipped
registration seam; plans in Application storage; nil for non-trait ResponseBody), boot checks
per spec Scope §6 (each check = typed throw or logged warn; one test each — hop-resolution
check reuses C4's registry), apex resolver registration API (internal registration function or
package — NO public until an app-facing need; tests register directly). Commit:
`feat(FOSMVVMVapor): derive + validate RecordLoadPlans at route registration (C7)`.

### Task 6: The executor

**OBLIGATIONS FROM TASK 5's REVIEW (cannot be skipped):**
1. A COMPOSABLE ResponseBody with a nil stored plan is a CONFIGURATION ERROR at first load
   (typed ContainmentError, never "legacy, skip") — grouped/`app.routes` registration skips boot
   derivation (RoutesBuilder cannot reach Application; see ViewModelRequest.swift seam comment).
   Optionally lazy-derive+validate instead of throwing (keeps grouped registration viable) — throw
   is the floor.
2. When binding a root identity, require its registered descriptor to declare containment of the
   tuple's first hop (one registry lookup) — turns the misrooted-query silent-empty mode into a
   typed error.

TDD — spec tests 8–11 + 13 (`.../Composition/PlanExecutorTests.swift`): end-to-end forest
(dock-rooted `.query` + apex-rooted in one request — mint Request with the RootedQuery-
conforming query in its URL, per shipped serverRequestQuery mechanics); three-level `.inherits`
descent under one apex grant; `.guards` denial/allow (anchored grant on a PersonnelFolder
instance — NOTE anchors below root bind level-by-level); `.refinedByRequest` sort/window on
exactly that tuple; supplemental internal seam (internal protocol, executor runs it post-
declarative; throwing hook fails the request); TaskGroup breadth + single-writer deposit (a
level with N siblings all cached — no lost writes; assert all N entries present). Implement
`PlanExecutor.swift` per spec Scope §7 (+ internal supplemental seam protocol). Commit:
`feat(FOSMVVMVapor): execute ResolvedRecordLoadPlans through the authorized engine (C7)`.

### Task 7: Docs sweep + CHANGELOG

Arch doc §C7: TBD → SPECIFIED (M1 placement grammar / M2 deferred+landing zone / M3 declared
values + trait), append the four C8 obligations to arch §C8. DoD greps: zero new package
beyond RecordLoadPlan (+ its `//` statement present); **no Fluent/Vapor types NOR
`$`-projection KeyPaths in Sources/FOSMVVM (code AND comments)**; walk file has no I/O imports.
`swiftformat . && swiftlint --quiet && swift test` — full green (report count). CHANGELOG:
public vocabulary + the C6 anchored-key change (contract wording). Commit:
`docs: C7 recorded — arch resolved, CHANGELOG, boundary greps`.

## Final verification (spec DoD)

- [x] Tests 1–13 mapped and green; full suite green; format/lint clean.
- [x] DocC + examples on every public symbol; no package symbol on public DocC surfaces.
- [x] Package surface = RecordLoadPlan (incl. nested WalkError) only — top-level symbol count;
      statement in place; boundary greps incl. $-projections.
- [x] Arch §C7 SPECIFIED + C8 obligations appended; CHANGELOG present.
