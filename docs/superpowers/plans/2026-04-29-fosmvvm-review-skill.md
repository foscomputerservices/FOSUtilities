# fosmvvm-review Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `fosmvvm-review` skill that triages branch-diff (or scoped) Swift files into FOSMVVM areas, dispatches one subagent per affected area against per-area check files, and emits a severity-tagged report consumable by humans and CI.

**Architecture:** A skill (markdown + YAML, no compiled code) with one orchestrator `SKILL.md`, an authoring guide `reference.md`, and per-area check files under `checks/`. Triage matches changed files to areas via globs, dispatches subagents in parallel (cap 4), aggregates findings into a markdown or JSON report. Reports are read-only; CI consumes exit codes.

**Tech Stack:** Markdown, YAML frontmatter, shell (git diff), Claude Code Skill tool, Task tool for subagent dispatch.

**Spec:** `docs/superpowers/specs/2026-04-29-fosmvvm-review-skill-design.md`

---

## File Structure

```
.claude/skills/fosmvvm-review/
  SKILL.md                    # entry: arg parsing, triage, dispatch, aggregation, CI flags
  reference.md                # check-file authoring guide (model-agnostic style)
  checks/
    cross-cutting.md          # always triggers; silent failure check
    fields.md                 # stub
    serverrequest.md          # stub
    swiftui-app-setup.md      # stub
    swiftui-view.md           # initial checks + Reviewer Guidance
    ui-tests.md               # initial check + Reviewer Guidance
    viewmodel.md              # initial checks (ops, appState)
    viewmodel-test.md         # stub
    viewmodelrequest.md       # stub
.claude-plugin/plugin.json    # bump 2.1.0 → 2.2.0
```

Each file has one responsibility. `SKILL.md` is the orchestrator; `reference.md` is documentation; each `checks/*.md` is one area's review knowledge. Stubs exist so triage routes correctly day one; depth grows over time.

---

### Task 1: Scaffold skill directory and bump plugin version

**Files:**
- Create dir: `.claude/skills/fosmvvm-review/`
- Create dir: `.claude/skills/fosmvvm-review/checks/`
- Modify: `.claude-plugin/plugin.json` (version 2.1.0 → 2.2.0)

- [ ] **Step 1: Create directories**

```bash
mkdir -p .claude/skills/fosmvvm-review/checks
```

- [ ] **Step 2: Bump plugin version**

In `.claude-plugin/plugin.json`, change `"version": "2.1.0"` to `"version": "2.2.0"`.

- [ ] **Step 3: Verify**

```bash
test -d .claude/skills/fosmvvm-review/checks && grep '"version": "2.2.0"' .claude-plugin/plugin.json
```

Expected: both succeed (exit 0, version line printed).

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude/skills/fosmvvm-review/
git commit -m "chore: scaffold fosmvvm-review skill, bump plugin to 2.2.0"
```

---

### Task 2: Write `reference.md` (check-file authoring guide)

**Files:**
- Create: `.claude/skills/fosmvvm-review/reference.md`

- [ ] **Step 1: Write the file**

Content:

````markdown
# Check File Authoring Guide

This guide specifies the structure and style for files in `checks/`. Each file documents one FOSMVVM area's review knowledge.

## File Naming

`checks/<area>.md` where `<area>` is one of: `fields`, `serverrequest`, `swiftui-app-setup`, `swiftui-view`, `ui-tests`, `viewmodel`, `viewmodel-test`, `viewmodelrequest`, `cross-cutting`.

## Frontmatter (Required)

```yaml
---
area: <area-identifier>
generator-skill: fosmvvm-<area>-generator
where:
  - "<glob pattern>"
  - "<glob pattern>"
---
```

- `area` — matches filename stem.
- `generator-skill` — the corresponding generator skill that owns the positive pattern. Use `none` for `cross-cutting.md`.
- `where` — globs the triage layer matches against scoped files. Multiple globs allowed.

## Body Sections

### `## Reviewer Guidance` (optional)

Free-form meta-instructions read by the subagent BEFORE running checks. Use for:
- Anti-recommendations: things the reviewer must NOT suggest, even if they look like simplifications.
- Mental-model corrections: architectural framings the reviewer must hold.
- Reviewer-mindset guards: known traps that bias review toward leniency.

