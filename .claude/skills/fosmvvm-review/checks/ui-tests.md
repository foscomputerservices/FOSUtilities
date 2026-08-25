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
- **`uiTestingElement(_:)` ships in FOSUtilities 0.12.0.** Below that pin the raw accessors were the only option: report them as *correct at time of writing, now fixable*, naming the version that lifts it — not as authored defects. Read the pin from the **xcodeproj's** `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, which governs the UI-test target and can disagree with the root SPM one.
- **There may be no `TestConfiguration` type in the repo at all.** Where the checks below say "thread it through `TestConfiguration`", that is the shape to build, not a file to find — the closure form is `.testHost { testConfiguration, testView in … }`, and the payload carries the VM stub's state into the env. Say so plainly rather than pointing at something that does not exist.
- Test host blocks must mirror production binding. In production, `bind(appState: .init(...))` projects the data store into the VM. In tests, `TestConfiguration` is the analogue — it must construct env state from the VM stub's settings, not from independent `.stub()` calls.

## Check: testhost-mirrors-vm-settings
**Severity:** blocker
**What:** Test host blocks must construct `@Observable` env state from the VM stub's settings, not from independent `.stub()` calls. The env and the VM must hold the same instance, mirroring production binding.
**Anti-pattern:** `let env = ProgrammingSettings(patientRight: .stub())` in a test host while the injected VM holds a different `PatientPanelSettings` instance — taps mutate one, the View reads the other, the test fails for an incorrect reason. Equally a hit, and worse: an env holding a **live production** object, `LocalDockStore(prober: LocalDockOps())`, injected at App scope with no relationship to the stub.

**Where to look when the app uses the plain `.testHost()`.** The env-construction site is often not in a UI test file at all — it is the app's `@main`, injected on the `WindowGroup`. A reviewer searching only the test target reports "nothing found" and is wrong. The tell is structural, **graded by what the environment holds** (ruled 2026-08-25 — the seam arrives with the App State): plain `.testHost()` plus a registered test view reading a **project-authored `@Observable`** (`.environment(appState)`) is the finding — the hosted view reads app state no test can reach, and the decorator + a real `TestConfiguration` should have arrived with that injection. When the only environment is the framework's (`MVVMEnvironment`), plain `.testHost()` is the correct baseline — at most note the latent shape (a stub that ever stops discarding the env would do real work against the production URLs). Broaden past `.stub()` — the anti-pattern is *any* env construction not derived from the VM stub, and a live production object is the most dangerous form because it will do real work. A payload-free `TestConfiguration` no test constructs is the same ruling's other half: a dead seam, flagged as scaffolding noise rather than wired transport.

**Grade latent and active differently, and say which.** A divergence where the stub ops ignores the env, and the view happens to render only from the VM, breaks nothing today — the first test that asserts on env state hits it. Report the tier: `blocker` when a test fails or does real work now, `warning` when it is latent, and in both cases name what will trip it. Do not flatten the two; whoever triages the list needs the difference.
**Detection:** Find blocks named `testHost`, `setUp`, or `presentView` in UI test files. For each construction of `@Observable` env state, verify it threads through the VM stub's settings (typically via `TestConfiguration` payload). Flag env constructions that use `.stub()` independent of the VM.

## Check: elements-reached-by-identifier
**Severity:** blocker
**What:** Tagged views are reached with `uiTestingElement(_:)`, never through XCUITest's element-type accessors.
**Anti-pattern:** `app.buttons["saveButton"].tap()` · `app.staticTexts["title"].label` · `app.otherElements["banner"].exists`
**Detection:** In UI test sources, flag reads or gestures that go through `app.buttons`, `app.staticTexts`, `app.otherElements`, `app.textFields`, and their siblings, for a view the app tags with `uiTestingIdentifier`. This includes the laundered form — a `private extension XCUIApplication` vending `var someTitle: XCUIElement { staticTexts.element(matching: .staticText, identifier: "…") }`. Wrapping the type query in a computed property does not remove the type query; it hides it from a grep and leaves the coupling in place. An accessor keyed on an element type bakes a rendering detail into the test: the test breaks when a `Button` becomes a `Menu`, which is a change with no behavioural meaning. `uiTestingElement(_:)` is keyed on the identifier alone and survives it.

