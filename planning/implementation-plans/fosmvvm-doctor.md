# `doctor` — implementation plan

**Design:** `docs/work/fosmvvm-doctor-design.md` (RATIFIED 2026-08-23). Names, rule table, severities, and surface are settled there; this plan does not re-open them.

**Shape of the work:** twelve rules, one internal read model, four public names, two front ends. Nothing in the `Emitter` moves.

---

## Two probes came back green before planning

**Foundation parses `project.pbxproj`.** The openStep plist reader handles it, and the object graph is walkable by hand. This is why XcodeProj is a convenience ruling rather than a feasibility one — worth knowing if the dependency ever needs to go.

**XcodeProj models synchronized folders.** `PBXFileSystemSynchronizedRootGroup` carries `exceptions`, `explicitFolders`, and `explicitFileTypes`. This was the real risk: the finishing checklist converts every generated project to synchronized folders, so a reader that could not see them would be blind to exactly the projects doctor exists for.

---

## Stage 0 — wiring

### T1 · Add XcodeProj to the package

`Package.swift:102` already carries a macOS-only dependency block, and `Package.swift:276` already wraps every bootstrap target in the same guard. So the dependency needs no platform condition and the sources need no `#if`.

Add `tuist/XcodeProj` at `.upToNextMajor(from: "9.16.0")` to the block at `:103`, and `.product(name: "XcodeProj", package: "XcodeProj")` to the `FOSMVVMBootstrap` target at `:277`.

**Gate:** `swift build` green; the fast `swift test` suite still green and still fast.

---

## Stage 1 — the read model

### T2 · `AuditedProject`

New file `Sources/FOSMVVMBootstrap/Doctor/AuditedProject.swift`, internal.

This is the seam that keeps twelve rules off XcodeProj's API. It answers exactly the questions the rules ask and nothing more: per target, the name, product type, product name, build settings by configuration, linked package products, linked local targets, and embedded frameworks with their sign-on-copy attribute. Beyond targets, it carries the app entitlements, the `Package.swift` platforms when there is one, the test plans with their referenced target identifiers, and the localization YAML paths.

**The one soft spot is `Package.swift`.** Ruling 2b says declared values, and a manifest is Swift rather than data — so the platforms come from a scan of the `platforms:` array rather than from evaluating the manifest. For a scaffolded project the form is known; for a legacy one it may not be. When the scan cannot make sense of the line, R10 reports a warning saying so rather than passing silently. If the field turns out to vary more than expected, `swift package dump-package` is the fallback, and it is a change to this file alone.

**Gate:** built from a committed fixture, the facts come back right — including one fixture converted to synchronized folders, since that is what a finished project looks like.

---

## Stage 2 — engine and the flat rules

### T3 · `ProjectRule`, `Finding`, `Severity`, `Doctor`

`ProjectRule` internal in `Sources/FOSMVVMBootstrap/Doctor/ProjectRule.swift`; a rule is a summary plus an evaluation over `AuditedProject` returning findings. The table is `ProjectRule.all` — no wrapper type, per the ruling.

`Finding` and `Severity` public in `Sources/FOSMVVMBootstrap/Doctor/Finding.swift`. `Doctor` and `Doctor.Report` public in `Sources/FOSMVVMBootstrap/Doctor/Doctor.swift`, carrying the DocC drafted in the design.

Land R1, R2, and R6 with it — the three flat build-setting rules. They prove the whole path end to end while the machinery is still small enough to change cheaply.

R2 also scans for near-miss spellings of `BUILD_LIBRARY_FOR_DISTRIBUTION` and names them, because a misspelled setting and an absent one are indistinguishable to Xcode and that is the entire point of the rule.

**Gate:** `Doctor.examine` on a clean fixture returns no findings; on a fixture broken three ways it returns three, at error.

---

## Stage 3 — the remaining rules

Each task is a rule group sharing machinery, each with a clean fixture and a deliberately broken one.

### T4 · Link and embed graph — R4a, R4b, R5

The rules the design had to reconcile against the templates. Shipping products only through SPMLibraries; testing products only into test targets; single-embed with sign-on-copy on the app and link-only everywhere else.

### T5 · Test targets — R3, R9

