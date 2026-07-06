# C8a — Controller Composition Refactor: HANDOFF for a clean context

**Date:** 2026-07-05 · **Ruled by David:** option A — refactor within C8, before his branch read.
**Worktree:** `/Users/david/Repository/FOS/FOSUtilities-model-identity`
(branch `spec/model-identity-live-invalidation`, head `7af8470`, clean, NOT pushed).
Suite: **545 green** + 2 pre-existing CSV known issues (+1 pre-existing WASI lint; both predate the branch).

---

## The standard this work is held to (David, verbatim)

> "I said at the beginning of this work that we had to make a **simple, elegant and
> joy to use api**; you keep running through the world like a butcher in a butcher
> shop or Freddy Kruger."

This refactor exists because C8's execution violated composition/specialization:
it built a **parallel** routing scaffold beside a shipped **general** one and then
proposed disposing of the general one as "legacy." The fix is not mechanical
deduplication — it is putting the layers in their right relationship, and the
result must read as *designed*, not patched. Do a short design pass before coding;
no butchery.

## The design correction (the truth to implement)

- **`ServerRequestController` is the GENERAL dispatch layer** (shipped 0.3.0–0.4.0):
  a `ServerRequest` is served by processors keyed by `ServerRequestAction`;
  HTTP-method mapping, body-stream strategy (`RequestBody.maxBodySize`), and route
  grouping are derived **once**, in one place.
  Files: `Sources/FOSMVVMVapor/Protocols/Controller.swift`,
  `Protocols/ControllerRouting.swift`, `Vapor Support/UpdateController.swift`.
- **C8's guarded pipelines are SPECIALIZATIONS of that shape:**
  the read pipeline (`Request.serve(_:)` — executor → ProjectionContext → body →
  buildResponse) and the write pipelines (`serveUpdate`/`serveCreate`/`serveDelete`
  in `Containment/WriteRoute.swift` — decode → validate → candidates → gate/resolve
  → apply → save → invalidate → serve(refresh)).
- **Target shape:** the framework supplies those pipelines as **processors** on the
  general mechanism; `register(request:)` (and the three write overloads) become
  **sugar that instantiates the controller pre-specialized** with the guarded
  processors. An app with a non-CRUD/multi-record operation supplies its own
  processor through the same general mechanism — that is the base layer working,
  not an escape.
- **Guards live in the processors,** never in which door was walked through.
- **The routing scaffold exists once.** The duplication to delete:
  `Vapor Support/ViewModelRequest.swift:86–140` (write overloads' inline
  `.on(.PATCH/.POST/.DELETE, body:)` groups) and the GET registration in
  `Vapor Support/VaporServerRequestHost.swift` re-implement what
  `UpdateController.swift:48–63` already generalizes.

## Known design tension to reconcile (the real work — think first)

The general layer and the C8 pipelines currently **bind the request differently**:

- The controller's `runServerRequest` hand-constructs
  `TRequest(query: nil, fragment: nil, requestBody: …, responseBody: nil)` —
  it predates C8 and never parses the query/sort.
- The C8 routes bind through `VaporServerRequestMiddleware` (the single parse
  point since T4: query **and** sort onto the typed instance) and pass the typed
  instance down (`serve(_ vmRequest:)`, instance-taking since the T4 fix cycle).

The reconciled general layer must use the **C8 binding** (middleware / typed
instance) — the controller's nil-query construction is part of what specialization
should improve *for every processor*, hand-written ones included. Reconcile the
`ActionProcessor` signature with the instance-taking pipelines; if the public shape
of `ServerRequestController` must change to get there (it shipped in 0.3.0–0.4.0;
pre-1.0 breaking is the branch's posture and `VaporViewModelFactory` got removed on
the same basis) — **any public-surface change to the controller family is a
David-gated design point: show him the before/after shape (verbatim declarations,
path:line) BEFORE implementing it.** He arbitrates all names and public shapes.

## Hard constraints

