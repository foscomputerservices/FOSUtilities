# fosmvvm-review Skill — Design

**Date:** 2026-04-29
**Status:** Approved (pending spec review)
**Plugin:** `fosmvvm-generators` (bump 2.1.0 → 2.2.0)

## Purpose

A code review skill for FOSMVVM codebases that complements the existing `fosmvvm-*-generator` family. Where generators encode the positive pattern ("here's how to write a ViewModel correctly"), this skill encodes review-only knowledge: anti-patterns, drift signals, common mistakes, and reviewer-mindset guidance the generators don't ship.

The end-state goal is for findings to atrophy as generator skills mature. High finding counts in any area signal that the corresponding generator skill needs strengthening upstream — review becomes a rubber stamp once generators steer Claude correctly the first time.

## Identity & Location

- **Name:** `fosmvvm-review`
- **Invocation:** users type `/fosmvvm-review` (optionally with `--all` or a path); Claude resolves it through the Skill tool. No separate command file.
- **Location:** `.claude/skills/fosmvvm-review/` in the FOSUtilities repo (part of the `fosmvvm-generators` plugin).
- **Plugin version bump:** 2.1.0 → 2.2.0 (per the "bump plugin version when updating skill documentation" lesson).

## Source-of-Truth Strategy

Hybrid:
- The corresponding `fosmvvm-<area>-generator` skill remains the source of truth for the **positive pattern**.
- Each per-area check file in this skill adds **review-only content**: anti-patterns, drift signals, detection heuristics, reviewer-mindset guidance.
- Frontmatter `generator-skill:` pointer makes the link explicit and machine-readable.

## Scope (Default + Args)

