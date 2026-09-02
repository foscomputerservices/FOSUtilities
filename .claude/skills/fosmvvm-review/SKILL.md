---
name: fosmvvm-review
description: Review FOSMVVM code in two tiers - the deterministic fosmvvm-doctor structural audit first (structural errors halt area review), then per-area check files dispatched one subagent per affected area. Emits one severity-tagged report covering both tiers. Report-only, no auto-fix. Use when reviewing a branch before merge, sweeping the codebase periodically, or in CI.
homepage: https://swiftpackageindex.com/foscomputerservices/FOSUtilities/documentation/fosmvvm
---

# FOSMVVM Code Review

> **Read [`shared/functional-discipline.md`](../shared/functional-discipline.md) before proceeding.** Every rule below derives from it.

Reviews a project in two tiers, one report. **Tier 1** is `fosmvvm-doctor` — the compiled, deterministic audit of project structure (Step 2); structural errors halt everything downstream, because area reviews assume a project shaped the way the scaffolder shapes it. **Tier 2** reviews the Swift sources against the per-area check files in `checks/`. Designed for both interactive use and CI integration.

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
| `--all` | Scope = all reviewable files (`.swift`, `.leaf`, `.tsx`, `.jsx`) under `Sources`, `Tests`, `Resources`. | — |
| `<path>` | Scope = reviewable files under `<path>`. | — |
| `--base <ref>` | Override diff base for default scope. | `main` |
| `--format md\|json` | Report format. | `md` |
| `--output <path>` | Write report to file (else stdout). | stdout |
| `--fail-on blocker\|warning\|nit` | Threshold for non-zero exit code. | `blocker` |

`--all`, `<path>`, and the default branch-diff are mutually exclusive scopes; if multiple are given, error.

## Workflow

### Step 1: Resolve Scope and Load Project Config

**Scope:** reviewable files are `*.swift`, `*.leaf`, `*.tsx`, and `*.jsx` — the view edge has three rendering surfaces, and a Swift-only scope silently exempts the Leaf and React ones.
- If `<path>` given: `find <path> -type f \( -name '*.swift' -o -name '*.leaf' -o -name '*.tsx' -o -name '*.jsx' \)`.
- If `--all`: the same `find` over `Sources Tests Resources` from the repo root (skip `node_modules` and `.build`).
- Else (default): `git diff --name-only <base>...HEAD -- '*.swift' '*.leaf' '*.tsx' '*.jsx'` where `<base>` is `--base` value or `main`.

If the resulting file list is empty:
- Empty diff: print "No changes to review." Exit 0.
- Path with no reviewable files: print "No files in scope at `<path>`." Exit 0.
- `--all` with no files: print "No reviewable files found." Exit 0.

**Project config:**
Look for `.fosmvvm-review.yml` at the repo root. If present, parse:
- `disabled_checks:` — list of check names to skip globally.
- `severity_overrides:` — map of `check-name: severity` (blocker | warning | nit).
- `excluded_paths:` — list of glob patterns; matching files are removed from scope.
- `doctor:` → `disabled_rules:` — list of `{rule, target, reason}` entries disabling one doctor rule for one target, the way SwiftLint's `disabled_rules` names rules (Step 2). `rule` is the identifier doctor prints on the finding (`app_sandbox`), `target` the Xcode target it names, `reason` one sentence. An entry without a reason is malformed. Nested under `doctor:` so it never reads as a sibling of `disabled_checks`, which governs tier 2.

If the file is missing or any key is absent, use defaults. If the file is malformed (invalid YAML, unknown top-level keys), print a warning and continue with defaults.

Apply `excluded_paths` immediately to filter the scoped file list before triage.

### Step 2: Tier 1 — Structural Audit (doctor)

Before any triage, run the deterministic structural audit. `fosmvvm-doctor` checks the project against the scaffolder's rules — build settings, linkage and embedding, test plans, entitlements, deployment floors. Deterministic questions stay in compiled code: this skill never re-derives what doctor already answers.

**How to run it** — first route that applies:

