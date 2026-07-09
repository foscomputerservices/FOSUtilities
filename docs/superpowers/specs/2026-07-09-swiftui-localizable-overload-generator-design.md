# SwiftUI Localizable Overload Generator — Design

**Date:** 2026-07-09
**Status:** Approved design, pre-implementation
**Owner:** David Hunt

## Problem

FOSMVVM ships `Localizable`-accepting overloads that mirror SwiftUI's
`LocalizedStringKey`/`String` APIs (`Text`, `Label`, `TextField`,
`LabeledContent`, `Tab`, `ContentUnavailableView`, `View.navigationTitle`).

Today those overloads are hand-written:

- Coverage is incidental (seven files; Button, Toggle, Picker, alerts,
  and hundreds of others have no overload).
- Conventions drifted (`defaultValue:` vs `defaultTitle:`,
  `some Localizable` vs `any Localizable`).
- Every new SwiftUI release silently widens the gap.

## Goal

A mechanism that sweeps the SwiftUI API surface as it evolves each OS
release and generates the full set of `Localizable` overloads
automatically, deterministically, and verifiably.

## Decisions (settled during design review)

1. **Fully automatic selection** — a deterministic rule decides which
   APIs get overloads. No per-API human allowlist.
   The rule leans on Apple's own curation: a `LocalizedStringKey`
   parameter is Apple's signal that the parameter is display text.
2. **Sweep scope: the SwiftUI module surface** — initializers *and*
   modifiers/methods. Because `Text`, `LocalizedStringKey`, and much of
   the surface migrated to `SwiftUICore` (2024 SDKs), the sweep covers
   both binary modules (`SwiftUI`, `SwiftUICore`) and their
   cross-module extension graphs. Sibling frameworks (Charts,
   WidgetKit, TipKit) are out of scope.
3. **Checked-in, maintainer-run** — the generator is a tool the
   maintainer runs when new SDKs ship. Generated sources are committed.
   FOSMVVM's public API is deterministic and reviewable in PRs.
4. **Generated replaces hand-written** — the seven hand-written mirror
   files are deleted. Non-mirror machinery is relocated (see
   "Not generated"). Source-breaking unification is accepted now,
   pre-1.0 (`defaultTitle:` → `defaultValue:`,
   `any Localizable` → `some Localizable`).
5. **`defaultValue:` kept everywhere** — every generated overload takes
   a `String? = nil` fallback after each Localizable slot.
6. **Extraction mechanism: symbol graphs** (Approach A) —
   `xcrun swift-symbolgraph-extract` JSON, decoded with plain
   `Codable`. Zero new dependencies; prior art in
   `Scripts/api-catalog-audit.swift`. The rejected alternative
   (parsing `.swiftinterface` with swift-syntax) bought only verbatim
   extension contexts at the cost of a high-churn dependency.
7. **Version identity is the SDK/OS version, never Xcode's version.**
   SwiftUI's surface is tied to the OS SDK. All stamps, comparisons,
   and gates key on per-platform SDK versions
   (`xcrun --sdk <name> --show-sdk-version`).
8. **Availability spans old-through-beta from one generated set** —
   generation runs against the newest installed SDKs, betas included
   (today: the OS 27 betas), and every overload carries the
   per-platform `@available` matrix from symbol-graph data, so one
   checked-in set serves clients back through OS 26 (and the package
   floors below that) while exposing 27-beta API behind guards.

## Empirical grounding (probed 2026-07-08, OS 26-era macOS SDK)

- `swift-symbolgraph-extract -module-name SwiftUI` succeeds;
  output ~456 MB JSON, 83,378 symbols.
- 5,124 symbols are inits/methods with a `LocalizedStringKey`
  parameter (184 inits, 4,940 methods) *before* filtering
  deprecated/obsoleted/underscored — filtering will cut this
  substantially; expect a shipped surface in the hundreds.
- `declarationFragments` reproduce exact signatures, including
  default arguments, `nonisolated`, generic params, and `where`
  clauses. Example, verbatim from the graph:

  ```swift
  nonisolated init<F>(_ titleKey: LocalizedStringKey,
      value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil)
      where F : ParseableFormatStyle, F.FormatOutput == String
  ```

