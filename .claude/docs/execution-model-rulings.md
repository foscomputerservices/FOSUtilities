# Execution Model — Rulings Ledger

**All five rulings below were RATIFIED by David (2026-08-08), adopting
the engine recommendations as written: (1) Factory ←
viewmodel-generator; (2) YAML split standing — values truth, structure
projection; (3) requirements-side Operations edges mapped, execution
side held; (4) ViewModel → Request as convention; (5) a dedicated
behavioral-test skill (to be built). Outcomes live as plain rules in
`shared/execution-model.md`; this file remains as the decision ledger.**

Audience: David (ruling) and the session that processes his rulings.
This file carries the provenance and decision context that the
consumer-facing page (`.claude/skills/shared/execution-model.md`)
deliberately omits — sessions need current rules, not the history of
how they were reached. When a ruling lands, its outcome is written into
the page as a plain rule and the brief here is marked resolved.

> **Protocol (the blindness rule).** Owner and engine have almost no
> shared context — different faculties, not just different facts. So a
> hole flagged for ruling must be a self-contained decision brief:
> what surfaced it, the candidates, what breaks under each, and the
> engine's recommendation marked as such — never "he'll see what I
> see." Rulings return with their rationale, for the same reason in
> the other direction: a bare verdict leaves the engine guessing the
> ruling's boundary.

## 1. Factory ownership

**Surfaced by:** litmus scenario C (2026-08-08) — two interpreters,
same inputs, opposite answers. The control arm generated the server
Factory under `fosmvvm-viewmodel-generator`; the delta arm under
`fosmvvm-serverrequest-generator`. Not determinable from the skills'
current declarations.

**Why it matters:** the Factory (`static func project(...)`) is the DIP
seam — domain models → ViewModel. If no skill owns it, every Factory
change is scheduled by session judgment.

- **Candidate A — viewmodel-generator owns it.** The Factory is f for
  one artifact: the VM and its projection are one unit of meaning.
  Consequence: one skill spans client and server modules; a VM shape
  change stays a one-skill traversal.
- **Candidate B — serverrequest-generator owns it.** The Factory runs
  at request-fulfillment time, server-side; group by where/when it
  executes. Consequence: a VM shape change becomes a two-skill
  traversal (shape in one skill, projection in another) — a fork risk
  for the single most coupled pair in the system.

**Engine recommendation (weakly held):** A, for cohesion of shape and
projection.

## 2. Localization YAML — mixed standing

**Surfaced by:** deriving the rule set; confirmed by litmus A, where
sessions emit YAML values freely.

**Why it matters:** the file holds owner-authored display text inside
generator-emitted structure. Without a ruling, sessions cannot tell
which edits are "patching output" and which are "authoring truth."

The file interleaves the two kinds:

```yaml
en:
  accountHeaderViewModel:    # keys mirror the VM's properties —
    title: "Account"         #   derivable structure (projection);
                             # values are the owner's words (truth)
```

Concretely, under Candidate C: the VM gains a `projectsBadge` property
→ the session adds the `projectsBadge:` key (structure tracks the VM),
carries `"Account"` over character-for-character (the owner's word is
untouchable), and proposes the new value flagged UNRATIFIED — a value
that never existed has no authored truth yet.

- **Candidate A — whole file is truth.** Generators may never touch
  it. Consequence: every new property requires the owner to hand-author
  keys; the generators' YAML emission becomes a violation.
- **Candidate B — whole file is projection.** Consequence: re-projection
  may overwrite owner-authored copy — truth destroyed by the engine.
- **Candidate C — split standing.** VALUES are truth (unauthored values
  are emitted UNRATIFIED for red pen); STRUCTURE/keys are projection.
  Consequence: sessions may restructure keys during re-projection but
  must carry values over verbatim.

**Engine recommendation:** C — it matches how the file is actually
produced and edited today.