### `## Check: <name>` (zero or more)

Each check has four required fields:

- **Severity:** `blocker` | `warning` | `nit`
- **What:** one-sentence description of the rule.
- **Anti-pattern:** what wrong code looks like (concrete shape).
- **Detection:** how the subagent identifies hits — grep targets, semantic checks, conditions for true positive.

## Authoring Style (Model-Agnostic)

Code under review may be authored by any LLM. Check files MUST be model-agnostic:

- Describe **the code pattern and why it's wrong** architecturally — never the author's tendencies.
- Anti-patterns describe **shapes** (read-modify-write on outputs, env mutation in views, silent swallows), never authorship.
- Reviewer Guidance describes **what NOT to recommend** with architectural reasons, never "because LLM X reaches for this."

✅ Good: "Operations methods must not read from the same mutable state they write to."
❌ Bad: "Claude tends to write read-modify-write Operations; flag these."

## Stub Form

A stub file has frontmatter + a one-sentence pointer to the generator skill + zero `## Check:` entries. Triage still routes to it; the subagent reports "no checks defined yet."

```markdown
---
area: fields
generator-skill: fosmvvm-fields-generator
where:
  - "Sources/**/Fields/**/*.swift"
  - "Sources/**/*Fields.swift"
---

# Fields Checks

The positive pattern lives in the `fosmvvm-fields-generator` skill. No review-only checks defined yet.
```

## Example: Full Check

```markdown
## Check: ops-no-output-reads
**Severity:** blocker
**What:** Operations methods must not read from the same mutable state they write to.
**Anti-pattern:** Reading `electrodes[index].polarity` then writing `settings.selectedPolarity = ...` in the same method.
**Detection:** For each type conforming to `*ViewModelOperations`, read each method body. Flag methods that both READ from and WRITE to `settings.*` (or other mutable parameter) within the same call.
```
````

- [ ] **Step 2: Verify file structure**

```bash
grep -E "^## (Frontmatter|Body Sections|Authoring Style|Stub Form|Example)" .claude/skills/fosmvvm-review/reference.md | wc -l
```

Expected: `5`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosmvvm-review/reference.md
git commit -m "docs: add fosmvvm-review check-file authoring guide"
```

---

### Task 3: Create stub check files

**Files:** (create all)
- `.claude/skills/fosmvvm-review/checks/fields.md`
- `.claude/skills/fosmvvm-review/checks/serverrequest.md`
- `.claude/skills/fosmvvm-review/checks/swiftui-app-setup.md`
- `.claude/skills/fosmvvm-review/checks/viewmodel-test.md`
- `.claude/skills/fosmvvm-review/checks/viewmodelrequest.md`

- [ ] **Step 1: Write `fields.md`**

```markdown
---
area: fields
generator-skill: fosmvvm-fields-generator
where:
  - "Sources/**/Fields/**/*.swift"
  - "Sources/**/*Fields.swift"
---

# Fields Checks

The positive pattern lives in the `fosmvvm-fields-generator` skill. No review-only checks defined yet.
```

- [ ] **Step 2: Write `serverrequest.md`**

```markdown
---
area: serverrequest
generator-skill: fosmvvm-serverrequest-generator
where:
  - "Sources/**/ServerRequests/**/*.swift"
  - "Sources/**/*Request.swift"
---

# ServerRequest Checks

The positive pattern lives in the `fosmvvm-serverrequest-generator` skill. No review-only checks defined yet.
```

- [ ] **Step 3: Write `swiftui-app-setup.md`**

```markdown
---
area: swiftui-app-setup
generator-skill: fosmvvm-swiftui-app-setup
where:
  - "Sources/**/*App.swift"
---

# SwiftUI App Setup Checks

The positive pattern lives in the `fosmvvm-swiftui-app-setup` skill. No review-only checks defined yet.
```

- [ ] **Step 4: Write `viewmodel-test.md`**

```markdown
---
area: viewmodel-test
generator-skill: fosmvvm-viewmodel-test-generator
where:
  - "Tests/**/*ViewModelTests.swift"
  - "Tests/**/ViewModels/**/*Tests.swift"
---

# ViewModel Test Checks

