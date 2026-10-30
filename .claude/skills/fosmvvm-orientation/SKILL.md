---
name: fosmvvm-orientation
description: Build the FOSMVVM View ↔ ViewModel ↔ Ops mental model before editing ViewModels, Views, or client-hosted Ops. Use when a project gate requires orientation before such edits, or before your first edit to that code in a session. Articulate the forward-projection rules in your own words, then walk failure scenarios cause → effect.
---

# FOSMVVM Orientation

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Work through this **once per session**, before the first edit to ViewModels, Views, or client-hosted Ops. Projects can make it mandatory with a `PreToolUse` gate (see [Gating Edits on Orientation](#gating-edits-on-orientation)).

Work through every section **in order** and write your answers **in the chat as visible text**. The value is in the articulation. Skimming defeats it.

If nothing has blocked an edit and no edit is about to happen, ask the user whether one is coming. If not, defer: the articulation work is wasted when no edit follows.

## Why This Exists (SOLID)

These rules fail in ways the compiler can't see. Code that breaks them compiles, renders once, and then goes stale, double-writes, or swallows errors, and the symptom shows up far from the cause. Each rule protects a SOLID principle:

| Rule | Principle protected | What breaks on deviation |
|------|--------------------|--------------------------|
| Views read only the ViewModel | **SRP**: the VM is a *projection of* state, never the state | Stale UI. The View bypasses the projection edge, so invalidation stops reaching it. |
| VMs hold scalars, never `@Observable` references | **SRP + DIP**: a VM is a `Codable` snapshot and does not depend on the store | Hidden coupling. Children traverse the VM to reach mutable state, and the snapshot stops being one. |
| `.bind(appState:)` takes extracted scalars | **LSP**: a value-type `AppState` and an `@Observable` store share property names but not contracts | Substituting one for the other compiles and breaks tracking at the edge. |
| Ops: protocol + Ops + StubOps, `output` last | **ISP + DIP**: Views depend on the ops protocol, never a concrete implementation | Test-only branches leak into production code, and storage writes hide among the inputs. |
| `async` only when the body awaits | **SRP**: the signature states what the body does | Unordered Tasks race, and the last write isn't the last tap. |
| Never fail silently | **Encapsulation**, the precondition SOLID assumes and not a principle of it: errors cross the boundary as values | Failures vanish, and the bug report can't be reproduced. |

A "simplification" that breaks one of these is a **stop**, not a style choice.

## Section 1: Read the architecture

Read these sections of [`shared/architecture-patterns.md`](../shared/architecture-patterns.md) now, using the Read tool. Every section below assumes you've read them:

- **The Four Rules of Forward Projection**
- **Where the Projection Edge Lives**
- **VMs Hold Scalars, Not `@Observable` References**
- **`.bind(appState:)` Takes Scalars, Not `@Observable` Instances**
- **One Top-Level App State, Not an Environment of Entries**
- **Ops Conventions** (especially *Signature: Inputs First, `output` Last* and *Not `async` by Default*)
- **Never Fail Silently**

**Project mappings.** If the project documents its own mappings, read them too. These are usually a `CLAUDE.md` at the root of the ViewModel tree (see [project-mappings-template.md](project-mappings-template.md)). They name the project's `@Observable` store types, its canonical ViewModels, and where its files live. They add to the patterns above and never replace them. If the project names its own types, use those names in Sections 2 and 3 in place of the neutral ones below.

## Section 2: Articulate what you just read

Answer each question in your own words, in chat. Be specific: generic MVVM platitudes don't count.

a) What is the relationship between a ViewModel and its View? Who reads what, and who writes what?

b) A View needs to display a value computed from two VM fields. Where does that computation belong, and why does putting it anywhere else break the pattern?

c) Why are Operations split into a protocol, Ops, and StubOps? What exactly does the VM's private `isStub` flag accomplish?

d) Why does a top-level VM hold only scalars and not `@Observable` references such as `WorkspaceSettings`? What goes wrong if a VM holds one "just as a pass-through for child binds"?