There is a second reason, and it is the one that costs afternoons. A gesture against an identifier no view carries fails the test *naming that identifier*, so a typo reads as a typo. The same typo through `app.buttons[…]` surfaces as an XCUITest snapshot error about an element that does not exist, which reads like a timing or hierarchy problem and gets debugged as one.

A raw accessor is legitimate for something FOSMVVM does not tag — a system alert, a share sheet, a keyboard key. Do not flag those; flag the ones reaching a view the app itself tagged.

## Check: harness-merges-every-yaml-bundle
**Severity:** blocker
**What:** A view-test harness localizing from more than one target's YAML uses the multi-bundle `setUp(bundles:)` form.
**Anti-pattern:** A harness calling the single-bundle `setUp(bundle:)` in an app whose ViewModels are localized from two places — its own YAML plus another target's — so half the strings resolve and half fall back.
**Detection:** Two failures, and they present in opposite ways.

**Some of the bundles (N of M) → silent.** Strings from the unmerged bundle resolve to their fallback, so the test asserts against a key or an English default and passes. Read for it; running proves nothing.

**None of them (0 of M) → loud.** When the passed bundle contains no YAML at all, `yamlStoreConfig` throws `noResourcePaths` and `setUp` dies before any test body runs. The whole harness is dead rather than quietly wrong.

**Check that the YAML physically reaches the bundle — do not stop at the call shape.** `bundle: Bundle(for: Self.self)` is a perfectly correct call that resolves nothing if the test target copies no resources. The failure is one layer down, in the Xcode target's wiring. Open the target's `PBXResourcesBuildPhase` and its synchronized groups, and settle it definitively against the built product: `find …/SomeUITests.xctest -name '*.yml'`. That takes five seconds and is the only answer that cannot be argued with.

Then, for each `ViewModelViewTestCase` / `ViewModelDisplayTestCase` harness, determine how many bundles carry YAML for the ViewModels it drives. In a client-server app that is routinely two: the client framework's own resources and the server-side contract's. Flag a harness passing one bundle where the ViewModels it exercises span several.

`setUp(bundles:resourceDirectoryName:appBundleIdentifier:locales:)` merges them into one store (FOSTestingUI, 0.13.2); `loadLocalizationStore(bundles:)` is the FOSTesting equivalent. Before that release the single-bundle form was the only option and harnesses worked around the gap — a symlinked `Resources` directory in the test target is the usual tell, and is worth reporting as the workaround it now is.

The symptom is not a failure. Strings from the unmerged bundle resolve to their fallback, so the test asserts against a key or an English default and passes — which is why this is worth catching by reading rather than by running.


## Check: no-hand-rolled-element-helpers
**Severity:** warning
**What:** Tests use the verified interaction APIs rather than re-implementing them.
**Anti-pattern:**
```swift
extension XCUIElement {
    var text: String? { value as? String }
    func typeTextAndWait(_ string: String, timeout: TimeInterval = 2) { … }
    func tapMenu() { … }
}
```
**Detection:** Flag `XCUIElement`/`XCUIApplication` extensions re-implementing what `uiTestingElement(_:)` already vends — `text` for `.value`, `typeTextAndWait`/`selectTypeTextAndWait` for `.setText(_:)`, `tapMenu` for `.tap()`, hand-rolled `waitFor…` loops for `waitForExistence()`. These are the cases the verified APIs were written to absorb, including the keyboard-occlusion and menu-dismissal handling a hand-rolled version will not have.

**Check whether the helpers are used before grading.** An unused helper set is dead code, which lowers the severity but not the finding: it sits in the test target as a template, and the next author writes against it.

**A hand-rolled wait is not automatically a hit.** The verified APIs poll *UI elements*. A test polling something else — a transported operations stub, an out-of-process side effect — has no verified equivalent to reach for, and that is a gap in the framework rather than a defect in the test. Say which you are looking at; if it is the framework gap, report it as one so it can be closed upstream.
