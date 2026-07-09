# SwiftUI Localizable Overload Sweep — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A maintainer-run Swift script that sweeps the SwiftUI/SwiftUICore
symbol graphs and generates FOSMVVM's complete `Localizable` overload
surface, replacing the seven hand-written mirror locations.

**Architecture:** Six-stage pipeline (Extract → Select → Union →
Transform → Emit → Verify) in one sectioned script,
`Scripts/localizable-overload-sweep.swift`, zero dependencies, decoding
`swift-symbolgraph-extract` JSON with `Codable`. Generated sources are
checked in under `Sources/FOSMVVM/SwiftUI Support/Generated/`; skipped
candidates are logged in a checked-in `SweepCoverage.md`. Version
identity is per-platform SDK versions, never Xcode's.

**Tech Stack:** Swift 6, Foundation only (script); Swift Testing
(behavioral tests); GitHub Actions (staleness gate).

**Spec:** `docs/superpowers/specs/2026-07-09-swiftui-localizable-overload-generator-design.md`
— read it first; it is the source of truth for every rule referenced
below. This plan resequences the spec's migration (relocate → generate
→ swap-delete) so the build stays green at every commit; the spec's
constraint (relocate before delete) is preserved.

---

## File structure

| Path | Role |
|---|---|
| `Scripts/localizable-overload-sweep.swift` | The generator (new; sectioned by pipeline stage) |
| `Sources/FOSMVVM/SwiftUI Support/Generated/*.swift` | Generated overloads, one file per extended type (new; machine-owned) |
| `Sources/FOSMVVM/SwiftUI Support/SweepCoverage.md` | Coverage manifest (new; machine-owned) |
| `Sources/FOSMVVM/SwiftUI Support/LocalizableViews.swift` | Relocated hand-written survivors (new) |
| `Sources/FOSMVVM/SwiftUI Support/Text.swift` | DELETED after relocation + swap |
| `Sources/FOSMVVM/SwiftUI Support/{Label,LabeledContent,Tab,ContentUnavailableView,TextField}.swift` | DELETED at swap |
| `Sources/FOSMVVM/SwiftUI Support/View.swift` | `navigationTitle` mirror removed; everything else untouched |
| `Package.swift` | `exclude` entry for `SweepCoverage.md` in the FOSMVVM target |
| `Tests/FOSMVVMTests/SwiftUI Support/GeneratedOverloadTests.swift` | Behavioral contract tests (new) |
| `.github/workflows/ci.yml` | Staleness-gate job (new job appended) |
| `.claude/skills/shared/api-catalog/FOSMVVM.md` | One family entry, § SwiftUI Support |
| `CHANGELOG.md` | Unreleased entry (breaking: `defaultTitle:` → `defaultValue:`, `any` → `some`) |

**Branch:** all work on `spec/localizable-overload-sweep` (repo
convention), PR to `main` only after David's review gate.

---

## Rationale notes for the implementer (not DocC material)

- **Why the script never emits on doubt:** a wrong overload is public
  API shipped to every FOSMVVM consumer. Skip + manifest beats guess.
- **Why delegate-by-name works without pinpointing the exact sibling:**
  the emitted body calls `self.init(...)`/`method(...)` with a `String`
  argument; the compiler's overload resolution picks Apple's
  `StringProtocol` variant. Sibling matching is only a *gate* to avoid
  emitting calls with no target; the CI compile is the real verifier.
  Recursion is impossible: our overloads take `some Localizable`, and
  `String` is not `Localizable`.
- **Why variadic-parameter candidates are skipped:** Swift cannot
  forward a variadic argument list to another variadic parameter.
  Closed-set reason: `unrecognized-shape`.
- **swiftformat interaction:** the repo's swiftformat config inserts
  the Apache header as the *first* comment block. The script must emit
  that header itself (byte-identical to what swiftformat would insert)
  and place the DO-NOT-EDIT stamp as a *second* comment block, so a
  swiftformat pass is a no-op. Acceptance for Task 7 includes
  swiftformat idempotence.
