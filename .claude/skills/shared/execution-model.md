# The Execution Model of f

**f(requirements, architecture, ui design) → Source Code** executes like
`make`: nobody follows a workflow — you compute a traversal. The rule set
below declares each artifact's inputs and projecting skill. Given any
work item: identify which *arguments* changed, compute the stale set from
the rules, sort it topologically, run the rules in order. The interpreter
schedules; the graph is truth.

## The rule set

```
Fields                ← requirements (editable data + validation rules)
                        [fosmvvm-fields-generator]
DataModel + Migration ← Fields + domain requirements
                        [fosmvvm-fluent-datamodel-generator]
ViewModel             ← ui design (shape: WHICH properties exist)
                        + requirements (operations)
                        [fosmvvm-viewmodel-generator]
FormViewModel         ← Fields (adopts)
                        [fosmvvm-viewmodel-generator]
Factory               ← ViewModel + DataModel (server-side DIP seam:
                        domain → VM adaptation; shape and projection
                        are one unit of meaning)
                        [fosmvvm-viewmodel-generator]
ServerRequest         ← ViewModel + requirements (which CRUD ops exist)
                        [fosmvvm-serverrequest-generator]
RequestBody           ← Fields (adopts)
                        [fosmvvm-serverrequest-generator]
ServerRequest         ← requirements (server data + operations as
  semantics             storage-unbound SHALL-statements, e.g. "SHALL
                        show users ordered by last name")
Server-based          ← ServerRequest semantics. The EXECUTION surface
  Operations            is under active development — no execution
                        edges are mapped here; the caveat in the
                        skills stands.
Localization YAML     ← keys/structure: ViewModel (projection).
                        VALUES are owner-authored truth, derived from
                        the ui design's COPY and sometimes the
                        requirements (a design's SAMPLE DATA never
                        becomes a value): carried over verbatim, never
                        regenerated; values with no authored truth yet
                        are emitted UNRATIFIED for the owner's red pen.
View                  ← ViewModel + ratified ui design
                        [fosmvvm-swiftui-view-generator |
                         fosmvvm-leaf-view-generator |
                         fosmvvm-react-view-generator]
App bootstrap         ← architecture (deployment URLs, localization)
                        [fosmvvm-swiftui-app-setup]  (once per app)
Invariant tests       ← framework invariants + artifact type shape
 (round-trip,           [fosmvvm-viewmodel-test-generator |
  versioning, locales,   fosmvvm-serverrequest-test-generator |
  typed req/response)    fosmvvm-ui-tests-generator]
Consistency tests     ← intermediate artifacts (do the adopters agree
 (Fields ↔ adopters)    with Fields?) — verifies build-tree COHERENCE.
                        Not a substitute for behavioral tests: Fields
                        is itself a projection, and tests derived from
                        it inherit its omissions.
Behavioral tests      ← f's ARGUMENTS ONLY: requirements + ratified
 (validation rules,     design (incl. ratified customer-DocC, which is
  operation semantics,  design-layer, authored before code) — NEVER
  ordering, etc.)       the implementation or any derived artifact.
                        Second independent projection of the same
                        arguments, authored in an ISOLATED context
                        that has not seen the code or its plan.
                        [fosmvvm-behavioral-test-generator]
stub() values         ← the reserved-fake vocabulary, and nothing
                        else: Flintstones names and data ("Fred
                        Flintstone", "Bedrock"), numbers at or near
                        ±42, dates around 1914. Stub data must be
                        SELF-MARKING — obviously fiction, implausible
                        as production data. Never plausible-real
                        placeholders ("Test User", 2020 — a plausible
                        year is the failure), never a design's sample
                        data, and never the answer to a requirements
                        gap: a stub value at a missing argument is
                        silent substitution wearing framework syntax —
                        halt and emit an UNRATIFIED candidate instead.
verify (always last)  ← all changed artifacts
                        [fosmvvm-review]
```