1. The project is a Swift package whose FOSUtilities pin ships the plugin (0.15+): from the repo root, `swift package fosmvvm-doctor --json`, plus `--shape <localOnly|clientServer|sharedLibrary>` when the shape is known. Judge the pin from `Package.resolved` (the resolved version), not the `Package.swift` requirement — `from: "0.14.0"` can resolve past 0.15. When no `Package.resolved` exists yet, try this route and fall through on failure.
2. Otherwise — an Xcode-only project, or a pre-plugin pin — run from a FOSUtilities checkout: `swift run fosmvvm-bootstrap doctor --project <repo-root> --json`, plus the same `--shape` flag when the shape is known (it moves the shape-dependent rules from `unchecked` into the audit). (The checkout is only a host; nothing is written anywhere.)

Both routes exit non-zero when doctor finds errors — capture stdout regardless of exit status (append `|| true`).
3. Neither available (no macOS, no checkout): tier 1 is **unavailable**. Record it as such below and continue to Step 3 — the absence is stated in the report, never silent. Name the enabling route (the `CreatingAProject` DocC article, § Diagnosing an existing project).

**Parse the JSON:** `findings` (each carrying `severity` — `error` | `warning` — an optional `target`, `summary`, `remedy`, and on the few findings a project may disable a `rule` identifier), `unchecked`, and `hasErrors`.

**Apply the project's disabled doctor rules (ruled 2026-09-02).** For each `doctor.disabled_rules` entry, find the doctor finding whose `rule` and `target` both match. A matched finding is reported at `warning` with `disabled: <reason>` beside it, and it no longer counts toward the gate below. An entry that matches no finding, or names a rule doctor did not print on that target, is reported in the Configuration line as unmatched and otherwise ignored — it never silences anything. Only findings that carry a `rule` identifier can be disabled; every other doctor finding is a defect and stays as reported. Recompute the gate from the findings that remain at `error` — not from doctor's own `hasErrors`, which predates the config.

**The gate (ruled 2026-08-25): structural errors halt tier 2.** When any doctor finding remains at `error` after the disabled rules are applied, do not dispatch any area subagent — fix structure first, so that the area reviews find what they expect where they expect. Skip to Step 7 and emit the report now, with:

- the `structure` section carrying every doctor finding and the `unchecked` list,
- `summary.by_area.structure` and `summary.total` counting them (severity mapping: doctor `error` → `blocker`, `warning` → `warning`),
- `"tier2": "halted"` in JSON; in Markdown, a `**Tier 2: halted**` line stating that doctor reported structural errors and area review runs after they are fixed.

When doctor reports only warnings, or nothing: record the results in the same `structure` section and continue to Step 3.

Doctor findings are deterministic facts, not review judgments: `disabled_checks`, `severity_overrides`, and inline suppression do not reach them, and they carry no check names — each finding's `remedy` is the action. The one door is `doctor.disabled_rules`, and it opens only on findings doctor itself marked with a `rule` identifier: the project is recording a choice, with a reason, not overriding a verdict.

### Step 3: Load Check Files

Read all `checks/*.md` from this skill's base directory. Parse YAML frontmatter (`area`, `generator-skill`, `where`).

Apply project config:
- Drop any `## Check: <name>` section whose name appears in `disabled_checks`.
- Override `**Severity:**` lines for checks listed in `severity_overrides`.

### Step 4: Triage — Match Files to Areas

For each scoped file, test against each check file's `where:` globs. Build a map `area → [files]`. A file may match multiple areas (acceptable — different lenses).

Always include `cross-cutting` in the dispatch list when scope is non-empty, regardless of glob matches.

Areas with no matched files (other than `cross-cutting`) are skipped.