- **`defaultedLocalizedString` stays `internal`**
  (`Sources/FOSMVVM/Localization/Localizable.swift:65`) — generated
  files are in the same module. Do not widen access.
- **Memory strategy:** decode one platform×module graph at a time;
  run Select during decode; discard everything else before loading the
  next graph (multi-GB working set otherwise).

---

### Task 0: Branch

**Files:** none

- [ ] **Step 1:** `git checkout -b spec/localizable-overload-sweep`
- [ ] **Step 2:** Confirm clean: `git status` → nothing to commit

---

### Task 1: Relocate hand-written survivors (build stays green)

**Files:**
- Create: `Sources/FOSMVVM/SwiftUI Support/LocalizableViews.swift`
- Modify: `Sources/FOSMVVM/SwiftUI Support/Text.swift`

Move — verbatim, no edits beyond the move — from `Text.swift` into the
new `LocalizableViews.swift`:

1. `public extension Localizable { var text: some View ... }` (Text.swift:50-54)
2. `private struct LocalizableResolverView<L: Localizable>: View { ... }` (Text.swift:56-104)
3. The optional-Localizable init `init(_ localizable: (some Localizable)?, defaultValue: String? = nil)` (Text.swift:45-47) — it mirrors nothing in SwiftUI (no optional-key inits exist) and stays hand-written per spec.

`Text.swift` keeps (for now) only the non-optional mirror init; it is
deleted in Task 8. `LocalizableViews.swift` needs the same imports as
`Text.swift` (`FOSFoundation`, `#if canImport(SwiftUI) import SwiftUI`)
and the Apache header (run `swiftformat .`).

- [ ] **Step 1:** Create the file, move the three items, leave `Text.swift` compiling with just the plain mirror init.
- [ ] **Step 2:** `swift build --target FOSMVVM` → succeeds
- [ ] **Step 3:** `swift test --filter FOSMVVMTests` → green
- [ ] **Step 4:** Commit: `refactor(FOSMVVM): relocate Localizable resolution machinery to LocalizableViews.swift`

---

### Task 2: Script skeleton + Extract stage

**Files:**
- Create: `Scripts/localizable-overload-sweep.swift`

Follow `Scripts/api-catalog-audit.swift` conventions (top-of-file
usage comment, Apache header, `import Foundation`, runs via
`swift Scripts/localizable-overload-sweep.swift`). No shebang.

CLI surface (parse from `CommandLine.arguments` by hand, as the audit
script does):

```
swift Scripts/localizable-overload-sweep.swift [flags]
  --check           regenerate to a temp dir and diff against checked-in
                    output; exit 1 on drift (used by CI)
  --filter <Type>   process only symbols whose extended type == <Type>
                    (debugging affordance)
  --keep-graphs     leave extracted JSON in the temp dir and print its path
```

Extract stage:

```swift
// MARK: - Stage 1: Extract

struct PlatformSDK {
    let platform: String       // "macosx", "iphoneos", "appletvos", "watchos", "xros"
    let target: String         // "arm64-apple-macos15.0", "arm64-apple-ios17.0", ...
    let version: String        // from `xcrun --sdk <p> --show-sdk-version`
    let path: String           // from `xcrun --sdk <p> --show-sdk-path`
}

let requiredSDKs = ["macosx", "iphoneos", "appletvos", "watchos", "xros"]
let modules = ["SwiftUI", "SwiftUICore"]
```

- Resolve all five SDKs first. **Any missing → print exactly which and
  `exit(1)`** (spec: no partial-platform generation).
- For each SDK × module: run
  `xcrun swift-symbolgraph-extract -module-name <m> -target <t> -sdk <path> -output-dir <tmp>/<platform>/`
  via `Process`. Collect main graphs *and* `<m>@*.symbols.json`
  extension graphs.