Edge *types* are architecture — stable, this page. Edge *instances* are
derived per project from type conformances (a `ViewModelView`'s VM, a
Fields protocol's adopters) — that derivation is evaluation, not
guidance-reading.

## The dual-channel rule

Tests projected from the implementation — written OR merely envisioned —
verify the projection against itself. Writing tests first, in the same
context that is about to write the code, is the same failure in a
different order: the tests target the implementation the author already
envisions, not the requirements. Order alone buys nothing; the
test-writer's CONTEXT is the entire mechanism — it must contain the
requirements and not the implementation, written or planned.

The visible cost is dropped requirements (code omits newest-first →
code-derived test asserts the unsorted order and stays green) — but
those fail loudly downstream when a user looks for the feature. The
worse, silent cost is **missed failure modes**: reverse-engineered
tests can only cover paths the code contains, and failure modes are
precisely the paths it doesn't. A violation the code doesn't handle
leaves no trace in the implementation for a test to be derived from
("text is required" → code checks non-empty → test asserts non-empty →
green; whitespace-only, oversized input, parent deleted mid-post,
double-send after timeout — the requirement's negative space — are
invisible to both channels). Such failures ship, pass every demo, and
surface in production where nothing ever looked missing.

So behavioral tests are a SECOND channel of f over the SAME arguments —
projecting from the requirement means enumerating the ways it can be
violated, not the ways the code happens to guard. Projected before and
independent of the code channel; agreement between channels is the
evidence; red-before-green means the second channel exists first.
Isolation is mechanical, not disciplinary: project the behavioral suite
in a subagent context that receives only f's arguments — requirements +
ratified design. Invariant tests are exempt — the invariant is
universal, so there is nothing to reverse-engineer.

**"Contract" is a role, not a parameter.** f's signature is unchanged —
requirements, architecture, ui design. "Contract" names those same
arguments as seen from the verification channel. There is no fourth
input; any test whose source is not one of the three arguments is on
the wrong channel.

**The closure (coverage as the channel comparator).** Independence
opens its own hole: was the contract channel projected *thoroughly*?
Close the loop by running the contract-derived suite and measuring
block coverage of the implementation. Every uncovered block is a
finding to CLASSIFY, never a prompt to write a test:

- **code implements unspecified behavior** → freelancing: delete it —
  OR the code needed functionality the contract never specified, which
  is a hole in the contract: a feedback loop to the contract author as
  an UNRATIFIED candidate, and possibly transitively upward to the
  requirements themselves;
- **the test projection under-spanned the arguments** → strengthen the
  suite from requirements + ratified design (never from the uncovered
  code).

Never derive the new test from the uncovered code itself — that
launders channel disagreement into green coverage while the contract
stays unverified.

**The contract language is prose.** Human-authored formal specification
does not pay at the application level. Ratified prose requirements are
the contract; prose is sufficient because the contract's interpreter is
a language model, with two compensators:

- ambiguity discovered during test projection ("required" — does
  whitespace satisfy it?) is a missing-argument halt → UNRATIFIED
  clarification candidate upward. Precision is paid lazily, exactly
  where behavior turns on it — never up front across the whole spec;
- closure catches soft readings mechanically: an under-spanning
  interpretation shows up as uncovered blocks regardless of the
  contract's language.

The formal slice the architecture already owns — the type system and
Fields validation rules — stays formal; prose carries application
semantics above that floor.

## Dispatch (change type → stale subtree)

- **New feature/screen** — plan first (`fosmvvm-planning` is the
  front-end: it parses the ticket against the truth layer and emits this
  traversal): Fields (iff user-editable input) → DataModel → ViewModel →
  ServerRequest → View → tests → review.
- **Fields gained/changed a field** — the adopters (RequestBody +
  FormViewModel + Model) + migration + form View + their tests. Nothing
  else.
- **UI design changed** — ViewModel iff the design changes WHICH
  properties exist; then View. Content baked in the design never
  projects.
- **Requirements changed an operation** — ServerRequest + VM operations
  + View bindings + tests.
- **Visual-only change** (no new rendered content) — View alone.
- **New app** — App bootstrap first, then as New feature.

## Halt states (not failures — correct terminations)

- **Missing argument** (silent requirements/design): emit an UNRATIFIED
  candidate for the owner's red pen; never silently substitute.
- **Unknown standing** (artifact truth or projection?): ask; do not
  infer.
- **Framework gap**: finding upstream (bug/PR against FOSUtilities);
  never fork its internals downstream.
- **A rule is missing from this page**: that is a finding against this
  page, not a license to improvise an edge.

Traversal ordering note: ViewModel → ServerRequest is the ratified
convention (the underlying dependency is partial; the convention buys
plan reproducibility).

Ruling ledger: `.claude/docs/execution-model-rulings.md`.