- **Public surface otherwise unchanged:** `register(request:)` + the three write
  overloads (signatures, `where` clauses, boot-check behavior), the writer
  protocols, `VaporResponseBodyFactory`, `ProjectionContext` — all identical.
  This is plumbing-beneath, made compositional.
- **Behavior pinned by the suite:** all 545 tests stay green UNMODIFIED except
  where a test names the plumbing itself (there should be almost none — the C8
  tests assert through public routes). A test that must change is a signal to
  re-check the design, not to edit the test.
- Boot-check battery unchanged (write-at-read-door reject, verb–door coherence,
  token lint, AppState checks, apex/root validation, Replace/Destroy
  "not yet supported" — though NOTE: the general layer registering PUT for a
  hand-written replace processor is legitimate; only the *guarded* doors defer
  Replace. Get this boundary right and state it in DocC.)
- Disciplines: zero `package` in FOSMVVMVapor; nothing widened for tests; DocC
  customer-framed with call-site examples; no "pass #2"/decision-ID vocabulary in
  DocC; sequential cache contract holds through every processor.
- swiftformat/swiftlint before each commit; trailers:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` +
  `Claude-Session: https://claude.ai/code/session_01FKA9Q3Fcoumn9HbrfLKcMo`

## Docs this refactor must reconcile (same commit(s))

- **Arch doc** (`docs/superpowers/specs/2026-07-03-authorized-container-data-loading-architecture.md`):
  REWRITE the §C8 forward note that calls the controller family a
  "second write door … disposition pending David" — the recorded truth becomes:
  the controller family is the **general dispatch layer**; C8's doors are
  framework-specialized controllers; hand-written processors are the sanctioned
  home for operations the guarded verbs don't cover yet (Replace/destroy/
  multi-record), shrinking as future slices add guarded verbs.
- **C8 spec** (`2026-07-05-vapor-response-body-factory-design.md`): §11 gains an
  implementation-time amendment recording the composition correction (pattern:
  the existing "Implementation-time amendments" block).
- **C8 plan** (`2026-07-05-l1-c8-vapor-response-body-factory.md`): one line in
  "Execution deviations (recorded)".
- `ServerRequestController`/`UpdateController` DocC: refresh to the composition
  framing (general layer; prefer `register(request:)` sugar where the shape fits;
  guards live in processors). CHANGELOG entry for whatever shape change lands.

## Process (per the standing session disciplines)

1. Short design pass FIRST: the reconciled `ActionProcessor`/binding shape +
   naming; **surface anything public-facing to David before coding** (verbatim
   before/after, path:line, vertical layout — his reading ergonomics).
2. TDD; subagent-driven if the context prefers, with **Opus implementers and an
   escalated (Fable) review of the reconciliation design** — the model-economy
   directive stands ([[model-credit-economy]]); escalated reviews caught 3
   Criticals in C8 (T4 blending/auth-leak; T6 create-gate bypass).
3. Dual review per task (spec-compliance, then quality), fix-until-approved.
4. Suite green at every commit.

## After this refactor (unchanged pipeline, all David-gated)

1. David reads the branch (spec open on his desk already).
2. Open David items: M-3 DoD letter-vs-spirit (3 Fluent-naming `//` comments in
   FOSMVVM); CHANGELOG framing already accepted.
3. Squash to logical commits (he approves the shape) → push → PR **only on his
   explicit go** ([[pr-requires-review-gate]], [[squash-before-pr]]).
4. POST-MERGE obligation: `fosutilities-api-catalog-update` + plugin bump (the
   catalog moved on main after this branch's merge-base; cannot be done on-branch).

## Orientation shortcuts for the fresh context

- Handoff memory: [[model-identity-specs-handoff]] (READ-FIRST header).
- The feedback that caused this refactor: [[compose-onto-general-never-butcher]].
- C8's shipped shape end-to-end: read the spec + `2026-07-05-c8-surface-sketch.swift`,
  then `WriteRoute.swift`, `VaporServerRequestHost.swift`, `ViewModelRequest.swift`,
  `UpdateController.swift` — in that order, before forming the design.
