---
area: cross-cutting
generator-skill: none
where:
  - "Sources/**/*.swift"
  - "Tests/**/*.swift"
---

# Cross-Cutting Checks

Concerns that span multiple FOSMVVM areas. This check file always triggers when scope is non-empty (regardless of which areas the diff touches).

## Reviewer Guidance

- Silent failure is never acceptable. Every error path must either propagate, log structurally, or surface to the user. "We'll handle it later" is the path to production bugs.
- Honor inline suppression directives (`// fosmvvm-review:disable:next <check> — <reason>` and the `:this` / block forms documented in `SKILL.md`). When a candidate finding's line is covered by a suppression for that check WITH a justification, omit the finding. When the directive is present but missing a justification, emit `suppression-without-justification` instead.

## Check: suppression-without-justification
**Severity:** warning
**What:** Every `fosmvvm-review:disable*` directive must include a justification — text after the check name explaining why the rule is silenced.
**Anti-pattern:** `// fosmvvm-review:disable:next no-silent-failure` (no reason given). Suppressions without reasons are invisible tech debt; the reader cannot tell if the silenced rule was a deliberate exception or a forgotten cleanup.
**Detection:** Find every `fosmvvm-review:disable:next`, `fosmvvm-review:disable:this`, and `fosmvvm-review:disable` directive in scoped files. For each, confirm the line includes text after the check name (typically separated by `—`, `-`, `:`, or whitespace). Flag any directive whose only content is the keyword + check name.

## Check: no-silent-failure
**Severity:** blocker
**What:** Error paths must not silently swallow errors. No empty catches, no `try?` near async device/network calls without explicit handling, no `defer { repaint() }` as the only response to a thrown error.
**Anti-pattern:**
```swift
Task {
    defer { toggleRepaint() }
    try await onPatientSideToggleChanged(viewModel.laterality)
}
```
The `try await` can throw; the `defer` runs but the error vanishes.
**Detection:** Find `try?` adjacent to `await`, empty `catch { }` blocks, and `Task { ... try await ... }` blocks where the only error response is a `defer`. For each hit, verify whether the error is propagated, logged, or surfaced. Flag if not.
