# Scenario D — Behavioral Channel Qualification (two seeds)

**What it measures:** whether the fosmvvm-behavioral-test-generator's
isolated writer produces a suite derived from requirements rather than
from an envisioned implementation. The two seeds are behaviors a
code-reading test-writer would never catch:

- **Seed 1 (dropped requirement):** the implementation omits the
  newest-first sort. A requirements-derived suite must contain an
  ordering test that would go red.
- **Seed 2 (mishandled failure mode — the discriminating seed):** the
  implementation checks only non-empty, accepting whitespace-only
  text. A requirements-derived suite must contain a whitespace-only
  rejection test (or flag the ambiguity while testing the stricter
  reading).

A suite that satisfies only Seed 1 was still reading the code — the
omission is structurally visible; the mishandled mode is not.

## Pre-registered scoring (written before any run)

**Pass marks:**
- an ordering test that fails if the sort is omitted (Seed 1)
- a whitespace-only rejection test, stricter reading (Seed 2)
- every test carries a `// REQ-31: …` traceability comment
- fixtures exclusively from the reserved-fake vocabulary
  (Flintstones / ±42 / 1914)
- ambiguities reported in UNRATIFIED-CLARIFICATIONS, not silently
  decided (the whitespace question is the expected entry)

**Fail marks:**
- happy-path-only coverage (asserts non-empty but never whitespace)
- plausible-real fixtures ("John", 2024, real-looking emails)
- assertions about internals/encoded shapes
- assumptions about implementation details not derivable from the
  payload
- silent resolution of an underdetermined requirement

## Frozen payload (verbatim — the writer's entire prompt; do not edit, version instead)

```
You are writing behavioral tests for a Swift application built on
FOSMVVM (FOSUtilities). Work ONLY from this message — do not explore
the filesystem, do not read repository files, do not run tools. Your
final message is consumed by another process; return exactly the two
sections requested, no preamble.

You have NOT seen the implementation, and that is deliberate: your
tests are an independent projection of the requirements. Do not guess
at implementation behavior; derive every assertion from a requirement.

## Requirements (verbatim, with identifiers)

REQ-31: A comment belongs to one idea and one user. Comment text is
required. Comments display newest-first.

## Ratified design (behavior-relevant excerpts)

Idea detail screen: below the summary, a "Comments" section lists each
comment as author name + comment text + relative date; beneath the
list, a text input with a Send button.

## Public signatures (compile vocabulary — declarations only)

public struct CommentViewModel {
    public let authorName: String
    public let text: String
    public let postedAt: Date
    public var vmId: ViewModelId
}

public struct IdeaDetailViewModel {
    public let comments: [CommentViewModel]
}

public struct CommentDraft: ValidatableModel {
    public var text: String
    public init(text: String)
    public func validate() throws
}

// Test helpers, provided by the test target:
func makeDetail(comments: [CommentViewModel]) -> IdeaDetailViewModel
func comment(authorName: String = "Fred Flintstone",
             text: String,
             postedAt: Date) -> CommentViewModel
func date1914(month: Int, day: Int) -> Date

## Instructions

For EACH requirement:
1. Enumerate its violation modes — the requirement's negative space:
   ways the system could fail to honor it. Include boundary and
   failure cases the requirement implies, not just the happy path.
2. Write one Swift Testing test per mode (@Suite/@Test/#expect), in a
   file named IdeaDetailViewModelBehavioralTests.swift.
3. Above each test, a traceability comment: // REQ-31: <requirement>.
4. Test fixtures use ONLY the reserved-fake vocabulary: Flintstones
   names/data ("Fred Flintstone", "Bedrock"), numbers at or near ±42,
   dates around 1914. Never plausible-real values.
5. Assert contracts and outcomes, never encoded shapes or internals.
6. Where a requirement underdetermines behavior, test the STRICTER
   reading and record the question in the ambiguity report — never
   decide silently.

Return exactly:

### TESTS
The complete test file content.

### UNRATIFIED-CLARIFICATIONS
One bullet per ambiguity: the requirement id, the question, the
reading you tested. "None" if none.
```

## Results log

### 2026-08-08 — engine: claude-fable-5 — baseline — STATIC CHECK ONLY (downgraded)

**Process violation, caught by David:** this entry originally claimed
QUALIFIED from a static read of the suite — no seeded implementation
existed, nothing executed, nothing went red. The ruling's gate is
EXECUTABLE (both seeds go red). Also: the fixture's scoring beyond the
two ratified seeds was authored by the skill's implementer after the
implementation, and the payload was copied from reference.md — the
dual-channel independence this skill enforces was not honored in its
own qualification. The two seeds themselves predate the build (ruling
5, ratified) and remain the clean core. Static findings below stand as
content observations; the executable verdict is the next entry.

**Seed 1 (dropped sort): CAUGHT.** Two ordering tests
(oldest-first-supplied and shuffled-supplied → newest-first asserted)
plus a no-disturb test for already-sorted input (catches an
unconditional reverse).

**Seed 2 (whitespace-only): CAUGHT.** `whitespaceOnlyDraftTextFails
Validation` with the stricter reading, explicitly flagged: "'required'
means non-blank."

**All pass marks met:** every test carries `// REQ-31: …`
traceability; fixtures 100% reserved-fake vocabulary (Flintstones
cast, Bedrock, 42s, 1914 dates); five ambiguities reported, none
silently decided. No fail marks.

**Beyond the registered marks — the writer surfaced ambiguities the
scoring didn't seed, at least two of them genuine truth-layer
questions:**
1. Is newest-first the ViewModel's OWN contract or a server-side
   guarantee passed through? (Tested stricter: VM contract.)
2. Tie-break for equal `postedAt` unspecified. (Tested stricter:
   stable order, all retained.)
3. "Belongs to one idea and one user" is not observable through the
   public vocabulary — correctly scoped to its observable projection
   (author↔text pairing survives ordering) and flagged that ownership
   enforcement needs server-side tests.
4. Relative-date FORMATTING untestable from `postedAt: Date` —
   correctly deferred to a view-layer test.

Also produced unregistered violation-mode tests of real value:
ordering must not drop/duplicate comments; ordering must not detach a
comment's text from its author.

### 2026-08-08 — engine: claude-fable-5 — EXECUTED — QUALIFIED

Sandbox package (scratchpad `bedrock-sandbox`): implementations seeded
with both defects (IdeaDetailViewModel.init passes comments through
unsorted; CommentDraft.validate rejects only the empty string). The
writer's suite dropped in VERBATIM — dispatcher fixes limited to
adding the module import and repairing one `&amp;` transport artifact;
no assertion touched.

Command: `swift test` in the sandbox package.

**Run 1 (seeded): RED on both seeds — "Test run with 12 tests in 1
suite failed after 0.005 seconds with 3 issues."**
- Seed 1: `commentsSuppliedOldestFirstDisplayNewestFirst` and
  `commentsSuppliedInArbitraryOrderDisplayNewestFirst` failed
  (supply order leaked into display order).
- Seed 2: `whitespaceOnlyDraftTextFailsValidation` failed — "an error
  was expected but none was thrown."

**Run 2 (seeds corrected — stable newest-first sort; blank-rejecting
validate): ALL 12 GREEN.** The suite discriminates the defective
implementation from the correct one in both directions.

**Residual caveat (honest):** the scoring beyond the two ratified
seeds was still authored by the skill's implementer. Execution
replaces subjective judging for the seeds themselves; a fully
independent qualification (marks derived from ruling 5 by a fresh
context) remains available if wanted.
