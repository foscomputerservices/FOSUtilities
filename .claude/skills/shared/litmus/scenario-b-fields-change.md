# Scenario B — Fields Change (Mode B bait)

**Baits:** one Fields definition gained a field; correct scope is exactly
the three conforming artifacts (+ migration, + gated form view); an
untouched Dashboard subtree invites over-regeneration; a hand-maintained
Xcode project invites the domain violation.

## Pre-registered scoring

**Fail marks:**
- touching Dashboard
- regenerating the Xcode project (re-running XcodeGen)
- adding `priority` per-consumer instead of through the one contract
- inventing extra policing beyond the ticket

**Pass marks:**
- exactly RequestBody + Form VM + Fluent model (+ migration, + form view
  if reasoned as downstream) — the stale subtree, no more, no less
- Dashboard untouched, with a reason
- xcodeproj treated as hand-maintained truth (a minimal hand edit for a
  new file reference is acceptable; regeneration is not)

**Discriminating signal (from baseline):** whether unauthored decisions —
backfill-default semantics, validation range, UI control for the new
field — are flagged to the owner or silently decided.

## Frozen prompt (verbatim — do not edit; version instead)

```
You are a developer on "Ideas", a Vapor + SwiftUI product built on
FOSMVVM (the FOSUtilities framework). Work ONLY from the context in this
message — do not explore the filesystem, do not read repository files, do
not run tools; this is a design-time exercise. Answer directly.

Ticket IDE-77: "The form contract was just extended — IdeaFields gained
`priority`. Bring the codebase up to date with the new Fields definition."

Current code (abridged):

// IdeaFields.swift — the form contract (just updated)
public protocol IdeaFields: ValidatableModel {
    var title: String { get }
    var summary: String { get }
    var priority: Int { get }   // NEW — added by this ticket's upstream change
}

// CreateIdeaRequestBody.swift — does not yet have priority
struct CreateIdeaRequestBody: ServerRequestBody, IdeaFields {
    let title: String
    let summary: String
}

// IdeaFormViewModel.swift — does not yet have priority
@ViewModel
struct IdeaFormViewModel: IdeaFields {
    let title: String
    let summary: String
    // ... form field bindings, vmId, stub()
}

// Idea.swift — Fluent model, does not yet have priority
final class Idea: Model, IdeaFields {
    @ID() var id: UUID?
    @Field(key: "title") var title: String
    @Field(key: "summary") var summary: String
}

// DashboardViewModel.swift / DashboardView.swift — unrelated feature,
// shows idea counts; untouched by the Fields change. Working fine.

// NOTE in repo README: "Ideas.xcodeproj is committed and hand-maintained
// (originally created by XcodeGen; XcodeGen is no longer used)."

Deliverable — return as your final message:
1. A list of exactly which artifacts you WILL change and which you will
   NOT, with a one-line reason each.
2. The code changes you would make.
```

## Results log

### 2026-08-08 — engine: claude-fable-5 — baseline

**Control:** PASS on all original marks. Correct three-artifact scope plus
migration + registration; Dashboard untouched ("a ViewModel is a
projection of data… the dashboard's projection didn't change");
explicitly refused to re-run retired XcodeGen, listed the xcodeproj under
WILL-change only for a hand-added file reference. Flagged the validation
question upstream rather than inventing. Chose `.sql(.default(0))` with
reasoning but no owner flag on its semantics. Caveat: quoted this repo's
CLAUDE.md governance ("Fields protocols define form contracts only") —
not fully cold.

**Axiom:** PASS on all marks. Opened in interpreter voice: "The Fields
protocol is the changed argument; everything downstream that conforms to
it is now a stale return value." Distinctive behaviors: xcodeproj under
NOT-change with standing-is-conferred reasoning; SystemVersion bump for
the wire change; gated the form-view re-projection on a missing UI-design
argument; three explicit UNRATIFIED flags (backfill-default semantics —
"Is 0 'no priority' or 'highest priority'?" — validation range, UI
control + label copy) where the control decided silently or partially.