The positive pattern lives in the `fosmvvm-viewmodel-test-generator` skill. No review-only checks defined yet.
```

- [ ] **Step 5: Write `viewmodelrequest.md`**

```markdown
---
area: viewmodelrequest
generator-skill: fosmvvm-viewmodel-generator
where:
  - "Sources/**/ViewModels/**/*Request*.swift"
  - "Sources/**/*ViewModelRequest.swift"
---

# ViewModel Request Checks

The positive pattern lives in the `fosmvvm-viewmodel-generator` skill (RequestableViewModel section). No review-only checks defined yet.
```

- [ ] **Step 6: Verify all five files exist with frontmatter**

```bash
for f in fields serverrequest swiftui-app-setup viewmodel-test viewmodelrequest; do
  test -f .claude/skills/fosmvvm-review/checks/$f.md && head -1 .claude/skills/fosmvvm-review/checks/$f.md | grep -q '^---$' && echo "$f OK"
done
```

Expected: 5 lines, each ending in `OK`.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/fosmvvm-review/checks/
git commit -m "feat: add stub check files for fosmvvm-review"
```

---

### Task 4: Author `viewmodel.md` with initial checks

**Files:**
- Create: `.claude/skills/fosmvvm-review/checks/viewmodel.md`

- [ ] **Step 1: Write the file**

```markdown
---
area: viewmodel
generator-skill: fosmvvm-viewmodel-generator
where:
  - "Sources/**/ViewModels/**/*.swift"
  - "Sources/**/*ViewModel.swift"
  - "Sources/**/*Operations.swift"
  - "Sources/**/*Ops.swift"
---

# ViewModel Checks

The positive pattern lives in the `fosmvvm-viewmodel-generator` skill. This file documents review-only concerns: anti-patterns, drift, common mistakes in ViewModels and their Operations.

## Reviewer Guidance

- Do NOT recommend collapsing the VM/data-store separation. The VM is the single source of truth for what Views read; the `@Observable` data store is what Operations write to. The `bind(appState: .init(...))` projection edge is where they meet — do not propose moving or removing it.
- Do NOT treat `@Observable` classes and structs as substitutable. They have different functional contracts: structs are values, `@Observable` classes participate in SwiftUI tracking. Recommending one in place of the other is an architectural error.
- Re-projection happens at the top of the subtree that owns `bind(appState:)`. The parent body that constructs the child's AppState is the projection edge. Do NOT propose moving projection edges to "simplify."

## Check: ops-no-output-reads
**Severity:** blocker
**What:** Operations methods must not read from the same mutable state they write to. They take inputs, transform, write outputs — never read-modify-write on the output struct.
**Anti-pattern:** A method on a `*ViewModelOperations` conformer that both reads from and writes to the same parameter (e.g., `settings.electrodeSettings[index].polarity` read, `settings.selectedPolarity = ...` write).
**Detection:** For each type conforming to a protocol matching `*ViewModelOperations`, read each method body. Flag methods that both READ from and WRITE to the same parameter within the same call.

## Check: ops-not-async-unless-needed
**Severity:** warning
**What:** FOSMVVM Operations should not be `async` unless they actually await something.
**Anti-pattern:** `func toggleEnabled(...) async throws { settings.isEnabled = enabled }` — declared `async throws` with no `await` in the body.
**Detection:** For methods on `*ViewModelOperations` conformers declared `async` (or `async throws`), grep the body for `await`. Flag methods where no `await` is present.

## Check: ops-output-param-last
**Severity:** warning
**What:** For clientHostedFactory ViewModels, the output parameter must be the last parameter in the Operation signature and labeled `output:`.
**Anti-pattern:** `func myOp(output settings: Settings, otherInput: Bool)` — output before inputs. Or `func myOp(inputs..., settings: Settings)` — output not labeled `output:`.
**Detection:** Identify ViewModels using `clientHostedFactory`. For their Operations, verify each method signature ends with `output <name>: <Type>`. Flag methods where the output is not last or not labeled `output:`. Server-based VMs (no `clientHostedFactory`) are exempt.

## Check: appstate-no-observable-args
**Severity:** blocker
**What:** `bind(appState: .init(...))` arguments must be plain values projected from `@Observable` state, not `@Observable` types passed by reference.
**Anti-pattern:** `bind(appState: .init(settings: programmingSettings))` where `programmingSettings` is an `@Observable final class`. Crosses the projection boundary.
**Detection:** Find all `bind(appState: .init(...))` call sites. For each argument, determine if its type is `@Observable`. Flag any `@Observable`-typed argument. (Reading a property OFF an `@Observable` and passing the value is fine.)
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## Check:" .claude/skills/fosmvvm-review/checks/viewmodel.md
```

