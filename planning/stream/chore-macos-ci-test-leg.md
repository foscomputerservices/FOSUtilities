---
status: open
last_updated: 2026-10-18
origin: David, 2026-10-17, during the DataFetch streaming review (OQ20), on learning CI runs no package tests on macOS
---

CI runs the package's tests on Linux only. Every test that exists only on Apple platforms has only ever run on a developer's Mac, and one of those suites fails intermittently.

## Goal

Every package test target runs in CI on macOS, and the leg is reliable enough to gate a merge.

Done means: `ServerBindHostedTests` no longer fails intermittently, and a macOS CI leg runs every package test target on each pull request.

## Input

**The gap:** `.github/workflows/ci.yml:285`, from `9bc21a9` (2025-01-06, "No idea why macOS hangs ... moving on for now"), only builds on macOS. Its comment says `swift test` hung on the runners. The only `swift test` in CI is the Linux leg, `ci.yml:213`.

**Never run in CI:** `Tests/FOSMVVMTests/SwiftUI Support/` (11 files, `ServerBindHostedTests` among them), `FOSTestingUITests`, `FOSReportingTests`, the macro tests under `#if`, `MutualTLSSessionTests`, and the Apple-only tests in `DataFetchStreamTests`.

**A sign it can work:** the scaffolder fast suite already runs `xcodebuild test -scheme FOSUtilities-Package -only-testing:FOSMVVMBootstrapTests` on `macos-26` (`ci.yml:497`).

**The intermittent:** in full `FOSMVVMTests` runs, about one in twenty fails a `ServerBindHostedTests` test in `waitUntil` (`Tests/FOSMVVMTests/SwiftUI Support/ServerBindHostedTests.swift:342`, expectation at `:349`). The failing test varies: `clearingTheFailure_fetchesExactlyOnceMore` on `feat/datafetch-streaming`, `invalidationDuringALoad_fetchesAgain` on `origin/main` `8e0ada3`. Run alone 50 times, it passed every time. Unverified suspects: the 5 s budget (500 spins of 10 ms) under a parallel run, the shared `Harness.current` static (`:271`), and layout of a window that is not key.

## Suggested actions

1. Reproduce the intermittent under instrumentation, find its cause, and fix it.
2. Try a macOS leg that runs all package test targets through `xcodebuild test` against `FOSUtilities-Package`, and see whether the 2025 hang remains.
3. Bring the leg's design, its run time, and any targets that cannot run there to David; David rules before it gates merges.

## History

- 2026-10-17 — Opened at David's request (OQ20); not scheduled.
- 2026-10-18 — Intermittent's cause found: `DeploymentTests` overrode the process-wide `Deployment.current` (and `FOS-DEPLOYMENT`) while a hosted test loaded, so the load failed with "Missing deployment configuration for production" (7 of 60 full `FOSMVVMTests` runs). Fixed by gating `DeploymentTests` under the shared trait, renamed `.processWideState` (OQ1, OQ2), which now restores the deployment after each test (OQ3): 0 of 60, and 10 of 10 full `xcodebuild test` runs green on fos-dev. The work item's three suspects were not the cause.
- 2026-10-18 — On fos-dev (macOS 27.0.1, Xcode 27.0), `xcodebuild test -scheme FOSUtilities-Package` ran all 8 package test targets on unfixed `main` with no hang: 1,405 passed, 1 failed (the intermittent), 3 skipped (bootstrap `IntegrationTests`), 55 s of testing, 170 s cold.
- 2026-10-18 — Trial on GitHub `macos-26` (Xcode 26.6), branch-only workflow `macos-test-trial.yml`, three jobs side by side (run 39131086173): all three green, 1,322 tests each (1,319 passed, 3 skipped bootstrap `IntegrationTests`), all 8 targets ran, no hang; the test step took 6 m 46 s, 9 m 9 s and 10 m 25 s, build included.
- 2026-10-18 — Leg added to `ci.yml` as "Test macOS packages" (OQ17): `build test` of the package scheme on `macos-26`/Xcode 26.6, no xcpretty (OQ19), result bundle uploaded on failure, a `record_green` need; it replaces the "Build macOS (Debug)" leg (OQ18). No check is required on `main`, so it gates like every other leg (OQ20 withdrawn). Trial workflow removed.