- Record each SDK's version string — this is the run's identity stamp.
- Print a one-line summary per graph: platform, module, byte size.

- [ ] **Step 1:** Write the section with CLI parsing + Extract.
- [ ] **Step 2:** Run: `swift Scripts/localizable-overload-sweep.swift --keep-graphs` → summary lists ≥ 10 graphs across 5 platforms; SDK versions printed.
- [ ] **Step 3:** Temporarily rename one SDK dir? — do NOT; instead verify the missing-SDK path with `xcrun --sdk madeupos --show-sdk-version` behavior stubbed in a code path review. (Manual verification; the hard-exit is trivially inspectable.)
- [ ] **Step 4:** Commit: `feat(scripts): overload sweep — extract stage`

---

### Task 3: Codable models + Select stage

**Files:**
- Modify: `Scripts/localizable-overload-sweep.swift`

```swift
// MARK: - Symbol graph model (subset we consume)

struct SymbolGraph: Decodable {
    let symbols: [Symbol]
    let relationships: [Relationship]
}

struct Symbol: Decodable {
    struct Identifier: Decodable { let precise: String }
    struct Kind: Decodable { let identifier: String }   // "swift.init" | "swift.method" | "swift.func" | ...
    struct Fragment: Decodable {
        let kind: String            // "typeIdentifier" | "externalParam" | "text" | ...
        let spelling: String
        let preciseIdentifier: String?
    }
    struct Availability: Decodable {
        struct Version: Decodable { let major: Int; let minor: Int?; let patch: Int? }
        let domain: String?
        let introduced: Version?
        let deprecated: Version?
        let obsoleted: Version?
        let isUnconditionallyDeprecated: Bool?
        let isUnconditionallyUnavailable: Bool?
    }
    struct SwiftExtension: Decodable {
        struct Constraint: Decodable { let kind: String; let lhs: String; let rhs: String }
        let extendedModule: String?
        let constraints: [Constraint]?
    }
    let identifier: Identifier
    let kind: Kind
    let pathComponents: [String]        // ["Text", "init(_:tableName:bundle:comment:)"]
    let declarationFragments: [Fragment]?
    let availability: [Availability]?
    let swiftExtension: SwiftExtension?
    let accessLevel: String?
}

struct Relationship: Decodable {
    let kind: String                    // "memberOf" | "extensionTo" | ...
    let source: String
    let target: String
    let targetFallback: String?         // "SwiftUICore.Text"
}
```

Selection rule (spec Stage 2), applied per graph during decode:

```swift
let localizedStringKeyUSR = "s:7SwiftUI18LocalizedStringKeyV"

func isCandidate(_ s: Symbol) -> Bool {
    guard ["swift.init", "swift.method", "swift.func"].contains(s.kind.identifier),
          s.accessLevel == "public",
          let frags = s.declarationFragments,
          // parameter position: a typeIdentifier fragment for LocalizedStringKey
          frags.contains(where: { $0.preciseIdentifier == localizedStringKeyUSR }),
          !s.pathComponents.contains(where: { $0.hasPrefix("_") }),
          !isDeprecatedOrObsoleted(s.availability)
    else { return false }
    return true
}
```

`isDeprecatedOrObsoleted`: true if any availability entry has
`isUnconditionallyDeprecated`, `deprecated`, or `obsoleted` set.
Every rejected candidate that matched the LocalizedStringKey test but
failed a later clause is retained (USR + reason) for the manifest.

**Caution (verify while implementing):** `LocalizedStringKey`'s USR may
differ now that it lives in SwiftUICore (`s:11SwiftUICore…`). Do not
hardcode blindly — locate the `LocalizedStringKey` type symbol in the
graphs first and take its USR from there; fail loudly if not found.

