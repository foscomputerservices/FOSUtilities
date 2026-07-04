# @LocalizedDate Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the missing `@LocalizedDate` property wrapper to the `Localized*` family (confirmed library bug — the family and two doc surfaces already reference it), plus macro recognition, contract tests, and the catalog correction.

**Architecture:** Mirror the existing `_LocalizedProperty` family pattern exactly: a `RetrievablePropertyNames` typealias + a constrained `init where Value == LocalizableDate` that delegates all formatting semantics to `LocalizableDate` (styles default in ONE home — the owner). Both macros' `knownLocalizedPropertyNames` lists must include the new name (the NOTE at the typealias site requires it; without it, `@ViewModel`/`@FieldValidationModel` expansion skips the property's `localizationId` registration).

**Tech Stack:** Swift 6, FOSMVVM + FOSMacros, Swift Testing (FOSMVVMTests) + XCTest (macro tests, macOS-only), the api-catalog update workflow from PR #105 (this branch stacks on `feature/api-catalog`).

---

## Design decisions (rationale — implementer context, gated via fosmvvm-planning)

1. **`value: Date` is REQUIRED** — deliberate deviation from `LocalizedInt`/`LocalizedDouble`'s `value: X? = nil`. Ints/doubles have a natural identity fallback (`0`); a date has no meaningful zero, and an implicit `Date()` would bake a nondeterministic encode-time value into ViewModels. (Base-type discipline: minimize options, not meanings.)
2. **No style-default logic in the wrapper init.** `LocalizableDate.init(value:dateStyle:timeStyle:dateFormat:)` already implements "`.medium` date style when nothing is specified" — the wrapper passes optionals through untouched. One home for the default (derive on the owner).
3. **`LocalizableValue.swift:24` DocC needs NO edit** — it already lists `@LocalizedDate`; it becomes true when this lands. Same for `.claude/CLAUDE.md:153` (Key Patterns). The only doc that must CHANGE is the catalog (`FOSMVVM.md`), which currently documents the absence.
4. **Dedicated test ViewModel** — do NOT add properties to the shared `Tests/FOSMVVMTests/TestViewModel.swift`: `expectVersionedViewModel` compares against committed `.VersionedTestJSON` baselines and a new property invalidates them.
5. **Macro snapshot tests:** the existing `ViewModelMacroTests`/`FieldValidationModelMacroTests` fixtures embed full expected expansions. Add `@LocalizedDate` to those fixtures and update the expected strings — the diff must be ONLY the new property's entries (`_aLocalizedDate.localizationId: "aLocalizedDate"` etc.). If the snapshot churn turns out larger than the new-property entries, STOP and report (something else is wrong).

## File structure

```
Sources/FOSMVVM/Localization/LocalizedProperty.swift      modify (typealias ~line 167; init after the LocalizedDouble init ~line 349)
Sources/FOSMacros/ViewModelMacro.swift                    modify (~line 54 list)
Sources/FOSMacros/FieldValidationModelMacro.swift         modify (~line 49 list)
Tests/FOSMVVMTests/Localization/LocalizedDateTests.swift  create (contract tests, Swift Testing)
Tests/FOSMacrosTests/ViewModelMacroTests.swift            modify (fixture + expected expansion)
Tests/FOSMacrosTests/FieldValidationModelMacroTests.swift modify (fixture + expected expansion)
.claude/skills/shared/api-catalog/FOSMVVM.md              modify (wrapper-family entry, via update-skill rules)
.claude-plugin/plugin.json                                modify (2.7.0 → 2.8.0, catalog content change = minor)
CHANGELOG.md                                              modify (new API entry — follow the file's existing conventions)
```

---

### Task 1: Wrapper + macro recognition (TDD; red = compile failure)

**Files:**
- Test: `Tests/FOSMVVMTests/Localization/LocalizedDateTests.swift` (create)
- Modify: `Sources/FOSMVVM/Localization/LocalizedProperty.swift`
- Modify: `Sources/FOSMacros/ViewModelMacro.swift`, `Sources/FOSMacros/FieldValidationModelMacro.swift`

- [ ] **Step 1: Write the failing test.** Model the file on `Tests/FOSMVVMTests/Localization/LocalizableDateTests.swift` (locale setup) and `LocalizablePropertyTests.swift` (wrapper round-trips). Structure:

```swift
// LocalizedDateTests.swift  (license header via swiftformat)
import FOSFoundation
import FOSTesting          // LocalizableTestCase
@testable import FOSMVVM   // mirror LocalizablePropertyTests' imports exactly; contract assertions must not reach internals
import Foundation
import Testing

struct LocalizedDateTests: LocalizableTestCase {
    // 1. Wrapper init: wrappedValue carries value + styles through to LocalizableDate
    @Test func wrapperInitPassesThrough() { ... @LocalizedDate(value: fixedDate, dateStyle: .short) ... }

    // 2. Default styling: no style args → LocalizableDate's .medium default applies
    // 3. Codable round-trip via try vm.toJSON().fromJSON() after localized encode:
    //    localizedString differs per locale (en vs es), matching LocalizableDateTests' expectations
    // 4. Versioning: vFirst/vLast flow through like the LocalizedInt tests
    let locStore: LocalizationStore
    init() throws { self.locStore = try Self.loadLocalizationStore(bundle: .module, resourceDirectoryName: "TestYAML") }
    // ^ loadLocalizationStore is synchronous `throws` — no await; no @Suite attribute (siblings use none;
    //   each suite loads its own locStore, no shared singleton)
}
```

Use a `@ViewModel struct DateTestViewModel` fixture (private to the test file, NOT the shared TestViewModel) with `@LocalizedDate(value:)`, `@LocalizedDate(value:dateStyle:)`, and `@LocalizedDate(value:dateFormat:)` properties, a fixed `Date(timeIntervalSince1970: 1_720_000_000)`, `vmId`, `stub()` per the `@ViewModel` requirements (crib the minimal shape from an existing small test VM in this test target).

