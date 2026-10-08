---
status: in progress
last_updated: 2026-10-08
origin: David, 2026-10-08, from the PR #167 CI run's annotations ("For the next work item after this PR merges, is there any way to resolve these warnings?")
---

A CI run on PR #167 shows 29 warnings and 17 notices, none from the code under test. Two causes account for the warnings seen: GitHub actions pinned to versions that run on the deprecated Node.js 20, and Homebrew reporting on preinstalled runner packages during the format-and-lint job.

## Goal

A green CI run shows no warnings, and any notice left is one we chose to keep.

## Input

**Node.js 20 deprecation**, per the annotations ("The following actions target Node.js 20 but are being forced to run on Node.js 24"; https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/). Uses in `.github/workflows/ci.yml` (2026-10-08):

- `actions/checkout@v4`: 8 uses
- `actions/checkout@v2`: 4 uses
- `actions/cache/restore@v4`, `actions/cache/save@v4`: 1 each
- `maxim-lobanov/setup-xcode@v1`: 7 uses (not yet confirmed as Node 20)
- `SwiftyLab/setup-swift@latest`: 2 uses (not yet confirmed)

**Homebrew noise** in the "Format and lint" job: "Skipping glib: most recent version 2.90.1 not installed" and similar lines for git, gh, cryptography, cmake, cairo, ca-certificates, bicep and aws-sam-cli, plus "Treating azure-cli as a formula…". The step, `ci.yml:156-163`:

```yaml
      # `brew install` leaves a preinstalled older formula alone, and the
      # ...
      # `brew upgrade` makes latest mean latest on every runner.
          brew update
          brew install swiftformat swiftlint
          brew upgrade swiftformat swiftlint
```

The step's comment records why it upgrades (an older preinstalled SwiftFormat once broke CI); keep that guarantee.

**The notices** (second screenshot, 2026-10-08):

- "The ubuntu-latest label will migrate to Ubuntu 26 beginning October 19, 2026" (https://github.com/actions/runner-images/issues/14748), on the jobs that run on `ubuntu-latest` (Detect code changes, Test Swift v6.3.2). Actionable and dated: the Linux legs change OS on the 19th with no change of ours, and the Swift setup action's support for Ubuntu 26 is unconfirmed. Ruled 2026-10-08 (OQ23, revised, David: "let's move as far forward as possible, no need to keep the old"): move the Linux jobs to Ubuntu 26 now (`ubuntu-26.04`, or the newest label GitHub offers), with no Ubuntu 24 leg kept. Confirm the Swift setup action supports it. Before October 19, 2026.
- "Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times." GitHub's status message; nothing to fix; the notice we keep.
- Confirm no other notice kinds among the 17.

**Swift on Ubuntu 26 (research 2026-10-08, sources in the session report):** swift.org publishes no 6.3.x toolchain for Ubuntu 26.04 (`releases.json`: 6.3–6.3.3 list Ubuntu 22.04 and 24.04 only; the 6.3.2 `ubuntu2604` tarball 404s). Swift 6.4.0 (2026-09-14) supports Ubuntu 26.04 (`resolute`), Docker `swift:6.4.0-resolute`. The `ubuntu-26.04` runner is GA (runner-images #14747). Ruled OQ24 (David: "Container is fine"): run the Linux jobs in the official container instead of a setup action; SwiftyLab was chosen only because it was quick to hand-write.

## Suggested actions

1. Read every annotation of the latest run (warnings and notices) and group them by cause.
2. Bump each action to the release that runs on Node 24, confirming that release for each one.
3. Make the Homebrew step touch only SwiftFormat and SwiftLint while still guaranteeing the latest versions; confirm which Homebrew setting silences which message.
4. Move every `ubuntu-latest` job to Ubuntu 26 (OQ23) with Swift 6.4.0 run in the official `swift:6.4.0-resolute` container, replacing `SwiftyLab/setup-swift` (OQ24). Confirm the package builds and tests on Linux with 6.4 before relying on it. Before October 19, 2026.
5. Confirm on a CI run that no warnings remain; list any notice kept and why.

## History

- 2026-10-08 — Opened at David's direction, to start right after PR #167 merges.
- 2026-10-08 — Built on `chore/ci-warnings`. Annotations of the full run 37793923225 grouped: 17 Node 20 warnings (checkout@v2/@v4, cache/restore@v4), 10 Homebrew warnings (the automatic `brew cleanup` after install, and the azure-cli formula-to-cask migration, both over preinstalled formulae), 1 SwiftyLab cache-reservation warning, 1 overload-sweep floor warning (a documented deferral in `docs/deferrals.md`, out of scope here), 18 notices (macOS capacity, kept; Ubuntu 26 migration), 16 cancellations from a superseded run. Changes: checkout@v7 and cache@v6 (both Node 24; v7's fork-PR block does not affect our `pull_request` / `workflow_dispatch` triggers); linters from the latest SwiftFormat/SwiftLint release binaries instead of Homebrew; Linux jobs on `ubuntu-26.04` in `swift:6.4.0-resolute`, SwiftyLab removed; the two remaining `ubuntu-latest` jobs on `ubuntu-26.04`. `main` requires no status checks, so the renamed Linux jobs block nothing. Linux build on 6.4 not yet proven: Docker is not running locally; the PR's CI run is the first proof.