### Step 5: Dispatch Subagents

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
3. **Use the file path exactly as provided in "Files in scope"** — repo-relative (e.g., `Sources/FOSMVVM/SwiftUI Support/Text.swift:81`). Do not shorten to the basename. IDEs and CI consumers rely on the path for navigation.
4. **Honor suppression directives.** Before reporting any finding, check for these comment forms:
   - `// fosmvvm-review:disable:next <check-name> — <justification>` on the line directly above the candidate.
   - `// fosmvvm-review:disable:this <check-name> — <justification>` anywhere on the candidate's line.
   - `// fosmvvm-review:disable <check-name>` / `// fosmvvm-review:enable <check-name>` block markers wrapping the candidate.
   If the matching check is suppressed, omit the finding. If a directive matches but has no justification text after the rule name, instead emit a `suppression-without-justification` finding (defined in `cross-cutting.md`).
5. Apply Reviewer Guidance: do NOT recommend the listed anti-patterns even if they "look like" simplifications.
6. **Establish the pinned FOSUtilities version before grading any check that names an API.** A check that says "use `uiTestingElement(_:)`" is not a defect report against a codebase written before that API shipped. Read the pin — and read the right one: an Xcode-project area is governed by `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, which can disagree with the root SPM `Package.resolved`. Where the API postdates the pin, report the finding as **correct at time of writing, now fixable** and say which version lifts it, rather than as an authored defect. Where the pin's own source contradicts a comment in the code under review, the source wins — treat any comment describing framework internals as a claim to verify, not context to trust.
6. **Never invent a check name.** The names above are the complete set for this area. If you find a real violation of the generator skill that no check covers — which will happen, because several areas are thinly covered — report it under the literal check name `uncovered-{area}` and name the generator-skill rule it breaks in the explanation. Do NOT coin a plausible-sounding name: check names are a stable contract that suppression directives, `.fosmvvm-review.yml`, and CI gates all address by name, and a fabricated one silently belongs to no rule and cannot be configured, suppressed, or trusted to reappear on the next run.
7. **Grade an `uncovered-{area}` finding on the same severity scale as the named checks** — blocker when it breaks at runtime, warning when it degrades the development experience. The absence of a check is not itself a severity.
8. If no findings, say "No findings."
9. Do NOT fix anything. Report only.

If you emitted any `uncovered-{area}` findings, end your report with a section titled `## Coverage gap` listing, one line each, the rule the check file should encode to catch them next time. This is the signal that the area needs checks written — say it plainly rather than papering over it with names that look official.

Format each finding as:
- **{severity}** [{check-name}] {repo-relative-path}:{line}
  Code: `{snippet}`
  Why: {explanation}
  Prevention: {generator-skill}
```

Substitute `{area}`, `{file_list}`, `{reviewer_guidance_section_or_"(none)"}`, `{generator_skill}`, and `{full_check_section_text}` from the loaded check file before dispatching.

### Step 6: Aggregate Findings

Collect each subagent's findings. Parse them into structured records: `{severity, area, file, line, check, message, prevention}`.

If a subagent returned an error or timeout, record the area as `ERROR` with the failure message; do not abort other areas.

### Step 7: Emit Report

#### Markdown format (`--format=md`, default)

```markdown
# FOSMVVM Review

**Scope:** {scope description} ({N} files)
**Tier 1 (doctor):** {ran | unavailable — reason and the enabling route}
**Tier 2:** (only when halted) halted — doctor reported structural errors; fix structure first, then re-run
**Areas triaged:** {comma-separated areas, or "none — tier 2 halted"}
**Fail-on threshold:** {threshold}
**Configuration applied:** (omit line if no config) disabled checks: {names}; severity overrides: {name=severity, ...}; excluded paths: {N}; doctor disabled rules: {N} ({M} unmatched: {rule@target, ...})

## Structure (doctor)
(omit the section when tier 1 ran clean with nothing unchecked)
- {❌ error | ⚠️ warning} {target or (project)}: {summary} → {remedy}
- ⚠️ {target}: {summary} — disabled ({rule}): {reason}   (a disabled doctor rule, reported at warning)
- Not checked: {each unchecked entry, one line}

## Findings by area
- structure: {N} ({Bb / Ww}) (present when doctor reported anything; doctor error → blocker, warning → warning)
- {area}: {N} ({Bb / Ww / Nn})
- ...

## Blockers
{tier-2 findings, grouped}