`TEST_HOST` and `BUNDLE_LOADER` on unit-test bundles, exempting UI-test bundles. Test plan target references resolved against real pbxproj targets — the re-minted-UUID trap.

### T6 · Signing and runtime configuration — R11, R12

`CODE_SIGN_STYLE` Automatic; `ENABLE_HARDENED_RUNTIME` off in Debug and on in Release, reported separately when it is off in both.

### T7 · Shape-conditional — R7, R8

These two are the only ones that consult `shape`. Without it they land in `Report.unchecked` rather than being guessed at. R7 is an error, R8 the table's single warning.

### T8 · Deployment floors — R10

The xcodeproj deployment targets against the `Package.swift` platforms, and both against `FOSPlatformFloor.floors` (`Sources/FOSMVVMBootstrap/FOSPlatformFloor.swift:14`). Projects without a root manifest — local-only is one — get the floor half only.

**Gate, each task:** the broken fixture produces exactly the expected finding at the expected severity, and the clean fixtures stay silent.

---

## Stage 4 — front ends

### T9 · CLI subcommand

`Sources/FOSMVVMBootstrapCLI/DoctorCommand.swift`, added to `Main.swift:11` alongside `New.self`.

**The type cannot be named `Doctor`** — it would shadow `FOSMVVMBootstrap.Doctor` in the same file that calls it. `struct DoctorCommand` with an explicit `CommandConfiguration(commandName: "doctor")`, so the user-facing verb is unaffected.

Exit code comes from `Report.hasErrors`, per the ruling.

### T10 · SPM command plugin

`Plugins/FOSMVVMDoctor/plugin.swift`, verb `fosmvvm-doctor`, declared in `Package.swift`. This is the distribution decision the migration design made at §3b — zero installation for anyone already depending on FOSUtilities.

**This task carries the sandbox probe.** Command plugins run sandboxed, and the design's prediction that `xcodebuild -showBuildSettings` would fail there is unverified. Measure it here, while a plugin exists to measure with, and record the answer in the design — it is what a future `--resolved` has to live with.

**Gate:** `swift package fosmvvm-doctor` runs from a throwaway consumer package and reports on it.

---

## Stage 5 — proof and publication

### T11 · Fixture suite

`Tests/FOSMVVMBootstrapTests/Fixtures/` — one clean project per shape plus one broken project per rule, all committed.

**Committed rather than generated, deliberately.** A broken fixture has to stay broken; if it were emitted, fixing the emitter would silently repair it and the test would pass while checking nothing.

Assertions go through `Doctor.examine` only. No `@testable` — the rules and the read model are internal, and everything asserted is reachable from the public surface.

### T12 · Conformance — the test that makes the table truth

Two lines at the end of each existing skeleton in `Tests/FOSMVVMBootstrapTests/IntegrationTests.swift:33`: examine the project that was just emitted and generated, assert no findings.

The skeletons already do the expensive part, so this costs nothing on top. The shared-library skeleton has no `.xcodeproj`, so it exercises the manifest-only path.

**This is the task that discharges ruling 1.** Until it passes, the rules table is a second opinion rather than truth.

### T13 · Docs

`Sources/FOSMVVM/FOSMVVM.docc/CreatingAProject.md:60` currently reads *"A `doctor` command … is planned as an SPM command plugin."* It becomes the real article: what doctor checks, both invocations, and what `--shape` is for.

README gains the diagnose-an-existing-project block beside the create-a-project one. The article stays the single source; README carries the block and a link.

### T14 · Catalog and changelog

Run `fosutilities-api-catalog-update` for the four new public names, and stamp the CHANGELOG.

---

## Risks

**The `Package.swift` platforms scan** is the least certain piece, and T2 states how it fails loudly rather than quietly.

**XcodeProj is on 9.x and actively developed** — 9.16.0 shipped 2026-08-20. Pinned `upToNextMajor`, and it is behind `AuditedProject`, so a breaking change is one file.

**The plugin sandbox is unmeasured.** It does not block v1, because declared-values needs no subprocess. It blocks `--resolved`, which is why T10 measures it now rather than later.

---

## Sequencing note

T1 through T3 are the spine — after them the rule tasks are independent and can land in any order, each with its own fixture. T12 is the one that cannot be skipped: it is the difference between a rules table that is truth and one that is an assertion.
