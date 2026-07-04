---
name: fosmvvm-planning
description: Plan FOSMVVM implementation work with a design-first, DocC-first gate. Use BEFORE writing an implementation plan that adds or changes FOSMVVM types, protocols, ViewModels, requests, identities, or persistence — it applies FOSMVVM's design and documentation discipline up front, then hands task decomposition to your generic plan process.
---

# FOSMVVM Planning

Plan FOSMVVM work in the order that catches the expensive mistakes **before** they reach code.

## Conceptual Foundation

A generic planning process (decompose → TDD → review) is necessary but **not sufficient** for FOSMVVM. In practice, almost none of the rework on a FOSMVVM plan comes from bad task decomposition — it comes from **design and documentation quality**: a stringly-typed identity, a second serialization format, two spellings of one operation, a published representation, `@testable` used for contract tests, theatrical comments, and DocC written from the implementer's chair instead of the customer's.

Those are all **checklistable and cheapest to fix at planning time**. This skill front-loads them. It does **not** replace your decomposition process — it runs a gate first, then hands off.

> **Source-of-truth ordering:** SOLID → the architecture docs (`.claude/docs/FOSMVVMArchitecture.md`, [Architecture Patterns](../shared/architecture-patterns.md), [Naming Dictionary](../shared/NAMES.md)) → code. And remember the precondition SOLID assumes: **encapsulation** (repo `CLAUDE.md` → *Encapsulation Is the Precondition SOLID Assumes*).

## When to Use This Skill

Use it before writing an implementation plan whenever the work **adds or changes**: a public type or protocol, a `Model`/identity/namespace, a `ViewModel` or its `vmId`, a `ServerRequest`/`Fields`, a persisted/serialized form, or any new public API surface. Skip it for a pure mechanical edit (rename, move, dependency bump) with no new surface.

## The Sequence (do these in order)

Announce: *"Using fosmvvm-planning to gate design → DocC → tests before decomposition."* Then:

### 1. Design the public surface — and justify every symbol

List each **new public symbol** the work introduces. For each, answer "what caller need does this serve?" Then run the gate — a hit is a **stop-and-reconsider**, not a nit:

- [ ] **Minimal surface.** Does it "just work" from the default/common path with nothing new to learn? Every added public getter, initializer, option, or conformance is a cost — justify it or cut it. Two ways to do one thing (`a.b` *and* `B(a:)`) is bloat: pick one, put it on the owner.
- [ ] **Encapsulation (reviewed separately from SOLID).** Sealed value types keep private storage and **no public getter of the raw contents**. Derive on the **owner** (a computed that vends a *typed* value), never expose the raw string. ([Architecture Patterns → Derive on the Owner](../shared/architecture-patterns.md).)
- [ ] **No stringly-typing.** An identity/route/key/token is a **typed** value (`ModelNamespace(for:)`, a `…Request`, `ModelIdentity`), never a raw `String`/`UUID` or a string literal. A `String` has no wall.
- [ ] **One serialization.** If a value is already `Codable`, don't invent a second bespoke format for it. Be deliberate about persistence (frozen, DB-backed, semver-major) vs. rendering (transient) forms.
- [ ] **Requirement + default** for anything a conformer should override with zero-config default (extension-only silently shadows). ([Architecture Patterns → Requirement + Default](../shared/architecture-patterns.md).)
- [ ] **Don't publish the representation.** The encoded shape never appears in DocC/CHANGELOG/README; it's a `//` maintainer note + a forward-compat test.
- [ ] **Boundaries hold.** ViewModel module never imports the domain/wire module (the Factory adapts); persistence types don't cross the SPMLibraries boundary; `ModelIdType` only in `@ID()`.

### 2. Write the customer-facing DocC — FIRST, before any implementation

For every public symbol, draft its `///` **from the call site**, answering the customer's three questions. This is the single highest-leverage step — writing docs after code traps you in the implementer's frame.

- **How do they call it?** Include a **concrete example** (nearly always). No example on public API = debt.
- **Why do they care / how do they benefit?** The problem it solves, in their words.
- **When does it matter?** When to reach for it (and when not).
- State the **contract only** — no implementation details, no design rationale, no notes-to-self. Those go in the **plan prose** (step 4), not the DocC.

Sanity check each draft: if it reads "An opaque X that wraps a Y…", it's implementer-framed — rewrite it to lead with the call. (Repo `CLAUDE.md` → *Documentation & Comments*; [Architecture Patterns → Documentation Has Three Audiences](../shared/architecture-patterns.md).)

### 3. Write the tests as contract tests

Plan tests that exercise **only the public contract**, the way a real caller would:

- Construct values via the public/intended path (`model.modelIdentity`, public inits, `.stub()`), **not** by reaching an internal init/getter. `@testable` is for block/arc **coverage**, never for contract coverage.
- Assert **behavior** (equality, determinism, round-trip identity, "old data still decodes"), **never** an encoded byte/key shape or a derived token's literal string.
- Use the repo round-trip helpers `try value.toJSON().fromJSON()`, not hand-rolled `JSONEncoder`/`JSONSerialization`, and never inspect raw JSON in an assertion.

### 4. Put the rationale in the PLAN PROSE (not the DocC)

The "why this way", rejected alternatives, gotchas, and design context are *expected* — they belong in the plan's prose and the design/spec doc, addressed to future-you the implementer. If any of it crept into a DocC in step 2, **relocate it here**.

### 5. Hand off decomposition

Now hand the gated design to your task-decomposition process (e.g. `superpowers:writing-plans`) for bite-sized TDD tasks, exact file paths, and the review loop. The tasks carry the DocC and tests you drafted above; the plan prose carries the rationale.

## What This Skill Produces

A plan whose **design and documentation are settled before decomposition** — minimal justified API, customer-facing DocC with examples written first, contract-only tests, and rationale in the prose. The generic process then structures it into tasks.

## Definition of Done (planning gate)

- Every new public symbol is justified and passes the step-1 checklist (or the deviation is raised, not hidden).
- Every public symbol has customer-facing DocC with an example, drafted before implementation.
- Tests are planned against the public contract only (no `@testable`-for-contract, no representation assertions).
- Rationale lives in the plan prose, not in DocC.

## See Also

- Repo `CLAUDE.md` — *SOLID Is the Foundation*, *Encapsulation Is the Precondition*, *Documentation & Comments*
- [Architecture Patterns](../shared/architecture-patterns.md) — Encapsulation, Derive on the Owner, Requirement + Default, Documentation Has Three Audiences
- [Naming Dictionary](../shared/NAMES.md) — typed names over stringly-typing
- `superpowers:writing-plans` (or your decomposition process) — the task breakdown this skill hands off to
