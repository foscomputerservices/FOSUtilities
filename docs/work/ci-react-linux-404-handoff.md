# RESOLVED: PR #103 Linux CI failure — `reactResourcesServed()` 404s

**Status:** root cause found and fixed in
`Tests/FOSMVVMVaporTests/Extensions/Application+FOSTests.swift` (uncommitted at time of
writing). macOS local: green. Awaiting Linux CI confirmation on the branch.

## Actual root cause — a test-boot race, NOT a serving/bundling bug
`reactResourcesServed()` booted the Vapor app in a **background task** and waited a fixed
`sleep(1)` before issuing requests:
```swift
Task { try await app.execute() }   // execute() → startup() → asyncBoot() → willBootAsync
sleep(1)                            // hope boot finished
```
The FileMiddleware for `/fosmvvm/react/*` is registered by
`YamlLocalizationInitializer.willBootAsync` (→ `configureFOSMVVMReactResources()`). That is an
**async** lifecycle handler, so it only runs via `asyncBoot()`. `app.test(...)` internally runs
only the **synchronous** `boot()` (see `VaporTesting/TestingApplicationTester.testing()` →
`try self.boot()`), which fires `willBoot`/`didBoot` but **never `willBootAsync`** — hence the
background `execute()` + `sleep(1)` was the *only* thing registering the middleware.

Under this PR the FOSMVVMVaporTests process grew from **323 tests / 40 suites** to
**330 tests / 44 suites** (+4 suites from `ReplaceRequestTests`,
`SynthesizedStubWitnessTests`, `VersionedBaselinePathTests`, `ViewModelStubMacroTests`). The
extra parallel-suite contention on the Linux runner pushed background boot past the 1s window,
so requests hit an app whose FileMiddleware wasn't registered yet → **all 4 files 404**.

The serving code, `Package.swift`, and the resource files are **byte-identical** to the green
commit `138e2cb` (PR #98 run 28583310138, ubuntu 6.2.1 PASS). The PR changed the *timing* this
latent race depended on, not the serving logic.

## The fix
Replace the background-boot race with a foreground, awaited boot:
```swift
try await app.asyncBoot()   // runs willBootAsync → registers FileMiddleware, synchronously
```
`asyncBoot()` is idempotent (`isBooted`-guarded), so the sync `boot()` inside `app.test(...)`
no-ops. No server bind (test tester defaults to `.inMemory`), no `sleep`, no race. Local run
drops from ~2s to 0.016s and logs confirm `willBootAsync` ("Serving FOSMVVM client resources
from: …") fires *before* the first GET.

## Why the earlier hypotheses were all wrong
- **`.gitignore` (commit 82fb579):** the 4 react files are **tracked** and **not ignored** by
  the new `Tests/**/.VersionedTestJSON/*` pattern → present on any fresh checkout. Ruled out.
- **Linux bundle-probe in `configureFOSMVVMReactResources`:** proven-good on Linux at
  `138e2cb`/`d2ff98e` (both ubuntu PASS). The probe was never the problem; the middleware just
  hadn't been registered yet when requests were sent.
- **"pre-existing / not this PR":** it *was* introduced by this PR's timing shift, but as a
  race exposure, not a logic regression.

## Empirical evidence (for the record)
- Run 28583310138 (PR #98, `138e2cb`, 10:39): `reactResourcesServed()` ✔ PASS, all 200.
- Run 28618417621 (this PR, `768a554`, 20:24): ✘ FAIL, all 404, "6 issues incl. 2 known"
  (the 4 non-known = the 4 react 404s; 2 known = unrelated `loadCSVData`).
- CI runs on `pull_request`/`workflow_dispatch` only — `main` is never directly tested, so
  "main was green on Linux" only ever meant "some PR's merge commit was green."

## Also pending on this branch (unrelated to CI, already decided)
- Stub-placement skill fix (SKILL.md Stubbable Pattern + reference.md Templates 2/4/Dashboard
  CardViewModel) + CHANGELOG baseline-path migration note — DONE in working tree, uncommitted.
  These were to land as a new commit once CI direction was settled. That's now settled.