- No args → `git diff --name-only main...HEAD` (current branch's changes vs main). **This is the default.**
- `--all` → full codebase scan (all `.swift` files under `Sources/` and `Tests/`).
- `<path>` → scoped to a file or directory.

## Dispatch Model

Triage-then-dispatch:

1. Resolve scope into a file list.
2. Load all check files; parse `where:` globs from frontmatter.
3. Match files to areas. A file may match multiple areas.
4. Always include `cross-cutting.md` if scope is non-empty.
5. Dispatch one subagent per matched area, max 4 in parallel.
6. Skip areas with no matched files (except cross-cutting).

## Output Shape

Report-only with severity tags (blocker / warning / nit). No auto-fix. Each finding cites the generator skill that should have prevented it. Summary surfaces "areas with elevated findings" as a feedback signal for generator skill investment.

## Directory Layout

```
.claude/skills/fosmvvm-review/
  SKILL.md                    # entry point: triage + dispatch + report
  reference.md                # check-file schema and authoring guide
  checks/
    fields.md
    serverrequest.md
    swiftui-app-setup.md
    swiftui-view.md
    ui-tests.md
    viewmodel.md
    viewmodel-test.md
    viewmodelrequest.md
    cross-cutting.md          # always triggers; spans all areas
```

All 9 check files exist on day one. Most start as stubs (frontmatter + pointer to corresponding generator skill + zero checks). Triage is structurally complete; depth grows over time as drift is discovered in real reviews. Check files are hand-edited markdown — no companion generator skill.

## Check File Schema

Each file has YAML frontmatter and a markdown body.

### Frontmatter

```yaml
---
area: viewmodel
generator-skill: fosmvvm-viewmodel-generator
where:
  - "Sources/**/ViewModels/**/*.swift"
  - "Sources/**/*ViewModel.swift"
---
```

- `area` — short identifier (matches filename stem).
- `generator-skill` — the positive-pattern source of truth.
- `where` — globs the triage layer matches against changed files.

### Body Sections

**`## Reviewer Guidance` (optional, but load-bearing where present)**

Free-form meta-instructions read by the subagent BEFORE running checks. Contains anti-recommendations, mental-model corrections, and reviewer-mindset guards. This catches reviewer drift the way feedback memories catch it for general sessions, but scoped to the area subagent. Examples:

- "Do NOT recommend collapsing env/VM read-write splits to simplify code. The split is required for test host injection."
- "Do NOT treat `@Observable` classes as substitutable for structs. They have different functional contracts."
- "Re-projection happens at the top of the subtree that owns `bind(appState:)`. Do not propose moving projection edges."

**`## Check: <name>` (zero or more)**

Each check has:

- **Severity:** blocker | warning | nit
- **What:** one-sentence description of the rule.
- **Anti-pattern:** what the wrong code looks like.
- **Detection:** how the subagent identifies hits — grep targets, semantic checks, conditions for a true positive.

Example:

```markdown
## Check: ops-no-output-reads
**Severity:** blocker
**What:** Operations methods must not read from the same mutable state they write to.
**Anti-pattern:** Reading `electrodes[index].polarity` then writing `settings.selectedPolarity = ...` in the same method.
**Detection:** For each type conforming to `*ViewModelOperations`, read each method body. Flag methods that both READ from and WRITE to `settings.*` (or other mutable parameter) within the same call.
```

### Stub Form

Stub check files contain frontmatter, the "positive pattern lives in `<generator-skill>`" sentence, and zero checks. Triage still routes to them; the subagent reports "no checks defined yet."

## Triage Logic (SKILL.md responsibilities)

1. **Resolve scope** from args.
2. **Load check files** — read all `checks/*.md`; parse frontmatter.
3. **Match files to areas** — each scoped file tested against each check file's `where:` globs. Multi-area matches are allowed.
4. **Always include `cross-cutting.md`** if scope is non-empty.
5. **Dispatch subagents** — one per matched area, max 4 in parallel.
6. **Skip empty areas** — areas with no matched files are not dispatched (cross-cutting excepted).

## Subagent Prompt Template

```
You are reviewing FOSMVVM code for the {area} area.

## Files in scope (filtered to this area)
{file list}

## Reviewer Guidance (read this BEFORE running checks)
{Reviewer Guidance section verbatim, if present}

## Positive pattern source
The "right way" lives in the {generator-skill} skill. Treat its
SKILL.md and any canonical-pattern.md as the source of truth for
what correct code looks like.

## Checks to run
{full body of check file, all ## Check: entries}

## Instructions
1. For each file in scope, evaluate every check.
2. For each finding, report: file:line, severity, check name, the offending code, and a one-sentence explanation citing the generator skill.
3. Apply Reviewer Guidance: do NOT recommend the listed anti-patterns even if they "look like" simplifications.
4. If no findings, say "No findings."
5. Do NOT fix anything. Report only.

Format each finding as:
- **{severity}** [{check-name}] {file}:{line}
  Code: `{snippet}`
  Why: {explanation}
  Prevention: {generator-skill}
```

## Final Report Format

```markdown
# FOSMVVM Review

**Scope:** {scope description} ({N} files)
**Areas triaged:** {comma-separated area list}

## Findings by area
- {area}: {N} ({blockers}b / {warnings}w / {nits}n)
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
```

The "Generator skill signals" section is the feedback-loop hook: it makes "where should we invest in generator skills?" visible at every review.

## Edge Cases

- **Empty diff** (branch matches main): print "No changes to review" and exit.
- **No matched areas**: print "No FOSMVVM-area files in scope" and exit. Cross-cutting still runs if scope is non-empty.
- **Stub check files**: subagent reports "no checks defined for this area; positive pattern lives in `{generator-skill}`." Not a failure.
- **Glob ambiguity** (file matches multiple areas): file appears in each matched subagent's scope; same finding may be reported by multiple subagents. Acceptable — different lenses.
- **Subagent failure** (timeout, error): aggregate report notes the area as `ERROR`; other areas continue.

## Initial Check Content

The plan that follows this design will populate (at minimum) these checks based on scenarios collected during brainstorming:

**`viewmodel.md`:**
- `ops-no-output-reads` (blocker) — Operations don't read from outputs they mutate.
- `ops-not-async-unless-needed` (warning) — `async throws` ops with no `await` in body.
- `ops-output-param-last` (warning, clientHostedFactory only) — output param last and labeled `output:`.
- `appstate-no-observable-args` (blocker) — `bind(appState: .init(...))` arguments must be plain values, not `@Observable` types.

**`swiftui-view.md`:**
- `view-reads-vm-only` (blocker) — view bodies read display data from VM, not `@Environment` shadowed by VM.
- `view-no-env-mutation` (blocker) — view bodies do not mutate `@Observable` state directly; ops do.
- `view-no-read-through-vm-ref` (warning) — VM may hold `@Observable` ref for ops dispatch but views must not read through it.
- **Reviewer Guidance:** do NOT recommend removing `@Environment` from views to "simplify"; do NOT recommend collapsing env/VM splits — the split is required for test host injection.

**`ui-tests.md`:**
- `testhost-mirrors-vm-settings` (blocker) — test host blocks construct env state from the VM stub's settings, not from independent `.stub()` calls.

**`cross-cutting.md`:**
- `no-silent-failure` (blocker) — `try?` near async, empty catches, defer-only error paths that swallow errors.

Other check files (`fields.md`, `serverrequest.md`, `swiftui-app-setup.md`, `viewmodel-test.md`, `viewmodelrequest.md`) start as stubs and grow as drift is discovered.

## Out of Scope

- **Auto-fix.** Review is report-only.
- **Generator skill updates.** Findings may signal generator skills need strengthening, but updating them is a separate task tracked outside this skill.
- **Canonical-pattern files in generator skills.** Worth pursuing as a separate follow-up against the generator skills, but not required for this skill to function.

## Open Questions

None at design time. Implementation plan will follow.