Expected: `4`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosmvvm-review/checks/viewmodel.md
git commit -m "feat: add viewmodel checks for ops and appState patterns"
```

---

### Task 5: Author `swiftui-view.md` with initial checks

**Files:**
- Create: `.claude/skills/fosmvvm-review/checks/swiftui-view.md`

- [ ] **Step 1: Write the file**

```markdown
---
area: swiftui-view
generator-skill: fosmvvm-swiftui-view-generator
where:
  - "Sources/**/Views/**/*.swift"
  - "Sources/**/*View.swift"
---

# SwiftUI View Checks

The positive pattern lives in the `fosmvvm-swiftui-view-generator` skill. This file documents review-only concerns for View bodies and their interaction with VMs and the `@Observable` data store.

## Reviewer Guidance

- Do NOT recommend removing `@Environment(SomeAppState.self)` from a view to "simplify" by reading through `viewModel.someObservableRef.x`. Production may bind both to the same instance, but tests inject independently — collapsing the split breaks test host injection.
- Do NOT recommend collapsing env/VM read-write splits. The split is required for test host injection (TestConfiguration pattern). View reads come from the VM; mutations go through Operations to the `@Observable` store; tests inject the VM stub's state into the env to mirror this.
- The VM is the single source of truth for what Views display. If a value needs to appear in a View, expose it as a frozen scalar on the VM at projection time. Do NOT recommend reaching back into the data store from the View body for display data.

## Check: view-reads-vm-only
**Severity:** blocker
**What:** Views read display data from the VM, never directly from `@Environment`-shadowed data store types when the VM exposes the equivalent.
**Anti-pattern:** A View reads `programmingSettings.amplitudeValue` from `@Environment(ProgrammingSettings.self)` for display when the VM already exposes `amplitudeValue` as a frozen scalar.
**Detection:** For each View, find `@Environment` declarations of `@Observable` types. For each property read off those env values in the View body, check whether the VM exposes the same property name. Flag overlapping reads — the View should be reading from the VM.

## Check: view-no-env-mutation
**Severity:** blocker
**What:** View bodies do not mutate `@Observable` state directly. Mutations go through Operations.
**Anti-pattern:** `programmingSettings.isEnabled = true` written inline in a View body or button action closure.
**Detection:** Inside View bodies and the closures they construct, find assignments where the LHS resolves to a property of an `@Observable` env value. Flag any such assignment. (Operations dispatched from button actions are fine — they call methods on a `*ViewModelOperations` conformer, which mutates internally.)

## Check: view-no-read-through-vm-ref
**Severity:** warning
**What:** A VM may hold a reference to its `@Observable` state for ops dispatch, but Views must not read display data through that reference.
**Anti-pattern:** `viewModel.patientPanelSettings.electrodeSettings[0].isLocked` read in a View body for display.
**Detection:** In View bodies, find chained reads through VM properties whose type is `@Observable`. Flag reads of properties that the VM could expose as frozen scalars at projection time.
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## Check:" .claude/skills/fosmvvm-review/checks/swiftui-view.md
```

Expected: `3`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosmvvm-review/checks/swiftui-view.md
git commit -m "feat: add swiftui-view checks for VM/env separation"
```

---

### Task 6: Author `ui-tests.md` with initial check

**Files:**
- Create: `.claude/skills/fosmvvm-review/checks/ui-tests.md`

- [ ] **Step 1: Write the file**

