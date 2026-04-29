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

Triage-then-dispatch: scoped files are matched to areas via per-file globs, then one subagent runs per matched area in parallel. See "Triage Logic" below for the step-by-step.

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

## Authoring Style (check files and Reviewer Guidance)

Code under review may be authored by any LLM (Claude, GPT, Gemini, etc.) — each with its own drift patterns. Check files and Reviewer Guidance must be **model-agnostic**:

- Describe **the code pattern and why it's wrong** architecturally — never the author's tendencies.
- Anti-patterns describe **shapes** (read-modify-write on outputs, env mutation in views, silent swallows), not authorship.
- Reviewer Guidance describes **what NOT to recommend** with architectural reasons, never "because LLM X reaches for this."

`reference.md` will enforce this style in the check-file authoring template.

## Subagent Framing (Anti-Bias)

LLMs reviewing their own work tend to extend leniency to familiar patterns. To remove self-recognition bias, the subagent prompt explicitly frames the code under review as foreign:

> Treat all code under review as authored by an unknown LLM, not by you. Do not extend the benefit of the doubt to patterns that look familiar — verify them against the checks and Reviewer Guidance regardless.

This is not deception — it's a calibration instruction. The reviewer's job is rigor; framing the code as foreign keeps it rigorous.

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

## Stance
Treat all code under review as authored by an unknown LLM, not by you. Do not extend the benefit of the doubt to patterns that look familiar — verify them against the checks and Reviewer Guidance regardless.

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

## CI Integration

The skill is expected to run in CI as well as interactively. Required affordances:

- **Exit code policy.** Exit `1` if any finding meets or exceeds the configured threshold; exit `0` otherwise. `--fail-on=blocker|warning|nit` configures the threshold; default is `blocker`.
- **Machine-readable output.** `--format=md|json` flag. Markdown is the default (interactive use). JSON mirrors the report structure: array of findings with `severity`, `area`, `file`, `line`, `check`, `message`, `prevention`, plus a top-level summary object.
- **Configurable base branch.** `--base <ref>` flag controls the diff base; defaults to `main`. CI on PRs targeting `develop` or release branches sets this to the merge target.
- **Output destination.** `--output <path>` flag writes the report to a file for CI artifact upload; default is stdout.
- **Headless-friendly.** No interactive prompts at any point in the skill flow. The skill is already report-only with no auto-fix prompts; the planner must preserve this.

**Recommended CI cadence.** Per-PR runs use the default branch-diff scope (fast, cheap, focused on what's about to land). `--all` is reserved for periodic sweeps — daily/weekly cron runs and PRs targeting `main`/`master`.

## Project Configuration (`.fosmvvm-review.yml`)

Repos consuming the skill may provide an optional `.fosmvvm-review.yml` at the repo root. Mirrors `.swiftlint.yml` convention — CI consumers find it without flags.

### Schema

```yaml
# Globally silence checks (no findings emitted, even without inline directives)
disabled_checks:
  - <check-name>

# Override default severity per check (blocker | warning | nit)
severity_overrides:
  <check-name>: <severity>

# Skip files entirely (applied AFTER glob matching, before subagent dispatch)
excluded_paths:
  - "<glob>"
```

All three keys are optional. Missing file → use defaults from check files.

### Precedence

Inline directives take precedence over config; config takes precedence over defaults:

1. **Inline `// fosmvvm-review:disable:*`** — strongest, scoped to a line/block.
2. **`.fosmvvm-review.yml`** — repo-wide globals.
3. **Default severities and enablements** from check files.

### Final Report Disclosure

The final report includes a "Configuration applied" line listing globally disabled checks and severity overrides, so suppressions are visible at every review run.

### Out of Scope (v1)

- Per-area sub-configs (e.g., `per_area: { ui-tests: { disabled_checks: [...] } }`). Add when global form proves too coarse.
- Custom check files in consuming repos. Canonical check files only.
- Threshold tuning ("only flag if N occurrences").

## Suppression

Some findings are intentional. The skill supports SwiftLint-compatible suppression directives in source comments:

- `// fosmvvm-review:disable:next <check-name> — <justification>` — suppresses the named check on the line below.
- `// fosmvvm-review:disable:this <check-name> — <justification>` — suppresses the named check on the same line (anywhere on that line).
- `// fosmvvm-review:disable <check-name>` ... `// fosmvvm-review:enable <check-name>` — block scope.

**Justification is required.** A suppression without text after the rule name is itself a finding (`suppression-without-justification`, severity `warning`, defined in `cross-cutting.md`). Suppressions without reasons become invisible tech debt; the requirement forces explicit documentation.

Subagents evaluate suppressions per check: when a candidate finding's line is covered by a suppression directive for that check (with justification), the finding is omitted from the report.

## Edge Cases

- **Empty diff** (branch matches main): print "No changes to review" and exit.
- **Path arg doesn't exist or matches no `.swift` files**: print "No files in scope at `{path}`" and exit.
- **No matched areas**: print "No FOSMVVM-area files in scope" and exit. Cross-cutting still runs if scope is non-empty.
- **Stub check files**: subagent reports "no checks defined for this area; positive pattern lives in `{generator-skill}`." Not a failure.
- **Glob ambiguity** (file matches multiple areas): file appears in each matched subagent's scope; same finding may be reported by multiple subagents. Acceptable — different lenses.
- **Subagent failure** (timeout, error): aggregate report notes the area as `ERROR`; other areas continue.
- **Determinism caveat.** Subagent dispatch is not perfectly deterministic — finding counts may flap slightly between runs on identical input. CI consumers should not assume bit-exact reproducibility; the exit-code threshold (`--fail-on`) is the stable signal.

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