- [ ] **Step 2: Run to verify it fails** — `swift test --filter LocalizedDateTests` → expect COMPILE failure: `LocalizedDate` not found.
- [ ] **Step 3: Minimal implementation.**
  - `LocalizedProperty.swift` typealias block (after `LocalizedDouble`, before `LocalizedCompoundString`, keeping the family's order sensible): `typealias LocalizedDate = _LocalizedProperty<Self, LocalizableDate>` — and heed the adjacent NOTE comment (next bullet).
  - Both macro files: add `"LocalizedDate"` to `knownLocalizedPropertyNames` (after `"LocalizedDouble"`).
  - The init, after the `LocalizedDouble` init, DocC first (drafted at the gate — call-site framed):

```swift
    /// Initializes the ``LocalizedDate`` property wrapper
    ///
    /// ## Example
    ///
    /// ```swift
    /// @ViewModel struct MyViewModel {
    ///     @LocalizedDate(value: order.placedAt, dateStyle: .short) var placedAt
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - value: The date to localize; formatted for the receiving **Locale** during encoding
    ///   - dateStyle: The **DateFormatter.Style** for the date portion (when no style or
    ///      format is provided, ``LocalizableDate`` defaults to `.medium`)
    ///   - timeStyle: The **DateFormatter.Style** for the time portion (default: none)
    ///   - dateFormat: A fixed date-format string that overrides the styles (default: none)
    ///   - vFirst: The first *SystemVersion* that this property is valid in
    ///   - vLast: The last *SystemVersion* that this property is valid in
    public init(value: Date, dateStyle: DateFormatter.Style? = nil, timeStyle: DateFormatter.Style? = nil, dateFormat: String? = nil, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) where Value == LocalizableDate {
        self.localizationId = .random(length: 10)
        self.wrappedValue = .init(
            value: value,
            dateStyle: dateStyle,
            timeStyle: timeStyle,
            dateFormat: dateFormat
        )
        self.bindWrappedValue = nil
        self.vFirst = vFirst ?? .vInitial
        self.vLast = vLast
    }
```

- [ ] **Step 4: Run to verify green** — `swift test --filter LocalizedDateTests` → PASS; then full `swift test` → 331+new pass (baselines untouched).
- [ ] **Step 5: swiftformat the touched files (license header rule); verify stable; commit**

```bash
git add Sources/FOSMVVM/Localization/LocalizedProperty.swift Sources/FOSMacros/ViewModelMacro.swift Sources/FOSMacros/FieldValidationModelMacro.swift Tests/FOSMVVMTests/Localization/LocalizedDateTests.swift
git commit -m "feat(FOSMVVM): add missing @LocalizedDate property wrapper"
```

### Task 2: Macro expansion snapshot tests

**Files:** Modify `Tests/FOSMacrosTests/ViewModelMacroTests.swift`, `Tests/FOSMacrosTests/FieldValidationModelMacroTests.swift`

- [ ] Add `@LocalizedDate(value: Date(timeIntervalSince1970: 0)) var aLocalizedDate` to the fixture VM in each test (next to the existing `@LocalizedInt(value: 42) var aLocalizedInt`), and add the matching `_aLocalizedDate.localizationId: "aLocalizedDate"` entry to each expected `localizationIds` dictionary string (match the dict's existing ordering convention — read the actual failure diff to place it exactly).
- [ ] Run `swift test --filter ViewModelMacroTests && swift test --filter FieldValidationModelMacroTests` — first run shows the expected-vs-actual diff; confirm the ONLY delta is the new property's entries (design decision 5: larger churn = STOP and report), fix expected strings, re-run → PASS.
- [ ] Commit: `git add Tests/FOSMacrosTests/... && git commit -m "test(FOSMacros): cover @LocalizedDate in macro expansion tests"`

### Task 3: Catalog correction + plugin bump + CHANGELOG (the update-skill workflow, for real)

**Files:** Modify `.claude/skills/shared/api-catalog/FOSMVVM.md`, `.claude-plugin/plugin.json`, `CHANGELOG.md`

- [ ] Follow `.claude/skills/fosutilities-api-catalog-update/SKILL.md` (it is on this branch): run `swift scripts/api-catalog-audit.swift` (rebuilds symbol graphs with the new API). Expected: 0 stale; `LocalizedDate` is likely parent-covered (member of catalogued `RetrievablePropertyNames`) so possibly 0 gaps — the catalog edit is still REQUIRED because the prose is now wrong.
- [ ] Edit the `@Localized*` wrapper-family entry in `FOSMVVM.md` (§ Localization, ~line 100–115): add `LocalizedDate` to the title backticks; replace the "There is no `@LocalizedDate` wrapper — carry a `LocalizableDate` property instead" limitation note with a normal family mention (dateStyle/timeStyle/dateFormat pass-through, `.medium` default; value is required — no zero date). Keep entry-format rules (task-framed title, label-free symbols, ≤~8-line example).
- [ ] Re-run the audit → 0 gaps / 0 stale / exit 0 (paste summary). Confirm `.claude/CLAUDE.md:153` Key Patterns line (`@LocalizedDate`) is now TRUE — no edit.
- [ ] Fix `.claude/docs/FOSMVVMArchitecture.md:920`: `@LocalizedDate var createdAt` doesn't compile (value is required) → `@LocalizedDate(value: model.createdAt) var createdAt` (Task 1 review finding — Architecture is Truth; a truth doc must not demo an invalid call).
- [ ] `CHANGELOG.md`: add the new-API entry following the file's existing section conventions (read the top of the file first).
- [ ] `plugin.json`: 2.7.0 → 2.8.0 (catalog content change = minor, per the update skill's semver guidance).
- [ ] Commit: `git add .claude/skills/shared/api-catalog/FOSMVVM.md .claude-plugin/plugin.json CHANGELOG.md && git commit -m "docs(api-catalog): @LocalizedDate exists now; bump plugin to 2.8.0"`

### Task 4: End-to-end verification

- [ ] `swift test` — full suite green (paste tail).
- [ ] `swift scripts/api-catalog-audit.swift; echo $?` — 0 gaps / 0 stale / exit 0 (paste summary).
- [ ] `grep -rn "no .*LocalizedDate\|LocalizedDate.*does not exist\|there is no" .claude/skills/shared/api-catalog/ .claude/CLAUDE.md .claude/docs/` — nothing claiming absence remains; and `grep -n "@LocalizedDate var" .claude/docs/FOSMVVMArchitecture.md` returns nothing (all examples use the required value form).
- [ ] No commit (verification only); report results.

---

## Execution notes

- Branch `fix/localized-date-wrapper` stacks on `feature/api-catalog` (PR #105). The PR for this branch targets `feature/api-catalog` (or retargets `main` after #105 merges).
- Macro tests are XCTest and compile on macOS — fine locally; ubuntu CI also builds macros.
- If `swift test --filter` misbehaves with macro targets, run the full suite — it's ~5 min.