```markdown
---
area: ui-tests
generator-skill: fosmvvm-ui-tests-generator
where:
  - "Tests/**/UITests/**/*.swift"
  - "Tests/**/*UITests.swift"
  - "**/TestConfiguration*.swift"
---

# UI Tests Checks

The positive pattern lives in the `fosmvvm-ui-tests-generator` skill. This file documents review-only concerns for UI test setup and the test-host pattern.

## Reviewer Guidance

- Do NOT recommend collapsing the env/VM split in production views to "make the test pass" or "simplify." The split is the architectural reason the test host pattern exists. The correct fix when a UI test fails because env state and VM state diverge is to thread the VM stub's state through `TestConfiguration` into the env — not to remove the env or the read/write boundary.
- Test host blocks must mirror production binding. In production, `bind(appState: .init(...))` projects the data store into the VM. In tests, `TestConfiguration` is the analogue — it must construct env state from the VM stub's settings, not from independent `.stub()` calls.

## Check: testhost-mirrors-vm-settings
**Severity:** blocker
**What:** Test host blocks must construct `@Observable` env state from the VM stub's settings, not from independent `.stub()` calls. The env and the VM must hold the same instance, mirroring production binding.
**Anti-pattern:** `let env = ProgrammingSettings(patientRight: .stub())` in a test host while the injected VM holds a different `PatientPanelSettings` instance — taps mutate one, the View reads the other, the test fails for an incorrect reason.
**Detection:** Find blocks named `testHost`, `setUp`, or `presentView` in UI test files. For each construction of `@Observable` env state, verify it threads through the VM stub's settings (typically via `TestConfiguration` payload). Flag env constructions that use `.stub()` independent of the VM.
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## Check:" .claude/skills/fosmvvm-review/checks/ui-tests.md
```

Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosmvvm-review/checks/ui-tests.md
git commit -m "feat: add ui-tests check for test-host VM mirroring"
```

---

### Task 7: Author `cross-cutting.md`

**Files:**
- Create: `.claude/skills/fosmvvm-review/checks/cross-cutting.md`

- [ ] **Step 1: Write the file**

```markdown
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
```

- [ ] **Step 2: Verify**

```bash
grep -c "^## Check:" .claude/skills/fosmvvm-review/checks/cross-cutting.md
```

Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosmvvm-review/checks/cross-cutting.md
git commit -m "feat: add cross-cutting check for silent failure"
```

---

### Task 8: Author `SKILL.md` (orchestrator)

**Files:**
- Create: `.claude/skills/fosmvvm-review/SKILL.md`

- [ ] **Step 1: Write the file**

````markdown
---
name: fosmvvm-review
description: Review FOSMVVM code against per-area check files. Triages changed files by area, dispatches one subagent per affected area for parallel review, emits severity-tagged report. Report-only, no auto-fix. Use when reviewing a branch before merge, sweeping the codebase periodically, or in CI.
homepage: https://swiftpackageindex.com/foscomputerservices/FOSUtilities/documentation/fosmvvm
---

# FOSMVVM Code Review

Reviews FOSMVVM-area Swift files against per-area check files in `checks/`. Designed for both interactive use and CI integration.

## When to Use This Skill

- Before merging a branch (default scope: branch diff vs `main`).
- Periodic codebase sweep (`--all`).
- Reviewing a specific path (`<path>`).
- CI pipelines (use `--format=json` and `--fail-on=blocker`).

## Argument Parsing

Parse the `args` string for these flags. Order does not matter; unknown args produce an error.

| Arg | Effect | Default |
|-----|--------|---------|
| (none) | Scope = branch diff vs `--base`. | Branch diff |
| `--all` | Scope = all `Sources/**/*.swift` and `Tests/**/*.swift`. | — |
| `<path>` | Scope = `.swift` files under `<path>`. | — |
| `--base <ref>` | Override diff base for default scope. | `main` |
| `--format md\|json` | Report format. | `md` |
| `--output <path>` | Write report to file (else stdout). | stdout |
| `--fail-on blocker\|warning\|nit` | Threshold for non-zero exit code. | `blocker` |

`--all`, `<path>`, and the default branch-diff are mutually exclusive scopes; if multiple are given, error.

## Workflow

### Step 1: Resolve Scope

- If `<path>` given: `find <path> -name '*.swift' -type f`.
- If `--all`: `find Sources Tests -name '*.swift' -type f` from repo root.
- Else (default): `git diff --name-only <base>...HEAD -- '*.swift'` where `<base>` is `--base` value or `main`.

