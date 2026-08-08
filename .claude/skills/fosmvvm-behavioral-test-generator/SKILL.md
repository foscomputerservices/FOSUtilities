---
name: fosmvvm-behavioral-test-generator
description: Generate behavioral test suites projected from requirements + ratified design in an ISOLATED context that has never seen the implementation. Use when a traversal reaches its tests stage and requirement semantics (validation rules, operation semantics, ordering) need verification — the second channel of f.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "⚖️", "os": ["darwin", "linux"]}}
---

# FOSMVVM Behavioral Test Generator

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Generate behavioral tests — the tests that verify the application does
what the *requirements* say, not what the implementation happens to do.

## Conceptual Foundation

> Governing frame: [`shared/execution-model.md`](../shared/execution-model.md) § The dual-channel rule.

Tests projected from the implementation — written or merely envisioned —
verify the projection against itself. Reverse-engineered tests can only
cover paths the code contains, and **failure modes are precisely the
paths it doesn't**: "text is required" → code checks non-empty → test
asserts non-empty → green, while whitespace-only, oversized input, and
double-send ship untested. Order alone buys nothing (tests-first in the
same context still targets the envisioned code); the test-writer's
CONTEXT is the entire mechanism.

So this skill runs as **two roles in two contexts**:

```
┌──────────────────────┐   isolation payload    ┌──────────────────────┐
│  DISPATCHER          │ ─────────────────────► │  WRITER (subagent)   │
│  (working session —  │   requirements +       │  fresh context —     │
│   has seen the code) │   ratified design +    │  has NEVER seen the  │
│                      │   public signatures    │  implementation      │
│  runs suite, judges  │ ◄───────────────────── │  writes the suite    │
│  red = channel       │   tests + ambiguity    │  from the arguments  │
│  disagreement        │   report               │                      │
└──────────────────────┘                        └──────────────────────┘
```

**Agreement between the two independent channels is the evidence.**
Red is not failure — red is the comparator working.

**SOLID this protects — DIP, applied to verification:** the suite
depends on the requirement layer (the abstraction), never on the
implementation (the concretion). Break the isolation and the dependency
inverts silently: the tests now certify whatever the code does, failure
modes ship green, and the violation is invisible in review because the
suite *looks* thorough. **Encapsulation:** behavioral tests assert the
contract, never the representation — no reaching into internals, no
pinning encoded shapes (see [Architecture Patterns → Encapsulation Is
the Precondition](../shared/architecture-patterns.md)).

## When to Use This Skill

- A traversal (per `shared/execution-model.md` dispatch) reaches its
  tests stage and the artifact has requirement-driven semantics:
  validation rules, operation semantics, ordering, state transitions
- Requirements changed and the behavioral suite is stale
- Red-before-green: ideally invoked BEFORE the implementation exists,
  so the second channel exists first
- NOT for round-trip/versioning/locale tests (invariant tests — use the
  existing test generators) and NOT for Fields↔adopter agreement
  (consistency tests)

## What This Skill Generates

| File | Location | Purpose |
|------|----------|---------|
| `{Name}BehavioralTests.swift` | `Tests/{Target}Tests/` | Requirement-derived behavioral suite |
| Ambiguity report | conversation (dispatcher routes upward) | UNRATIFIED clarification candidates found during projection |

## Project Structure Configuration

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{Name}` | The artifact under test | `IdeaDetailViewModel`, `CreateCommentRequest` |
| `{Target}` | Test target name | `IdeasAppTests` |
| `{REQ}` | Requirement identifier from the truth layer | `REQ-31` |

## How to Use This Skill

**Invocation:**
/fosmvvm-behavioral-test-generator

**Prerequisites:**
- The requirement excerpts governing the artifact identified in context
  (from the requirements document / ticket)
- The ratified design excerpts (including ratified customer-DocC) in
  context
- The artifact's PUBLIC signatures known (type names, property and
  method signatures — the vocabulary tests compile against)

**Workflow integration:**
Invoked at the tests stage of a traversal, ideally before the
implementation is written. The dispatcher (this session) assembles the
isolation payload and spawns the writer via the Agent tool; the writer
returns the suite and an ambiguity report. Complements — never
replaces — the invariant test generators.

## Pattern Implementation

### Role 1 — the DISPATCHER (this session)

1. **Assemble the isolation payload** from context, containing ONLY:
   - the requirement excerpts, verbatim, with their identifiers
   - the ratified design excerpts relevant to behavior
   - the artifact's public signatures (declarations only — the
     compile vocabulary; signatures supply the NOUNS, requirements
     supply every PROPOSITION)
   - the writer instructions from [reference.md](reference.md)
2. **Payload hygiene check — the isolation contract.** The payload
   MUST NOT contain: implementation bodies, the implementation plan,
   existing tests, Factory code, derived-artifact internals (Fields
   validation bodies), or this session's opinions about behavior. If
   an item is load-bearing but forbidden, that is a payload-design
   finding — do not smuggle it in.
3. **Spawn the writer** with the Agent tool, payload as the entire
   prompt. The writer must be instructed not to explore the filesystem.
4. **Receive the suite; write it verbatim.** On compile failure from a
   wrong signature: correct the SIGNATURES in the payload and re-run
   the writer. Never edit assertion logic — a dispatcher-edited
   assertion is the contamination this skill exists to prevent
   (imports/formatting fixes are allowed).
5. **Run the suite. Red = channel disagreement — classify it:**
   - the code violates the requirement → fix the code;
   - the writer misread the requirement → payload defect; fix payload,
     re-run writer;
   - the requirement is genuinely ambiguous → missing-argument halt:
     route the writer's UNRATIFIED clarification upward. Never
     "fix" the test to match the code.
6. **Closure (after green):** run block coverage under the full suite.
   Classify every uncovered block per
   `shared/execution-model.md` § The closure — unspecified behavior
   goes upward as a finding; under-spanned projection strengthens the
   suite FROM THE ARGUMENTS. Never derive a test from an uncovered
   block.

### Role 2 — the WRITER (isolated subagent)

For each requirement in the payload:

1. **Enumerate the violation modes** — the requirement's negative
   space: the ways the system could fail to honor it, not the ways an
   implementation might guard. "Text is required" ⇒ empty,
   whitespace-only, absent field. "Newest-first" ⇒ empty list, single
   element, equal timestamps, order after insertion.
2. **Write one test per mode** (Swift Testing: `@Suite`, `@Test`,
   `#expect`), each carrying a traceability comment binding it to its
   requirement: `// {REQ}: <requirement text>`.
