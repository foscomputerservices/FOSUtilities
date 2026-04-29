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
3. **Use the file path exactly as provided in "Files in scope"** — repo-relative (e.g., `Sources/FOSMVVM/SwiftUI Support/Text.swift:81`). Do not shorten to the basename. IDEs and CI consumers rely on the path for navigation.
4. **Honor suppression directives.** Before reporting any finding, check for these comment forms:
   - `// fosmvvm-review:disable:next <check-name> — <justification>` on the line directly above the candidate.
   - `// fosmvvm-review:disable:this <check-name> — <justification>` anywhere on the candidate's line.
   - `// fosmvvm-review:disable <check-name>` / `// fosmvvm-review:enable <check-name>` block markers wrapping the candidate.
   If the matching check is suppressed, omit the finding. If a directive matches but has no justification text after the rule name, instead emit a `suppression-without-justification` finding (defined in `cross-cutting.md`).
5. Apply Reviewer Guidance: do NOT recommend the listed anti-patterns even if they "look like" simplifications.
6. If no findings, say "No findings."
7. Do NOT fix anything. Report only.

Format each finding as:
- **{severity}** [{check-name}] {repo-relative-path}:{line}
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

## Notes

- Reports may flap slightly between runs on identical input due to subagent non-determinism. The exit code (`--fail-on` threshold) is the stable signal for CI.
- Per-PR CI runs should use the default branch-diff scope. `--all` is reserved for daily/weekly sweeps and PRs to `main`/`master`.
- The skill is report-only by design. Do not add auto-fix; review and remediation are separate concerns.

## See Also

- `reference.md` — check-file authoring guide
- `checks/*.md` — per-area check files