If the resulting file list is empty:
- Empty diff: print "No changes to review." Exit 0.
- Path with no `.swift` files: print "No files in scope at `<path>`." Exit 0.
- `--all` with no files: print "No Swift files found." Exit 0.

### Step 2: Load Check Files

Read all `checks/*.md` from this skill's base directory. Parse YAML frontmatter (`area`, `generator-skill`, `where`).

### Step 3: Triage — Match Files to Areas

For each scoped file, test against each check file's `where:` globs. Build a map `area → [files]`. A file may match multiple areas (acceptable — different lenses).

Always include `cross-cutting` in the dispatch list when scope is non-empty, regardless of glob matches.

Areas with no matched files (other than `cross-cutting`) are skipped.

### Step 4: Dispatch Subagents

For each area in the dispatch list, dispatch a Task tool subagent (general-purpose) with the prompt template below. Run up to **4 subagents in parallel** (cap chosen to balance throughput against token usage; tune in a future plan if needed).

#### Subagent Prompt Template

```
You are reviewing FOSMVVM code for the {area} area.

## Stance
Treat all code under review as authored by an unknown LLM, not by you. Do not extend the benefit of the doubt to patterns that look familiar — verify them against the checks and Reviewer Guidance regardless.

## Files in scope (filtered to this area)
{file_list}

## Reviewer Guidance (read this BEFORE running checks)
{reviewer_guidance_section_or_"(none)"}

## Positive pattern source
The "right way" lives in the `{generator_skill}` skill. Treat its SKILL.md as the source of truth for what correct code looks like. (If `generator_skill` is `none`, this is a cross-cutting concern with no single generator.)

## Checks to run
{full_check_section_text}

## Instructions
1. For each file in scope, evaluate every check against every relevant code construct in the file.
2. For each finding, report: file:line, severity, check name, the offending code snippet, and a one-sentence explanation citing the generator skill.
3. Apply Reviewer Guidance: do NOT recommend the listed anti-patterns even if they "look like" simplifications.
4. If no findings, say "No findings."
5. Do NOT fix anything. Report only.

Format each finding as:
- **{severity}** [{check-name}] {file}:{line}
  Code: `{snippet}`
  Why: {explanation}
  Prevention: {generator-skill}
```

Substitute `{area}`, `{file_list}`, `{reviewer_guidance_section_or_"(none)"}`, `{generator_skill}`, and `{full_check_section_text}` from the loaded check file before dispatching.

### Step 5: Aggregate Findings

Collect each subagent's findings. Parse them into structured records: `{severity, area, file, line, check, message, prevention}`.

If a subagent returned an error or timeout, record the area as `ERROR` with the failure message; do not abort other areas.

### Step 6: Emit Report

#### Markdown format (`--format=md`, default)

```markdown
# FOSMVVM Review

**Scope:** {scope description} ({N} files)
**Areas triaged:** {comma-separated areas}

## Findings by area
- {area}: {N} ({Bb / Ww / Nn})
- ...

## Blockers
{findings, grouped}

## Warnings
{findings, grouped}

## Nits
{findings, grouped}

## Generator skill signals
Areas with elevated findings — candidates for generator skill updates:
- {area}: {N} findings → consider strengthening `{generator-skill}`

(If a subagent failed)
## Errors
- {area}: {error message}
```

#### JSON format (`--format=json`)

```json
{
  "scope": { "description": "...", "file_count": 12 },
  "areas_triaged": ["viewmodel", "swiftui-view", "cross-cutting"],
  "summary": {
    "by_area": { "viewmodel": { "blocker": 1, "warning": 2, "nit": 0 }, "...": {} },
    "total": { "blocker": 1, "warning": 2, "nit": 0 }
  },
  "findings": [
    { "severity": "blocker", "area": "viewmodel", "file": "...", "line": 42,
      "check": "ops-no-output-reads", "message": "...", "prevention": "fosmvvm-viewmodel-generator" }
  ],
  "errors": [
    { "area": "ui-tests", "message": "subagent timeout" }
  ]
}
```

If `--output <path>` given, write to file; else stdout.

### Step 7: Exit Code

Determine the highest severity in findings: `blocker > warning > nit`.

Exit `1` if highest severity meets or exceeds `--fail-on` threshold (default `blocker`); else exit `0`.