3. **Fixtures use the reserved-fake vocabulary** — Flintstones
   names/data, numbers at/near ±42, dates around 1914 — never
   plausible-real values.
4. **Ambiguity is a finding, not a decision.** Where the requirement
   underdetermines behavior ("required" — does whitespace satisfy
   it?), pick the STRICTER reading for the test, and report the
   ambiguity in the UNRATIFIED-CLARIFICATION section of the reply.
5. **Assert the contract, never the representation** — behavior and
   outcomes, not encoded shapes or internals.

### Context Sources

- **Prior conversation**: the traversal underway, the artifact, its
  requirement identifiers
- **Truth-layer documents**: requirements / ratified design Claude has
  read into context
- **Public API**: signatures gathered for the payload (declarations
  only)

## Key Patterns

### Requirement → violation modes → tests

```swift
@Suite("IdeaDetailViewModel — REQ-31 behavioral")
struct IdeaDetailViewModelBehavioralTests {

    // REQ-31: comments display newest-first
    @Test func commentsAreNewestFirst() {
        let vm = makeDetail(comments: [
            comment(text: "Yabba", postedAt: year1914(day: 1)),
            comment(text: "Dabba", postedAt: year1914(day: 3)),
            comment(text: "Doo", postedAt: year1914(day: 2))
        ])
        #expect(vm.comments.map(\.text) == ["Dabba", "Doo", "Yabba"])
    }

    // REQ-31: comment text is required
    // UNRATIFIED-CLARIFICATION: does whitespace-only satisfy "required"?
    // Stricter reading tested; flagged for the owner.
    @Test func whitespaceOnlyTextIsRejected() throws {
        #expect(throws: (any Error).self) {
            try validated(CommentDraft(text: "   \n"))
        }
    }
}
```

### The two-seed qualification (run before trusting a writer change)

Seed a sandbox implementation with (a) a dropped requirement (omit the
sort) and (b) a mishandled failure mode (accept whitespace-only). The
suite qualifies iff BOTH go red — a suite that catches only the
dropped requirement was still reading the code. Record runs in
[`shared/litmus/scenario-d-behavioral-channel.md`](../shared/litmus/scenario-d-behavioral-channel.md).

## File Templates

See [reference.md](reference.md) for the complete isolation-payload
template (the writer's entire prompt) and the test-file template.

## Naming Conventions

| Concept | Convention | Example |
|---------|------------|---------|
| Test file | `{Name}BehavioralTests.swift` | `IdeaDetailViewModelBehavioralTests.swift` |
| Suite name | `"{Name} — {REQ} behavioral"` | `"IdeaDetailViewModel — REQ-31 behavioral"` |
| Traceability | `// {REQ}: <text>` above each test | `// REQ-31: comments display newest-first` |

## See Also

- [shared/execution-model.md](../shared/execution-model.md) — the dual-channel rule and the closure this skill implements
- [fosmvvm-viewmodel-test-generator](../fosmvvm-viewmodel-test-generator/SKILL.md) — invariant tests (round-trip, versioning, locales)
- [fosmvvm-serverrequest-test-generator](../fosmvvm-serverrequest-test-generator/SKILL.md) — typed request/response tests
- [reference.md](reference.md) — payload + test templates

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-08-08 | Initial skill — implements execution-model ruling 5 (dedicated behavioral-test channel, isolated projection) |