## Architecture — six-stage pipeline

The tool is a standalone SPM executable package under `Tools/`,
independent of the root package (consumers never see it).
Not a single-file script: it has real parsing and transformation
rules and deserves unit tests.

### 1. Extract

For each platform — macOS, iOS, tvOS, watchOS, visionOS — run
`xcrun swift-symbolgraph-extract` against that platform's SDK for both
modules (`SwiftUI`, `SwiftUICore`), collecting main graphs and
extension graphs (e.g. `SwiftUI@SwiftUICore.symbols.json`).
Record each SDK's version at extract time; these versions become the
run's identity stamp.

### 2. Select

Keep a symbol when all of:

- kind ∈ { `swift.init`, `swift.method`, `swift.func` }
- at least one *parameter* is `LocalizedStringKey`, matched by the
  fragment's `preciseIdentifier` (`s:7SwiftUI18LocalizedStringKeyV`),
  never by spelling
- not deprecated, not obsoleted, not underscored, not SPI

### 3. Union

Merge platform graphs by USR (Apple's stable symbol ID).
One API seen on several platforms becomes one record with a merged
per-platform availability matrix.

Availability clamping against the Package.swift floors
(iOS 17 / macOS 14 / macCatalyst 17 / tvOS 17 / watchOS 10 /
visionOS 1): introduced-at-or-below-floor ⇒ no annotation;
otherwise emit the full `@available(...)` line from graph data.
`unavailable` domains are emitted as Apple declares them.

iPadOS has no separate availability domain in symbol graphs — it rides
`iOS`. macCatalyst is its own domain.

### 4. Transform

For each record, produce one overload:
Apple's signature with these edits, everything else copied verbatim
(generic parameters, `where` clauses, default arguments,
`nonisolated`, extension context and its constraints —
e.g. `extension TextField where Label == Text`):

- Each `LocalizedStringKey` parameter type becomes `some Localizable`.
  Never `any` (existentials are a code smell, per governance).
- After each replaced slot, insert a fallback parameter:
  - unnamed leading slot (`_ titleKey:`) → `defaultValue: String? = nil`
  - labeled slot → `default<Label>: String? = nil`
    (a two-slot API reads `defaultValue:` + `defaultMessage:`)
- Multi-slot APIs produce **one** overload with all key slots
  replaced — no mixed String/Localizable combinatorics.

**Body — delegate-target policy.** The body must hand SwiftUI an
*already-localized* `String`, never a `LocalizedStringKey` (that would
re-enter bundle lookup). Deterministic, in order:

1. A `some StringProtocol` sibling with an otherwise-identical
   signature exists in the graphs → delegate directly:
   `self.init(localizable.defaultedLocalizedString(defaultValue: defaultValue), ...)`
2. Else a `Text`-taking sibling exists → delegate wrapping
   `Text(verbatim: resolved)`.
3. Else → skip; record in the coverage manifest.
   The tool never emits a call it cannot prove has a target.

### 5. Emit

- One generated file per extended type (`Text.swift`,
  `TextField.swift`, `View.swift`, …) under a generated-sources
  directory inside `Sources/FOSMVVM/SwiftUI Support/`
  (directory name: naming table).
- Files wrapped in `#if canImport(SwiftUI)`.
- Every file gets a DO-NOT-EDIT header stamped with the per-platform
  SDK versions the run saw (Xcode version recorded only as an
  informational footnote).
- Output sorted by USR: same SDKs in ⇒ byte-identical files out.
- `swiftformat` runs on output (also inserts the Apache header).
- Alongside the code: a checked-in **coverage manifest** listing every
  candidate the run skipped, with a reason from a closed set
  (`deprecated` / `no-delegate-target` / `unrecognized-shape` /
  duplicates folded by union). Silent truncation is banned; coverage
  changes must be visible in the PR diff.
- **Beta hygiene:** any API whose `introduced:` equals a beta SDK's own
  version is flagged `beta-tier` in the manifest — informational, so
  the RC-time regeneration diff shows exactly which beta-era
  signatures Apple renamed or dropped.

### 6. Verify

- Generated code is checked in ⇒ the existing CI matrix compiling
  FOSMVVM on all Apple platforms is the primary integration test.
- **CI staleness gate:** per platform, if the runner's SDK version
  equals the stamped one, that platform's regeneration slice must be
  `git diff --exit-code` clean. Platforms whose SDK differs are
  skipped with an informational note — a new-SDK rollout never breaks
  unrelated PRs; regeneration is a deliberate, reviewed act.

### Maintainer workflow (new SDKs ship)

Run the tool → review the diff (new APIs appear as new overloads;
manifest diff shows coverage changes) → commit.

## Not generated (relocated, stays hand-written)

- `LocalizableResolverView` + the `Localizable.text` property —
  client-side resolution machinery; mirrors nothing.
- The optional-Localizable `Text` init — SwiftUI has no optional-key
  inits to mirror.

Both move to one hand-written file (name: naming table).

## Documentation

- Every generated overload gets a template-driven, customer-framed
  DocC comment: one sentence
  ("Localizable-accepting form of SwiftUI's `Label.init(_:systemImage:)`")
  plus one usage example per extended type.
- The API catalog gets one curated *family* entry
  (`FOSMVVM.md § SwiftUI Support`) so the catalog audit sees the
  surface without flooding gap warnings.

## Error handling

- **Missing SDK** → hard exit, nonzero, naming exactly which SDKs are
  missing. No partial-platform generation — it would silently emit
  wrong availability annotations.
- **Un-transformable symbol** (unrecognized declaration shape) →
  never guess, never emit: skip + manifest entry with reason and raw
  declaration. The run still succeeds.
- **Nothing is silently dropped** — every non-generated candidate is a
  manifest line with a closed-set reason.

## Testing

1. **Unit tests on the tool** (Swift Testing, in the tool package):
   selection filter, availability merge + floor clamping, signature
   transformation, delegate-target policy, multi-slot naming.
   Driven by small checked-in symbol-graph fixtures (hand-trimmed JSON
   records, a few KB — never the real graphs).
   Golden tests: fixture record in → expected Swift source out,
   verbatim.
2. **The package build is the integration test** — checked-in output
   compiling on the full CI matrix proves delegate targets resolve and
   availability is coherent.
3. **Behavioral tests stay behavioral** — a small hand-written test
   file exercises one representative overload per delegate-policy path
   (String-sibling, Text-verbatim), asserting the localized value
   lands in the view. Test the contract, not the generated text.

## Migration (one-time, in implementation)

1. Delete the seven hand-written mirror files.
2. Relocate resolver machinery + optional-Text init.
3. Generate; run the full suite.
4. Intended breakage surfaces in existing call sites
   (`defaultTitle:` → `defaultValue:`, `any` → `some`).

## Naming table — David arbitrates

No name below is settled. Candidates carry the legibility axis
(distinct leading characters, no confusable shapes).

**1. Tool package directory (under `Tools/`)**

- `LocalizableOverloads` — plain, states the output
- `OverloadSweep` — states the mechanism (sweep), distinct shape
- `SwiftUIMirror` — states the relationship, risks vagueness

**2. Generated-sources directory (inside `SwiftUI Support/`)**

- `Generated` — conventional, instantly legible
- `Swept` — distinct from everything, but cryptic

**3. Relocated hand-written file**

- `LocalizableViews.swift`
- `LocalizableResolution.swift` — names the machinery's job

**4. Coverage manifest filename**

- `SweepCoverage.md` — ⚠ flagged: `Generated/` + `GenerationManifest.md`
  would share a `Genera-` prefix (confusable shapes); a `Sweep-` name
  avoids the collision
- `GenerationManifest.md`

**5. Multi-slot fallback parameter convention**

- `defaultValue:` (unnamed slot) + `default<Label>:` (labeled slots) —
  proposed
- alternative: `default<Label>:` everywhere, no bare `defaultValue:`
  (uniform but breaks the shipped convention)

## Open questions

- None blocking. Naming table awaits arbitration; can be settled at
  implementation-plan time.