## Warnings
{tier-2 findings, grouped}

## Nits
{tier-2 findings, grouped}

(The Blockers/Warnings/Nits sections carry **tier-2 findings only** — the markdown mirror of the JSON rule that tier-1 findings never enter `findings[]`. Doctor's full detail lives in the Structure section; its counts appear in "Findings by area" under `structure`. On a halted run the Structure section is the whole story and the tier-2 sections are empty.)

## Coverage gaps
(omit the section when there are no `uncovered-*` findings)
Real violations no check covers — these areas need checks written:
- {area}: {N} uncovered ({M} of them blockers) → rules to encode: {one line each}

## Generator skill signals
Areas with elevated findings — candidates for generator skill updates:
- {area}: {N} findings → consider strengthening `{generator-skill}`

(If a subagent failed)
## Errors
- {area}: {error message}
```

`uncovered-*` findings count toward the severity totals like any other — a real
blocker is a blocker whether or not someone had written the check yet. The
separate section exists so the *gap* stays visible rather than dissolving into
the general finding list, and so a run against a thinly-covered area cannot be
mistaken for a clean one.

#### JSON format (`--format=json`)

```json
{
  "scope": { "description": "...", "file_count": 12 },
  "tier1": "ran",
  "tier2": "ran",
  "structure": {
    "findings": [
      { "severity": "error", "target": "SPMLibraries", "summary": "...", "remedy": "..." },
      { "severity": "warning", "target": "PalettePress", "summary": "...", "remedy": "...",
        "rule": "app_sandbox", "disabled": "Talks to the local Docker socket." }
    ],
    "unchecked": ["entitlements match the project shape (needs --shape)"]
  },
  "areas_triaged": ["viewmodel", "swiftui-view", "cross-cutting"],
  "config": {
    "fail_on": "blocker",
    "disabled_checks": ["..."],
    "severity_overrides": { "<check>": "<severity>" },
    "excluded_paths_count": 0,
    "doctor_disabled_rules": { "applied": 1, "unmatched": [] }
  },
  "summary": {
    "by_area": { "structure": { "blocker": 1, "warning": 0, "nit": 0 }, "viewmodel": { "blocker": 1, "warning": 2, "nit": 0 }, "...": {} },
    "total": { "blocker": 2, "warning": 2, "nit": 0 },
    "uncovered": { "viewmodel": 3, "swiftui-app-setup": 5 }
  },
  "findings": [
    { "severity": "blocker", "area": "viewmodel", "file": "...", "line": 42,
      "check": "ops-no-output-reads", "message": "...", "prevention": "fosmvvm-viewmodel-generator" },
    { "severity": "warning", "area": "viewmodel", "file": "...", "line": 88,
      "check": "uncovered-viewmodel", "message": "...", "prevention": "fosmvvm-viewmodel-generator" }
  ],
  "coverage_gaps": [
    { "area": "viewmodel", "count": 3, "rules_to_encode": ["vmId derivation on list rows", "..."] }
  ],
  "errors": [
    { "area": "ui-tests", "message": "subagent timeout" }
  ]
}
```

`summary.uncovered` lets a CI wrapper track whether coverage is improving —
`jq '.summary.uncovered | add // 0'` trending down means checks are being
written. Gate on it only deliberately: a thinly-covered area reports a high
number through no fault of the code under review.

There is **one summary**: doctor findings count in `summary.by_area.structure`
and in `summary.total` alongside every other area (doctor `error` → `blocker`,
`warning` → `warning`), so the CI contract — `jq '.summary.total.blocker == 0'`
— covers both tiers without forking. `tier1` is `"ran"` or
`"unavailable: <reason>"`; `tier2` is `"ran"` or `"halted"`. When halted,
`areas_triaged` is empty, `findings` carries no tier-2 records, and the
`structure` section is the whole story. The full doctor detail (targets,
remedies, unchecked) lives only in `structure` — tier-1 findings do not appear
in the `findings[]` array, which remains check-name-addressable tier-2 records.

If `--output <path>` given, write to file; else stdout.

### Step 8: Annotate Failure Threshold

The skill runs inside Claude Code and cannot directly control the shell exit code. Instead, record the configured `--fail-on` threshold in the report so out-of-process wrappers can translate findings to exit codes:

- **Markdown report:** include a `**Fail-on threshold:** {threshold}` line in the header.
- **JSON output:** include a top-level `"config": { "fail_on": "<threshold>", ... }` field (already present per the JSON schema in Step 7).

CI consumers invoke the skill via `claude -p` and parse the JSON to decide whether to fail the build:

```bash
claude -p "/fosmvvm-review --format=json --fail-on=blocker" > review.json
jq -e '.summary.total.blocker == 0' review.json > /dev/null || exit 1
```

The skill does not ship a wrapper script — each consuming repo writes its own to fit its CI runner.

## Project Configuration

Repos may provide an optional `.fosmvvm-review.yml` at the repo root to customize the skill's behavior.

```yaml
# Globally silence checks (no findings emitted, even without inline directives)
disabled_checks:
  - ops-not-async-unless-needed

# Override default severity per check
severity_overrides:
  ops-output-param-last: nit         # default warning
  no-silent-failure: warning         # default blocker

# Skip files entirely (applied AFTER glob matching, before subagent dispatch)
excluded_paths:
  - "Sources/Generated/**"
  - "Tests/Fixtures/**"
```

All keys are optional. Missing or malformed file → defaults are used and a warning is printed.

**Precedence:** inline `// fosmvvm-review:disable:*` directives > `.fosmvvm-review.yml` > defaults from check files.

The "Configuration applied" line in the report makes any active overrides visible at every run.

## Suppression

Findings can be suppressed inline when intentional. SwiftLint-compatible syntax:

```swift
// fosmvvm-review:disable:next no-silent-failure — preview-only fallback, no production path
let value = (try? something()) ?? "default"

let other = (try? bar()) ?? "" // fosmvvm-review:disable:this no-silent-failure — closure binding intentionally swallows
```

Block scope:

```swift
// fosmvvm-review:disable no-silent-failure
... multiple lines ...
// fosmvvm-review:enable no-silent-failure
```

**Justification is required.** A suppression without text after the check name produces a `suppression-without-justification` finding (warning). This forces explicit documentation of every silenced check.

## Coverage state

The coverage ledger's register is closed — every gap it identified has a shipped check (most recently G22–G26 in 2.62.0). As of plugin 2.62.0:

- **Covered:** `cross-cutting` (20 checks), `viewmodel` (13), `view` (9 — multi-surface: SwiftUI/Leaf/React), `serverrequest` (9), `swiftui-app-setup` (6), `datamodel` (5), `viewmodel-test` (5), `ui-tests` (4), `fields` (4), `serverrequest-test` (2).
- **Retired:** `viewmodelrequest`. The rule set names `ServerRequest`, not `ViewModelRequest` — the latter is a `ShowRequest` specialization, so its wire contract is `serverrequest`'s and the VM↔Request pairing is `viewmodel`'s (`viewmodel-request-pairing`).

Violations no check covers still surface as `uncovered-{area}` findings rather than under invented names, so any remaining gap shows up in every report instead of hiding behind official-looking labels — an `uncovered-*` finding is now also a signal that the coverage ledger (`coverage-ledger.md`, beside the checks) may need a new entry.

## Notes

- Reports may flap slightly between runs on identical input due to subagent non-determinism. The exit code (`--fail-on` threshold) is the stable signal for CI.
- A check name is a contract. Suppression directives, `.fosmvvm-review.yml`, and CI gates all address checks by name, so names must come from the check files and nowhere else — see the `uncovered-{area}` rule in the subagent prompt.
- Per-PR CI runs should use the default branch-diff scope. `--all` is reserved for daily/weekly sweeps and PRs to `main`/`master`.
- The skill is report-only by design. Do not add auto-fix; review and remediation are separate concerns.

## See Also

- `reference.md` — check-file authoring guide
- `checks/*.md` — per-area check files