e) Why can't you pass an `@Observable` instance where `.bind(appState: .init(...))` expects scalars, even when the property names line up? What does restating them as a struct accomplish at the projection edge?

f) What happens to an error thrown by `try await op(...)` inside `Task { try await op(...) }` with no `catch`? Why is "the Task just ends quietly" the wrong mental model, and where should the error surface instead?

## Section 3: Reason through scenarios

For each scenario, explain **what breaks** and **which observable symptom appears first**. Don't hedge. Walk cause → effect until the failure mode is explicit.

**Scenario A.** A button in a View doesn't fire its action reliably. The tempting fix is to add `@State var triggered = false` to the View, flip it on tap, and read and write it directly in the View body. Following the projection direction: what breaks, and which stub-driven test fails first?

**Scenario B.** A stub needs a different return value for one test case. The tempting fix is to add `if isStub { return ... }` inside the **live** Ops implementation. Following the Ops shape: what invariant does this violate, and what is the point of the stub/live split?

**Scenario C.** An op is declared `async throws`, but its body is just `storage.cardWidth = width`. The tempting choice is to leave it `async` because "more async can't hurt." Following SwiftUI's tap handling: what failure appears, and what would a user report? (Hint: rapid stepper taps.)

**Scenario D.** A child view needs `WorkspaceSettings` for its `.bind(appState:)` call. The tempting fix is to add `workspaceSettings: WorkspaceSettings` to the parent `WorkspacePreferencesViewModel` so children can reach it through the VM. Following the VM shape: what is the hidden coupling? What do the Views *look* like they're doing, and what *are* they doing?

**Scenario E.** A child's `.bind(appState:)` needs several fields from `workspaceSettings`. The tempting shortcut is `.bind(appState: .init(workspaceSettings))`: the property names line up and it compiles. Following "`.bind(appState:)` Takes Scalars" and the projection-edge model: what contract did you silently discard, and which kind of UI change stops propagating first?

**Scenario F.** A toggle's mutation closure in a View is:

```swift
Task {
    defer { refresh() }
    try await viewModel.operations.applyNotificationsChange(...)
}
```

The remote call inside `applyNotificationsChange` fails intermittently. Following "Never Fail Silently": what does the user see? What does the developer see when debugging the report? Why is "I'll add a `catch` with logging later" the exact trap that let this bug ship?

## Section 4: Clear the gate (gated projects only)

Skip this section if no project gate sent you here.

A gate's block message names a **marker path**. Write your answers to that path **verbatim**. Don't invent or guess a session id. Write only after Sections 1–3 are genuinely complete:

```
# FOSMVVM Orientation: Section 2 Articulations

(a) <your answer>
...
(f) <your answer>

# FOSMVVM Orientation: Section 3 Scenario Walks

Scenario A: <walk; what breaks; first symptom>
Scenario B: ...
...
Scenario F: ...
```

Gates check the content, not just that the file exists. An empty `touch` or a stub won't clear one, and fabricated articulation is still fabricated: the user can read the marker. After writing it, retry the blocked edit.

## Gating Edits on Orientation

*For project maintainers.* To make this skill mandatory, add a `PreToolUse` hook that blocks edits to the project's ViewModel, View, and Ops paths until the session has written its answers to a marker file. [gate-hook.md](gate-hook.md) has the complete setup: the script, the `settings.json` wiring, enabling the plugin for the project so every machine has the skill, and how to verify the gate.

Put the project's type names, store types, and file locations in its own docs, not in a copy of this skill; a forked copy goes stale when the architecture changes. [project-mappings-template.md](project-mappings-template.md) is a starting point.

## See Also

- [Functional Discipline](../shared/functional-discipline.md): the evaluation contract every rule derives from
- [Architecture Patterns](../shared/architecture-patterns.md): the canonical source for each rule tested here
- `fosmvvm-viewmodel-generator`: the Ops / StubOps / `isStub` wiring
- `fosmvvm-swiftui-view-generator`: `.bind(appState:)` and mutation closures at the call site
- `fosmvvm-review`: post-hoc review against the same rules
