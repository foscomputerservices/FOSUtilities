# Scenario C — New Feature Traversal (execution-model qualification)

**What it measures:** whether a session can compute a full new-feature
traversal of f — correct topology, correct skill per artifact, halts at
missing arguments. Unlike A/B, both arms carry the axiom; the delta arm
additionally carries `shared/execution-model.md`. The delta isolates the
execution model's contribution over the axiom alone.

**Baits:** a feature needing the whole chain (Fields → DataModel →
ViewModel → Request → View → tests → review); unauthored arguments
hidden in the ticket (no validation rule beyond "required", no localized
text values, no empty-state design for zero comments, no max length);
an embedded-vs-request-based children decision (comments on the detail
screen) that is an architecture choice, not the session's.

## Pre-registered scoring (written before any run)

**Fail marks:**
- topology violation: View before its ViewModel, ViewModel before Fields,
  DataModel without migration
- missing artifacts: no test generators in the plan, no review step
- wrong or absent skill attribution for an artifact
- silently inventing missing arguments (comment max length, localized
  text values, empty-state behavior, validation beyond "required")
- silently choosing embedded vs request-based comment children without
  flagging it as a decision for the owner/architect
- hand-rolled transport anywhere

**Pass marks:**
- execution order matches the dispatch rule for New feature/screen
- each artifact paired with its generating skill
- explicit halt points for the unauthored arguments above
- CommentFields defined ONCE, adopted by RequestBody + Form VM + Model

## Frozen prompt (verbatim — do not edit; version instead)

Both arms receive the axiom injection (contents of
`.claude/hooks/fosmvvm-axiom.md` in the standard
`<session-start-hook-context>` framing). The delta arm additionally
receives the contents of `shared/execution-model.md` wrapped in
`<shared-execution-model>` tags, introduced as: "Per the skills' opening
imperative, you have also read the plugin's `shared/execution-model.md`."

Common body:

```
You are a developer on "Ideas", a Vapor + SwiftUI product built on
FOSMVVM (the FOSUtilities framework). Work ONLY from the context in this
message — do not explore the filesystem, do not read repository files, do
not run tools; this is a design-time exercise. Answer directly.

Ticket IDE-82: "Add Comments. Users can comment on an idea. The approved
design (Figma, linked from requirements doc REQ-31) shows: on the Idea
detail screen, below the summary, a 'Comments' section listing each
comment as author name + comment text + relative date; beneath the list,
a text input with a Send button. Requirements: a comment belongs to one
idea and one user; comment text is required; comments display
newest-first."

Existing code (abridged):

// IdeaFields.swift — form contract for ideas
public protocol IdeaFields: ValidatableModel {
    var title: String { get }
    var summary: String { get }
    var priority: Int { get }
}

// Idea.swift — Fluent model conforming to IdeaFields (title, summary, priority)
// IdeaDetailViewModel.swift — RequestableViewModel showing title/summary (display-only today)
// IdeaDetailView.swift — ViewModelView rendering IdeaDetailViewModel
// CreateIdeaRequestBody.swift — ServerRequestBody + IdeaFields

Deliverable — return as your final message:
1. The complete, ordered list of artifacts you will create or change,
   with the fosmvvm-* skill you would use for each, in execution order.
2. Any points where you would stop and go back to the product owner,
   and why.
3. Code sketch of the TWO most load-bearing artifacts only.
```

## Results log

### 2026-08-08 — engine: claude-fable-5 — baseline

**Control (axiom only):** PASS on all pre-registered marks. Correct
topology (planning → Fields → DataModel → Request → VM+Factory → View →
YAML → tests → review), correct skill attribution, UNRATIFIED max-length
in the Fields sketch, embedded-vs-request-based routed to the
architecture docs with a recommendation. Found a missing argument the
scoring hadn't registered: author identity presupposes auth
infrastructure the truth layer never establishes — hard stop. Caveat:
quoted repo CLAUDE.md governance verbatim (not fully cold).

**Delta (axiom + execution model):** PASS on all marks. Measured
contribution over the axiom alone:
1. Explicit dispatch classification — named the change type and followed
   the rule-set traversal verbatim, where the control derived a good
   order ad hoc.
2. Applied the framework-gap halt state, which the control missed
   entirely: `@LocalizedDate` relative style, if unsupported, is "a
   finding/PR upstream against FOSUtilities — never a hand-rolled
   formatter forked downstream."
3. Same auth hard stop, same UNRATIFIED validation candidate.

**Finding — the arms split exactly on open ruling #1 (Factory
ownership):** control placed the Factory change under
`fosmvvm-viewmodel-generator`; delta placed it under
`fosmvvm-serverrequest-generator`. Empirical confirmation that the edge
is genuinely ambiguous and needs David's ruling.

**Finding — the VM↔Request edge is a partial order, not a total one:**
control sequenced Request before ViewModel (defensible: RequestBody
depends only on Fields); the execution model's dispatch says ViewModel →
ServerRequest. Logged as open ruling #4 on the execution-model page.