- [ ] **Step 1:** Write models + Select; wire per-graph streaming (decode → select → discard).
- [ ] **Step 2:** Run with `--filter Text` → prints candidate list including `init(_:tableName:bundle:comment:)`-style inits.
- [ ] **Step 3:** Run unfiltered → total candidate count printed; expect same order of magnitude as the probe (thousands pre-dedup across platforms) and post-filter counts per kind.
- [ ] **Step 4:** Commit: `feat(scripts): overload sweep — symbol models + select stage`

---

### Task 4: Union + availability merge + floor clamp

**Files:**
- Modify: `Scripts/localizable-overload-sweep.swift`

- Merge candidates across platforms by USR into one record with a
  per-domain availability map (`iOS`, `macOS`, `macCatalyst`, `tvOS`,
  `watchOS`, `visionOS`).
- A domain seen in a platform's graph without an `introduced` version =
  available since forever → treated as at-floor.
- Floors (from Package.swift): iOS 17, macOS 14, macCatalyst 17,
  tvOS 17, watchOS 10, visionOS 1. Clamp: `introduced <= floor` ⇒ drop
  from the emitted annotation; all domains dropped ⇒ no annotation.
- `isUnconditionallyUnavailable` domains ⇒ `@available(<domain>, unavailable)` lines.
- Flag `beta-tier` when a domain's `introduced` equals that platform's
  SDK version *and* the SDK version string marks a beta/major ahead of
  the current release train (implementable as: introduced == SDK
  version; the flag is informational only).

- [ ] **Step 1:** Implement union + merge + clamp.
- [ ] **Step 2:** Run `--filter TextField` → the `selection:` init shows `@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)` + tvOS/watchOS unavailable (cross-check against `TextField.swift:130-132` before it is deleted).
- [ ] **Step 3:** Run `--filter Text` → the basic init shows NO annotation (pre-floor).
- [ ] **Step 4:** Commit: `feat(scripts): overload sweep — union and availability clamping`

---

### Task 5: Extended-type resolution + sibling index + delegate policy

**Files:**
- Modify: `Scripts/localizable-overload-sweep.swift`

**Extended type:** `pathComponents.dropLast()` names the extended type
(`["Text", "init(...)"]` → `Text`; `["View", "navigationTitle(_:)"]` →
`View`). Extension constraints come from the `swiftExtension` mixin
(e.g. `Label` members carry `Title == Text, Icon == Image`). Nested
types (`dropLast()` count > 1) → join with `.`.

**Sibling index:** while decoding each graph, also index NON-candidate
public inits/methods by `(extendedType, pathComponents.last!)` — i.e.
same name, same arity-labels. For a candidate, a **String sibling**
exists when an indexed sibling's fragments have, at the
LocalizedStringKey parameter position(s), `some StringProtocol` (or a
generic constrained to `StringProtocol`); a **Text sibling** when the
position holds `Text`. Position comparison is by external parameter
labels, not fragment offsets.

**Delegate policy (spec Stage 4):**
1. String sibling → direct delegation.
2. Else Text sibling → wrap: `Text(verbatim: <resolved>)`.
3. Else → skip, manifest reason `no-delegate-target`.

Variadic parameter anywhere in the candidate → skip,
`unrecognized-shape` (cannot forward variadics in Swift).

- [ ] **Step 1:** Implement type resolution, sibling index, policy classification.
- [ ] **Step 2:** Run summary: counts per policy path printed; `navigationTitle` classifies as policy 1. Spot-check one policy-2 and one skipped candidate and record them for Task 6's golden checks.
- [ ] **Step 3:** Commit: `feat(scripts): overload sweep — sibling matching and delegate policy`

---

### Task 6: Transform stage

**Files:**
- Modify: `Scripts/localizable-overload-sweep.swift`

Signature rewrite over `declarationFragments` (work on the fragment
array, not regex over joined text):

- Fragment run for each LocalizedStringKey **parameter type** →
  replace with `some Localizable`.
- After each replaced parameter, insert
  `, defaultValue: String? = nil` (unnamed slot) or
  `, default<CapitalizedLabel>: String? = nil` (labeled slot).