**Refinement (David's axiom red-line, 2026-08-08):** value provenance —
values derive from the ui design's COPY (labels, titles) and sometimes
the requirements; a design's SAMPLE DATA never becomes a value. This
and the never-project-sample-data tell are two halves of one rule:
copy projects into YAML values (then ratified); sample data projects
nowhere.

## 3. Operations (server-based) — requirements-side edges

**History:** the engine originally kept the page silent on Operations,
over-extending the handoff's standing instruction ("the preamble
deliberately does not claim the discipline settles that surface") into
total silence — a Mode-B over-reach the instruction never asked for;
it only forbids claiming the discipline settles the FRAMEWORK's
Operations surface. Caught by David's red-line (2026-08-08), which
also sketched the requirements-side mapping: requirements state what
data is on the server and the operations needed against it —
read/write/query, deliberately unbound from SQL (e.g., "The
application SHALL show the users ordered by last name") — translating
into ServerRequest semantics that server-based Operations consume:

```
ServerRequest semantics  ← requirements (server data + operations,
                           storage-unbound SHALL-statements)
Server-based Operations  ← ServerRequest semantics
```

**Ruling requested:** adopt the requirements-side edge pair (the
arguments are stable regardless of framework churn), while the
framework-side edge — how Operations execute — stays unmapped until
that surface stabilizes? **Engine recommendation:** yes — map the
argument side now, hold the implementation side, keep the caveat where
the skills state it.

## 4. VM ↔ ServerRequest ordering

**Surfaced by:** litmus scenario C — control sequenced Request before
ViewModel (defensible: RequestBody depends only on Fields); the page's
dispatch says ViewModel → Request.

**Why it matters:** the true dependency is partial (RequestBody ←
Fields alone; a RequestableViewModel and its Request reference each
other), so either order is derivable. With a stochastic engine, an
unruled partial order means traversal plans vary run to run.

- **Candidate A — VM → Request as convention.** Not a dependency claim;
  bought for plan reproducibility: uniform traversals are reviewable
  traversals.
- **Candidate B — declare the partial order and allow either.** Truer to
  the graph. Consequence: plan-level variation without cause — the
  scheduling analogue of manufactured diff.

**Engine recommendation:** A — determinism where the graph doesn't
force it is cheap and pays in reviewability.

## 5. The behavioral-test channel has no owner

**Surfaced by:** David, reviewing the page — "I'm not convinced Claude
doesn't just reverse-engineer the code he's going to write and test
that, not the requirements." Confirmed on inspection: the three test
generators produce invariant tests (round-trip, versioning, locales,
typed request/response); no skill owns
`behavioral tests ← requirements`.

**Why it matters:** without an owner, behavioral testing defaults to
the same context that writes the code — the self-verification failure
the dual-channel rule exists to prevent.

- **Candidate A — a new skill** (a behavioral-test generator) whose
  instructions REQUIRE isolated projection: inputs are requirements +
  ratified design only; invoked via a subagent that has not seen the
  implementation. Consequence: clean ownership, one more skill to
  maintain.
- **Candidate B — extend the three existing test generators** with a
  behavioral section each, carrying the same isolation requirement.
  Consequence: no new skill, but isolation discipline is spread across
  three docs, and the invariant/behavioral distinction blurs — the
  very confusion that produced this hole.

**RULING (David, 2026-08-08): Candidate A ratified. BUILT same day** —
`fosmvvm-behavioral-test-generator` (SKILL.md + reference.md): a
dispatcher/writer split where the dispatcher assembles an isolation
payload (requirements verbatim + ratified design + public declarations
only) and spawns the writer as a fresh subagent; assertion edits by
the dispatcher are forbidden (payload fix + re-run instead);
ambiguities return as UNRATIFIED-CLARIFICATIONS; closure per the
execution-model. Qualified via litmus scenario D (two seeds).

**Engine recommendation (adopted):** A — the two test kinds have
different inputs, different isolation requirements, and different
failure modes.
Qualification for whichever candidate ships: a litmus scenario with
two seeds — a dropped requirement (code omits it) and, the
discriminating one, an unhandled failure mode (requirement: "text is
required"; code accepts whitespace-only). The behavioral suite passes
qualification iff both go red; a suite that catches only the dropped
requirement was still reading the code.

## Open direction (David, 2026-08-08 — brainstorm, unratified): derived formal contracts

The engine could project formal semantics — e.g. abstract Swift
protocols — from f's arguments, each binding back via comment
references to the requirements it derives from. The economics: a
derived formal contract is a COMPACT RATIFICATION SURFACE — small and
precise, cheap for the owner to red-pen; once ratified, standing is
conferred and it is truth at its layer, so tests deriving from it are
on-channel. The architecture already runs one instance of this
pattern: the Fields protocol IS a formal contract derived from
requirements, ratified, then projected three ways. This direction
generalizes Fields to operation semantics — the middle ground between
prose (cheap, soft) and human-authored formal specification (which
does not pay at application level; cost anchor from David's MSR
contract-coverage work: two man-years to prove a linked list).

## 6. Stubbable abuse — fabricated arguments with no provenance

**Surfaced by:** David (2026-08-08) — "I've seen AI use stub() to fill
placeholders… then they remain forever and it's practically impossible
to discern from the tester's POV that the data isn't real." Corroborated
by litmus A: the control arm copied design sample data into stub().

**Why it matters:** a stub value is a fabricated argument. The ruled
behavior at a requirements gap is the missing-argument halt; stub()
gives silent substitution an officially sanctioned syntax — the
violation dressed as framework conformance. And stub data carries no
provenance in the data itself, so placeholders acquire de facto
ratification by persistence. Stub shapes are load-bearing downstream
(test generators derive from Stubbable), doubling the stakes.

- **Candidate A — reserved-fake vocabulary.** Stub values drawn only
  from a canonical, obviously-synthetic namespace (the 555 /
  example.com pattern). Data self-marks; leakage into YAML, migration
  defaults, or Factory fallbacks is grep-detectable. Catches
  value-copying, which no call-site rule sees.
- **Candidate B — boundary enforcement.** stub() call sites permitted
  only in preview/test contexts; a fosmvvm-review check. Catches
  call leakage, which no vocabulary rule sees.
- **The halt-tell (either way):** "a stub value is never the answer to
  a requirements gap" — added where the tells live.
- **Framework option (separate finding, owner's call):** interactive
  VMs already carry isStub wiring; a rendered watermark when a stubbed
  VM draws outside a preview would make fake data visible at the
  glass.

**Engine recommendation:** A + B + the halt-tell — complementary
surfaces (values vs call sites vs the moment of temptation).
Qualification seed for the litmus suite: a ticket with a deliberate
requirements gap; the session passes iff it halts with an UNRATIFIED
candidate rather than stubbing and shipping.

**RULING (David, 2026-08-08): Candidate A ratified, with the canonical
vocabulary supplied** — Flintstones names/data, numbers at/near ±42,
dates around 1914 (his historical convention). Landed in the page as
the stub() values rule. The halt-tell landed with it as a derivation
of the existing missing-argument halt state (stub-at-a-gap = silent
substitution), not new truth. **Candidate B also RATIFIED (David,
2026-08-08)** — landed as two blocker checks in
`fosmvvm-review/checks/cross-cutting.md`: `stub-vocabulary`
(plausible-real placeholders flagged) and `stub-leakage` (stub calls
or vocabulary values in production paths, YAML values, migration
defaults, Factory fallbacks). Ruling CLOSED.
