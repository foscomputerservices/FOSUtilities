---
area: viewmodel-test
generator-skill: fosmvvm-viewmodel-test-generator
where:
  - "Tests/**/*ViewModel*Tests.swift"
  - "Tests/**/ViewModels/**/*Tests.swift"
---

# ViewModel Test Checks

The positive pattern lives in the `fosmvvm-viewmodel-test-generator` skill. A ViewModel test's job is to prove the *contract* — that the type round-trips, that old encodings still decode, that every locale has a translation. These checks are about tests that reach past that contract, or that quietly stop proving it.

## Reviewer Guidance

- **`@testable import` here exists to see internal ViewModel types, not to reach a value's internals.** It is legitimate for block coverage; it is never a licence to fabricate or inspect state the public contract does not offer. Do NOT recommend reaching an internal init or getter to make an assertion easier — that is the encapsulation break wearing test clothing.
- **Do NOT recommend asserting an encoded shape**, even to "pin the format". There is no contract that a type encodes a particular way, only that it round-trips. That rule is `representation-test` in `cross-cutting.md`; do not duplicate it here, but do not undermine it either.
- A ViewModel test that only exercises `.stub()` proves the stub, not the ViewModel. The round-trip is what makes it a test. This is satisfied at *suite* level: a stub-composition test sitting beside a full contract test in the same file is fine, and is not a finding.
- **Read the pinned tag's `FOSTesting` source before grading, and trust it over the tests' own comments.** Test files in a mature codebase accumulate confident, detailed explanations of framework internals that were true once. Two in the codebase this file was verified against were stale by a release.

## Check: viewmodel-test-covers-the-contract
**Severity:** warning
**What:** Each ViewModel has a test exercising the full contract — Codable round-trip, version stability, and translations for every supported locale.
**Anti-pattern:** A test file that constructs `.stub()`, asserts a property, and stops — no round-trip, no `expectFullViewModelTests`, so a broken `Codable` conformance or a missing Spanish translation ships green.
**Detection:** Enumerate `@ViewModel` types and the tests covering them.

**Child ViewModels are covered for Codable and NOT for translations — this is the fact the check turns on.** A parent's round-trip carries its children, so their `Codable` conformance is exercised. `expectTranslations` is a **single-level `Mirror(reflecting:)` walk** (`Sources/FOSTesting/LocalizableTestCase.swift`): it inspects only children castable to `any Localizable` or `_LocalizedProperty`. A `[ChildViewModel]` is neither — there is no `Array: Localizable` conformance — and a single nested `ViewModel` property is neither either. Both are skipped outright, with no recursion.

Nor does encoding catch it: `LocalizableString.encode(to:)` resolves a missing translation to `""` rather than throwing. So a missing or typo'd translation on a child ViewModel ships green through the parent's test.

**Therefore: a child ViewModel carrying any localized property needs its own test.** Do not accept "the parent covers it" — and treat a comment in the tests asserting that it does as a finding in its own right, because that belief is precisely what stops the missing test from being written.

Then flag a ViewModel with no test at all, and a test that never reaches `expectFullViewModelTests` (or, where the coverage is assembled by hand, all three of `expectCodable`, `expectVersionedViewModel`, and `expectTranslations`). The one-line form is the generator's standard pattern and is sufficient for most ViewModels; hand-assembly is fine, partial hand-assembly is the hit — say which of the three is missing.

## Check: versioned-baselines-not-regenerated
**Severity:** blocker
**What:** Committed `.VersionedTestJSON` baselines are additive history, never refreshed to make a change pass.
**Anti-pattern:** A commit deleting or rewriting committed baseline files alongside a ViewModel change — or a test-suite helper that deletes them before running.
**Detection:** `expectVersionedViewModel` writes a baseline once when absent, then only ever *re-decodes* every committed version to prove old encodings still load. Deleting them destroys the historical versions that are the entire point of the check, and the suite goes green by having nothing left to verify.