- Copy verbatim: `nonisolated`, generic parameter lists, `where`
  clauses, default arguments, attributes (`@ViewBuilder`, `@escaping`),
  return types.
- Body:
  - init-shaped: `self.init(<resolved>, <passthrough args>)`
  - method-shaped: `<name>(<resolved>, <passthrough args>)`
  - `<resolved>` = `localizable.defaultedLocalizedString(defaultValue: defaultValue)`
    (or the `default<Label>`-named parameter for labeled slots), wrapped
    in `Text(verbatim: ...)` on policy path 2.
  - passthrough: every other parameter forwarded by label
    (`prompt: prompt`), including defaulted ones.
- Any fragment shape the rewriter does not recognize → skip the
  candidate, `unrecognized-shape`, with the raw declaration in the
  manifest. **Never emit a guess.**

- [ ] **Step 1:** Implement transform.
- [ ] **Step 2 (golden check):** `--filter Label` printed output matches the hand-written `Label.swift:26-46` shape (modulo DocC + `defaultValue` position); diff by eye.
- [ ] **Step 3 (golden check):** `--filter View` output contains a `navigationTitle(_ localizable: some Localizable, defaultValue: String? = nil) -> some View` delegating by method call.
- [ ] **Step 4:** Commit: `feat(scripts): overload sweep — transform stage`

---

### Task 7: Emit stage + manifest + Package.swift exclude

**Files:**
- Modify: `Scripts/localizable-overload-sweep.swift`
- Modify: `Package.swift` (FOSMVVM target: add `exclude` for `SwiftUI Support/SweepCoverage.md`)
- Create (generated): `Sources/FOSMVVM/SwiftUI Support/Generated/*.swift`, `Sources/FOSMVVM/SwiftUI Support/SweepCoverage.md`

File layout per generated file:

```swift
// <TypeName>.swift
//
// Copyright 2026 FOS Computer Services, LLC
// <exact Apache header block the repo's swiftformat config emits>

// GENERATED FILE — DO NOT EDIT
// Generated by Scripts/localizable-overload-sweep.swift
// SDKs: macosx <v> | iphoneos <v> | appletvos <v> | watchos <v> | xros <v>
// Xcode <v> (informational)
// Regenerate: swift Scripts/localizable-overload-sweep.swift

#if canImport(SwiftUI)
import SwiftUI

public extension <TypeName> <constraints> {
    /// Localizable-accepting form of SwiftUI's `<TypeName>.<title>`.
    ///
    /// ## Example
    /// ```swift
    /// <one concrete example — full example on the file's first overload,
    ///  one-liner on the rest>
    /// ```
    /// - Parameters:
    ///   - localizable: The ``Localizable`` to display.
    ///   - defaultValue: Fallback text used if localization did not complete.
    <overload>
}
#endif
```

- Group overloads by extended type; one file per type; members sorted
  by USR (determinism). Multiple constraint-sets on one type → multiple
  `extension` blocks in the same file.
- Availability annotation (from Task 4) directly above each overload.
- `SweepCoverage.md`: header with the same SDK stamp, then sections per
  closed-set reason (`deprecated`, `no-delegate-target`,
  `unrecognized-shape`), one line per skipped USR with its declaration
  title; `beta-tier` flags listed in their own section. Sorted. Nothing
  silently dropped.
- `--check` mode: emit to temp dir; byte-compare against checked-in
  `Generated/` + `SweepCoverage.md`; nonzero exit + file list on drift.

- [ ] **Step 1:** Implement emit + manifest + `--check`.
- [ ] **Step 2:** Run the script for real. `Generated/` populates; skim `Text.swift`, `View.swift` outputs.
- [ ] **Step 3:** `swiftformat .` → **zero changes in `Generated/`** (idempotence acceptance). If it rewrites anything, fix the emitter, not the config.
- [ ] **Step 4:** `swift Scripts/localizable-overload-sweep.swift --check` → exit 0. Touch one generated file, re-run → exit 1 naming it; revert.
- [ ] **Step 5:** Commit (script + Package.swift only — generated output lands with the swap): `feat(scripts): overload sweep — emit, manifest, --check`

---

> **Execution amendments (2026-07-09, from Task 7):**
> 1. Generated files are named `<Type>+Localizable.swift` — SwiftPM
>    refuses two same-basename files in one target, and the hand-written
>    `View.swift` survives forever.
> 2. The plain non-optional `Text(_ localizable:defaultValue:)` init is
>    NOT generated (Apple's LSK Text init is
>    `init(_:tableName:bundle:comment:)`; bundle-lookup params have no
>    meaning for pre-localized strings → honest no-delegate-target
>    reject). Step 1a relocates it to `LocalizableViews.swift` as a
>    hand-written survivor, joining its optional sibling, with a comment
>    stating why. Only then is `Text.swift` deleted.
> 3. Sibling matching now decodes the `swiftGenerics` mixin
>    (declaration-level constraints) — the first real compile exposed
>    delegates to more-constrained siblings; fixed reject-only.

### Task 8: The swap (delete mirrors, build green)

**Files:**
- Delete: `Label.swift`, `LabeledContent.swift`, `Tab.swift`, `ContentUnavailableView.swift`, `TextField.swift`, `Text.swift` (all in `SwiftUI Support/`; `Text.swift` only after Step 1a)
- Modify: `View.swift` — remove ONLY the `navigationTitle` overload, DocC + func (View.swift:38-57). Line 37 (`public extension View {`) MUST stay — `invalidateBinding` and `refreshedViewModel` live in that same extension block. `withValidations` and the `EnvironmentValues` entry also stay.
- Add: everything under `Generated/` + `SweepCoverage.md`

- [ ] **Step 1a:** Relocate the non-optional `Text` init (with its DocC) from `Text.swift` into `LocalizableViews.swift`, commented as a deliberate hand-written survivor.
- [ ] **Step 1:** Delete/trim per the file list. **Do not touch `LocalizableViews.swift`** (beyond Step 1a's addition).
- [ ] **Step 2:** `swift build` → fix any in-repo call sites that used retired spellings. No `defaultTitle:` callers exist in `Sources/`; the realistic risk is `any` → `some` inference at the ~13 `TextField(` call sites in `FormFieldView.swift`.
- [ ] **Step 3:** `swift test` → full suite green on macOS.
- [ ] **Step 4:** `xcrun xcodebuild` iOS-simulator build (mirror the ci.yml invocation) → compiles. This is the first proof the availability matrices are coherent on a non-macOS platform.
- [ ] **Step 5:** Commit: `feat(FOSMVVM)!: generated Localizable overload surface replaces hand-written mirrors`

---

### Task 9: Behavioral contract tests

**Files:**
- Create: `Tests/FOSMVVMTests/SwiftUI Support/GeneratedOverloadTests.swift`

Contract-only (no `@testable` for these; construct via public API;
`Text` is `Equatable` — assert behavior, never generated text):

```swift
// Policy path 1 (String sibling): a localized Localizable renders its value
@Test func textOverloadUsesLocalizedValue() throws {
    let localizable = /* localized LocalizableString via existing test YAML store —
                         follow the construction pattern in existing FOSMVVMTests
                         localization tests */
    #expect(Text(localizable) == Text(verbatim: try localizable.localizedString))
}

// defaultValue contract: pending (un-localized) value falls back
@Test func textOverloadFallsBackToDefaultValue() {
    let pending = LocalizedString(/* pending, not encoded */)
    #expect(Text(pending, defaultValue: "fallback") == Text(verbatim: "fallback"))
}

// Policy path 2 (Text sibling): pick one generated policy-2 overload
// (recorded in Task 5 Step 2) and assert its observable contract the
// same way if the type is Equatable; otherwise compile-exercise it in
// a @ViewBuilder body and assert the view builds.

// Modifier path: compile-exercise
@Test @MainActor func navigationTitleOverloadBuilds() {
    let localizable: LocalizedString = /* localized */
    _ = EmptyView().navigationTitle(localizable) // compiles + returns some View
}
```

- [ ] **Step 1:** Write the four tests following existing FOSMVVMTests localization-store setup.
- [ ] **Step 2:** `swift test --filter GeneratedOverloadTests` → green.
- [ ] **Step 3:** Commit: `test(FOSMVVM): behavioral contract tests for generated overloads`

---

### Task 10: CI staleness gate

**Files:**
- Modify: `.github/workflows/ci.yml` (append job)

```yaml
  overload_sweep_staleness:
    name: Generated overloads staleness gate
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - name: Compare SDK stamp and regenerate
        run: |
          # The script's --check mode compares per-platform SDK versions
          # against the stamp in SweepCoverage.md. Platforms whose SDK
          # version differs are reported and skipped (exit 0 + notice);
          # matching platforms must be diff-clean (exit 1 on drift).
          swift Scripts/localizable-overload-sweep.swift --check
```

Requires `--check` to implement the per-platform skip semantics (spec
Stage 6): version mismatch ⇒ informational skip, never failure —
regeneration is a deliberate act, and a runner with a missing SDK
(e.g. no visionOS image) reports-and-skips that platform rather than
hard-exiting in `--check` mode. (Full generation keeps the hard-exit.)

- [ ] **Step 1:** Adjust `--check` for per-platform skip semantics; add the job.
- [ ] **Step 2:** Local rehearsal: `swift Scripts/localizable-overload-sweep.swift --check` → exit 0 with per-platform verdict lines.
- [ ] **Step 3:** Commit: `ci: staleness gate for generated Localizable overloads`

---

### Task 11: Catalog, CHANGELOG, docs

**Files:**
- Modify: `.claude/skills/shared/api-catalog/FOSMVVM.md` — one *family* entry under § SwiftUI Support describing the generated overload surface (how to call: `Text(viewModel.title)`, `Button(vm.action) {...}`, etc.; contract: mirrors SwiftUI's LocalizedStringKey surface with `some Localizable` + `defaultValue:`), marked `<!-- apple-only -->` if the audit requires it.
- Modify: `CHANGELOG.md` — Unreleased: feature (full generated overload surface) + breaking (`defaultTitle:` → `defaultValue:`, `any` → `some`, removed optional-init relocation notes).

- [ ] **Step 1:** Write both entries.
- [ ] **Step 2:** `swift Scripts/api-catalog-audit.swift` → no stale-entry errors introduced (gap warnings about generated members should be satisfied by the family entry; if the audit floods, extend `scripts/api-catalog-ignore.txt` per its documented mechanism and note it in the PR).
- [ ] **Step 3:** Commit: `docs: catalog family entry + CHANGELOG for generated overloads`

---

### Task 12: Final verification + review gate

- [ ] **Step 1:** `swiftformat .` → no diff; `swiftlint` → clean.
- [ ] **Step 2:** `swift test` full suite → green; record counts.
- [ ] **Step 3:** `swift Scripts/localizable-overload-sweep.swift --check` → exit 0.
- [ ] **Step 4:** Squash granular commits into logical commits (script / migration / tests / ci+docs). **Do NOT open a PR** — push the branch and stop: David reviews first (repo review gate), then says go.

---

## Deviations that require stopping

- The real graphs surface a candidate class the transform rules don't
  cover cleanly (beyond variadics) → stop and show David the class, do
  not invent policy 4.
- Generated output fails to compile on any platform after honest
  sibling-matching → the delegate policy has a hole; stop, bring the
  failing declarations.
- The candidate count after filtering is wildly off the probe's order
  of magnitude (e.g. 10 or 50,000) → selection rule is wrong; stop.
