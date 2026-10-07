---
status: open
last_updated: 2026-10-06
origin: a consumer's follow-up to the 0.20.1 doctor review (2026-10-06)
---

The doctor's single-embed rule (R5) tells a UI-test bundle to link its local frameworks without embedding them, which is the scaffolder's shape and passes in CI, but in at least one consumer's project removing those embeds stops every UI-test runner from launching on the iOS Simulator.

## Goal

R5's advice for UI-test bundles is correct for every project it fires on: either the precondition that makes link-only work is known and stated (and checked), or the rule stops advising link-only where that precondition does not hold.

Done means: the difference between the scaffolder's UI-test target and the failing shape is identified from real build settings; R5's remedy (or its scope) is changed to match; a doctor test covers the failing shape.

## Input

**The failure (consumer report, 2026-10-06):** iOS 26.5 Simulator, Xcode 26, FOSUtilities 0.20.0. Three UI-test bundles each link app frameworks plus FOSTestingUI, with `TEST_TARGET_NAME` set to the harness app. With the embeds removed, no test runs: "Simulator device failed to launch …xctrunner. The request was denied by service delegate (SBMainWorkspace) for reason: Busy ("Application failed preflight checks")". With only the embeds restored, the runners launch and the tests pass.

**The scaffolder's shape that works** — `Sources/FOSMVVMBootstrap/Templates/client-server/project.yml.tmpl` (around lines 185-215): the UI-test target compiles the shared ViewModels sources in-module, depends on the app target, and links `SPMLibraries` and `<Name>ClientViewModels` with `embed: false`. CI's generated UI-test legs (ServerDemo and LocalDemo, iOS Simulator) pass with it.

**David's ruling, OQ41 (2026-10-06):** link-only for UI-test bundles is doctrine. This item tests whether that holds outside the scaffolder's shape.

**Settings requested from the consumer:** `LD_RUNPATH_SEARCH_PATHS`, each linked framework's `MACH_O_TYPE`, code-signing settings, `TEST_TARGET_NAME`/`TEST_HOST`, the app dependency, and any framework the UI-test target links that the app does not embed.

## Suggested actions

- Compare the consumer's settings with a freshly scaffolded project's, read through Xcode's MCP.
- Find the precondition (likely candidates: a framework the app does not embed, runpath search paths, or signing on the runner).
- Change R5 for UI-test bundles to match: state the precondition in the remedy, check it, or narrow the advice. Bring the outcome to David if it changes OQ41.

## History

- 2026-10-06 — minted from the consumer's follow-up; settings requested.