**Two modes, and they look for different things.** Reviewing a *diff*: flag baseline files deleted or modified in the same change as a ViewModel's shape. Reviewing a *sweep*: walk the baseline directory's history (`git log --diff-filter=DM --name-status`) and cross-reference each touching commit against whether it also changed a ViewModel — that pairing is the signal, and it is invisible from the working tree, which will look clean. An already-released commit is still worth reporting: the lost decode history does not come back, and the finding tells the owner which versions can no longer be audited.

Flag any code path that removes or overwrites baselines. The remedy is that a schema change must stay backward-decodable: add fields, never rename or remove them. If a rename is genuinely required, that is a versioning decision for the owner, not a baseline refresh.

**A version-line re-cut is not a green-washing, and should be reported differently.** When a project retires a whole version series — collapsing three version axes into one, renaming `1.0.0` to `0.2.0` — the old baselines stop denoting anything and replacing them is legitimate. The tell is that no ViewModel shape changed in that commit. Report it as context rather than as a defect, and say what it cost: every earlier rewrite becomes unauditable, because the history it would be checked against is gone.

Note the check is decode-only and **skips `ClientHostedViewModelFactory`** types, so a client-hosted ViewModel showing no versioned coverage is expected, not a gap.

## Check: no-date-equality-across-round-trip
**Severity:** warning
**What:** Tests do not assert in-memory `Date` equality across an encode/decode round-trip.
**Anti-pattern:** `#expect(decoded.createdAt == original.createdAt)` where `original` was built from `Date()`.
**Detection:** FOSMVVM's canonical wire format is **millisecond** precision, so a freshly-created `Date` is not equal to itself after a round-trip — the sub-millisecond component is truncated. Flag equality assertions on `Date`-typed properties across a round-trip. This fails intermittently rather than reliably, which is worse: it passes locally and flakes in CI. The remedy is to compare via behaviour or ordering, or to start from an already-canonical fixture value rather than `Date()`.

## Check: test-yaml-covers-every-locale
**Severity:** warning
**What:** A ViewModel's test YAML carries every locale the suite asserts.
**Anti-pattern:** `expectTranslations` running against `en` and `es` while the fixture defines only `en`, so the Spanish assertion passes against a fallback rather than a translation.
**Detection:** For each ViewModel under test, find its test YAML and compare against the locales the test case declares. Two failures, both in scope, checked separately:

- **A locale block absent entirely** — the fixture defines `en:` and the suite asserts `es:`.
- **Key-level gaps** — both blocks exist, but `es:` is missing individual property keys. Diff the full key tree under each locale, not just the top-level blocks; this is the more common shape and the structural one.

Say which locale, which fixture, and which keys — the failure mode is a test that looks like it covers two languages and covers one.

**Out of scope: English copied into a non-English block.** A fixture whose `es:` keys are all present and all hold English text passes every structural check and is invisible here. It is a real defect and worth mentioning if you happen to notice it, but do not build the check around detecting it.

## Check: versioned-baseline-committed
**Severity:** warning
**What:** Every non-client-hosted ViewModel under versioned test has at least one **committed** `.VersionedTestJSON` baseline (ruled 2026-08-25; the generator's Conceptual Foundation states the committed-artifact rule). Without one, `expectVersionedViewModel` takes its write-once branch on every clean checkout and then re-decodes only the baseline it just wrote — the wire-shape canary can never fire.
**Anti-pattern:** A test target calling `expectFullViewModelTests(SomeViewModel.self)` with no `.VersionedTestJSON` directory anywhere in its tree.
**Detection:** For each test target exercising `expectFullViewModelTests`/`expectVersionedViewModel`, check that a `.VersionedTestJSON` directory exists in the target's tree, is tracked (not ignored), and holds at least one baseline per non-client-hosted ViewModel under test. `clientHostedFactory` ViewModels are exempt — they carry no server wire contract to pin. Destroying or regenerating existing baselines is `versioned-baselines-not-regenerated`'s finding; this check fires on never having had them.