## Notes

- Reports may flap slightly between runs on identical input due to subagent non-determinism. The exit code (`--fail-on` threshold) is the stable signal for CI.
- Per-PR CI runs should use the default branch-diff scope. `--all` is reserved for daily/weekly sweeps and PRs to `main`/`master`.
- The skill is report-only by design. Do not add auto-fix; review and remediation are separate concerns.

## See Also

- `reference.md` — check-file authoring guide
- `checks/*.md` — per-area check files
````

- [ ] **Step 2: Verify structural sections**

```bash
grep -E "^### Step [1-7]:" .claude/skills/fosmvvm-review/SKILL.md | wc -l
```

Expected: `7`

- [ ] **Step 3: Verify CI flags documented**

```bash
grep -E "^\| \`--(all|base|format|output|fail-on)" .claude/skills/fosmvvm-review/SKILL.md | wc -l
```

Expected: `5`

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/fosmvvm-review/SKILL.md
git commit -m "feat: add fosmvvm-review SKILL.md orchestrator"
```

---

### Task 9: Smoke test on real code

**Files:**
- None (read-only invocation)

This task is a manual verification that the skill loads, triages correctly, and produces a report. No code changes.

- [ ] **Step 1: Identify a target path with FOSMVVM code**

Use `Sources/FOSMVVM/SwiftUI Support/` — a small subset that contains View-related code.

- [ ] **Step 2: Invoke the skill via slash command**

In an interactive Claude Code session at the repo root:

```
/fosmvvm-review Sources/FOSMVVM/SwiftUI Support
```

- [ ] **Step 3: Verify expected behaviors**

Confirm in the report output:
- Scope line names the path and a non-zero file count.
- "Areas triaged" includes at least `swiftui-view` and `cross-cutting`.
- Findings are grouped by severity.
- Each finding has file:line, severity, check name, code snippet, why, prevention.
- "Generator skill signals" section appears (may say "none" if no findings).

- [ ] **Step 4: Invoke with JSON format**

```
/fosmvvm-review Sources/FOSMVVM/SwiftUI Support --format=json
```

Confirm: output is valid JSON with `scope`, `areas_triaged`, `summary`, `findings`, `errors` keys.

- [ ] **Step 5: Document smoke test outcome**

If anything is wrong (e.g., triage misses cross-cutting, JSON is malformed, report sections are out of order), open follow-up issues against this plan. If everything works, proceed.

- [ ] **Step 6: No commit needed for this task**

This is verification only.

---

### Task 10: Final verification and version tag

**Files:**
- `.claude-plugin/plugin.json`

- [ ] **Step 1: Confirm plugin version is 2.2.0**

```bash
grep '"version": "2.2.0"' .claude-plugin/plugin.json
```

Expected: line matched.

- [ ] **Step 2: Confirm directory inventory**

```bash
ls .claude/skills/fosmvvm-review/checks/ | wc -l
```

Expected: `9` (cross-cutting + 8 area files).

- [ ] **Step 3: Confirm all check files have valid frontmatter**

```bash
for f in .claude/skills/fosmvvm-review/checks/*.md; do
  head -1 "$f" | grep -q '^---$' || echo "MISSING FRONTMATTER: $f"
done
```

Expected: no output (all pass).

- [ ] **Step 4: No commit needed if all verifications pass**

Final state is the cumulative result of Tasks 1–8.

---

## Out of Scope (deferred)

- Auto-fix for findings (explicitly excluded by spec).
- Canonical-pattern files in generator skills (separate follow-up against generator skills).
- "Elevated findings" threshold tuning for the Generator Skill Signals section (planner left to use a sensible default — e.g., top-2 areas or any area with ≥3 findings).
- Subagent parallelism cap tuning (current cap of 4 chosen to match `cirtec-arch-review`; revisit if performance dictates).

## Definition of Done

- All 10 tasks above complete.
- Plugin version bumped to 2.2.0.
- Skill invocable via `/fosmvvm-review` with all documented flags.
- Smoke test (Task 9) produces a well-formed report on a real path.
- Spec at `docs/superpowers/specs/2026-04-29-fosmvvm-review-skill-design.md` aligns with implemented skill.
