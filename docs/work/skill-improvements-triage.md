# Skill-improvements triage & execution prep (backlog item #3)

**Status:** prep only — no skill edits made from this doc yet. Written to set up a
**fresh, carefully-scoped session** to fold the Port-Authority-surfaced skill
improvements into the `fosmvvm-*` generator skills.

## Why this needs care

Skills **replicate their patterns into every downstream customer app.** A wrong
pattern in a skill is not one bug — it is the same bug scaffolded into every
FOSMVVM project that runs the generator. So the bar is: *get it right*, not *get
it done*. This is the same discipline that (today) kept us from over-folding the
`stub()` witness — the macro only synthesizes for `@ViewModel` types, so blindly
deleting every hand-written `stub()` would have broken nested/singleton cases.

## Non-negotiable process (per skill edit)

1. **Source-of-truth ordering:** SOLID first → `.claude/docs/FOSMVVMArchitecture.md`
   → code. If a backlog entry conflicts with SOLID, that outranks the entry.
2. **`writing-skills` TDD, every edit (rigid):**
   - **RED** — run a pressure/generation scenario with a subagent against the
     **current** skill; watch it reproduce the wrong pattern (baseline).
   - **GREEN** — edit, then a **fresh subagent reading ONLY the edited skill**
     must produce the right pattern *and not over-apply it* (the stub test today
     is the template: it correctly folded `@ViewModel` parents while keeping the
     singleton and nested-type stubs).
   - Compile/verify code templates against the real macros where feasible.
3. **Triage-before-edit:** several entries are **already partially addressed**
   (e.g. app-setup already has Template 7 + `SPMLibraries`). Re-read the current
   skill before changing it — do not assume the backlog's "Actual" still holds.
4. **Versioning:** bump the plugin version (`.claude-plugin/plugin.json`) and the
   per-skill Version History table when a skill's emitted output changes. Decide
   cadence with David (one bump at end of batch vs per-skill — see Decisions).
5. **Never push.** Changes flow back to David for the FOSUtilities release. Commit
   locally on the working branch only.

## Source of truth & context to load in the fresh session

- **The ratified backlog (Harbor worktree — a SEPARATE repo):**
  `/Users/david/.config/superpowers/worktrees/accelsharp-harbor/port-authority-ui/docs/work/fosutilities-improvements.md`
  (line refs below are `L<n>` into this file.)
- **Verified project template (Harbor worktree):**
  `…/port-authority-ui/docs/work/fosmvvm-app-project-template.md` — the
  build-verified `project.yml` recipe that L179/L183 want folded into app-setup.
- **Architecture doc (this repo):** `.claude/docs/FOSMVVMArchitecture.md` — the
  "Project Structure" (~L990), "What Belongs Where" (~L1076), and "File
  Organization Conventions" (~L1096) sections that L135 wants surfaced in app-setup.
- **Skills (this repo):** `.claude/skills/fosmvvm-{viewmodel-generator,
  viewmodel-test-generator, swiftui-app-setup, ui-tests-generator,
  serverrequest-generator}/` and the `shared/` skill dir.
- **Memory:** `[[fosutilities-improvements-status]]`, `[[fosutilities-040-release]]`.

---

## Triage

Legend: ✅ done · ⛔ withdrawn (do NOT act) · 📚 library-not-skill · 🏠 Harbor-side ·
🏛 architecture/item-#4 (brainstorm-gated) · ✳️ **OPEN & FOS-skill-facing (= item #3)**.

### ✅ Done — no action
- **Stub scaffolding fold-in** (L53–54) — done this session, commit `a7a4444`.
  `-viewmodel-test-generator` needed no change (its fixtures are plain
  `ViewModel`-protocol structs with no parameterized stub).
- **`ReplaceRequest`** (L67) — shipped.
- **`uiTestingIdentifier` library modifier** (L68) — ships in FOSMVVM `main`;
  only client-copy deletion remains (tracked in 0.4.0 release, not here).
- **`FOSTesting` baseline-directory fix** (L90) — shipped (commit `82fb579`).
  *Residual skill-doc note → see ✳️ B7.*

### ⛔ Withdrawn — do NOT act (acting would bless an anti-pattern)
- **Route-group prefix helper** (L97) — ViewModels are middleware-gated, never
  string-route-grouped. No `FOSTestingVapor` change.
- **`.bind()` addressing / `requestURL`** (L113) — base URLs are clean hosts;
  `requestURL` discarding a base-URL path is correct by design.

### 📚 Library, not a skill (tracked elsewhere)
- **Vapor `encodeResponse` serve-path gap** (L108–111) = backlog **item #1**,
  tracked in `docs/work/vapor-viewmodelfactory-encodeResponse-gap.md`. Its own
  focused session; not part of #3.

### 🏠 Harbor-side (not a FOS change)
- `HarborAdmin` verb-first NAMES divergence (L44) — David's rename call.
- `HarborChannel` not iOS-clean / host code not `#if os(macOS)`-gated (L126).
- Build-proof `iPhone 16` simulator stale vs iOS-26 floor (L132).
- `stubLocalization:` knob on `withLiveHarbormaster`/`withAdminApp` (L111 pt 3).
- Splitting the current `DocksViewModel.swift` into one-file-per-VM (L43, the
  *code-cleanup* half; the *skill* half is ✳️ B2).

### 🏛 Architecture — backlog item #4, brainstorm-gated (NOT #3)
- Subscribable/live `.bind()` → `@ViewModel(options:[.live])` (L72).
- Server-hosted `ViewModelOperations` pattern (L73).
- Independent per-contract `SystemVersion` lines (L74).

---

## ✳️ OPEN & FOS-skill-facing — this IS item #3

Grouped by target. Each entry: backlog line ref + the change + current-skill note.

### A. NEW ARTIFACT — FOSMVVM naming dictionary — ✅ DONE (GREEN-verified 2026-07-02)
Authored `.claude/skills/shared/NAMES.md` (Decision 1). RED baseline: subagent on the
*current* serverrequest-generator produced verb-first `CreateUserRequest`… (A2 read
requests were already correct — a "keep" case). GREEN: fresh subagent on the edited
skills produced noun-first CRUD **and** kept read requests verb-less (rejected
`DocksShowRequest`) **and** handled the duplicate-name case. Skills bumped:
serverrequest-generator → 2.10, viewmodel-generator → 2.10.
- **A1** (L40) ✅ Final/verb request types → `<Noun><Verb>Request` (noun-first, REST
  verb *and* semantic actions). NAMES.md §1a + serverrequest-generator "Naming the
  Concrete Request Type" section; flipped all verb-first examples in that skill.
- **A2** (L41) ✅ ViewModel read requests → `<Noun>Request` (verb-less). NAMES.md §1b;
  viewmodel-generator Naming Conventions row clarified (`DocksRequest`, not
  `DocksShowRequest`). (Was already correct — GREEN confirms not broken.)
- **A3** (L61) ✅ Duplicate type names across modules are fine (module *is* the
  namespace). NAMES.md §2 + viewmodel-generator note (with the DIP corollary).

### B. `fosmvvm-viewmodel-generator` (+ `-viewmodel-test-generator`)
- **B1** (L42) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.12) — explicit
  anti-mega-VM callout (SRP) on the top-level template. Was already implicitly correct
  via "Two Categories"; callout makes it bulletproof.
- **B2** (L43) ✅ DONE (GREEN 2026-07-02) — canonical "File Organization Conventions" in
  **app-setup 1.5** (Decision 2 owner) + one-file-per-VM scaffolding pointer added to
  viewmodel-generator 2.12 citing it. GREEN: one-file-per-type + container dir + mirroring.
- **B3** (L52) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.12) — "Dates and Numbers"
  now states the principle: init param is the plain Swift type, init body wraps + owns
  formatting policy (`.init(value:, showGroupingSeparator:)`); callers/stubs pass plain
  values. Card/UserCard row templates demonstrate it. Was partly present for Int/Date;
  now explicit + SRP framing.
- **B4** (L55 **=** L153) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.12) —
  **rewrote Identity section** (stable data identity; singleton vs list-row; String/Int/
  UUID/merged ids; List-churn warning) and reconciled **all** `.init()` throwaways in
  SKILL.md + reference.md. **Compile-verified against the real `@ViewModel` macro:**
  singleton uses `var vmId = .init(type: Self.self)` (a `let`+default is excluded from
  `Codable` decode — compiler warns), list-row uses `let vmId` + `.init(id:)` in init.
  GREEN: correct vmId for top-level/String-row/summary + rejected `.init(type:)` on rows.
- **B5** (L56) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.12) — Decision 6 =
  **hard rule**. Added dedicated **"ViewModel Module Must NOT Depend on Domain Types
  (Dependency Inversion)"** section: category-error framing, owned display enums, Factory
  performs projection, + the optional Factory-adapter domain-typed-init extension (server
  module only). GREEN over-application guard: Factory correctly imports BOTH modules (the
  one exception); adapter-init lives server-side.
- **B6** (L57) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.11) — Enum Localization
  Pattern now raw-less (`enum X: Codable, Sendable, CaseIterable`; key via
  `String(describing:)` not `rawValue` — verified `propertyName` is a plain `String` in
  `LocalizableString.swift`, so YAML keys unchanged) + anti-pattern callout.
- **B7** (L95-tail) ✅ DONE (GREEN 2026-07-02) — committed-baseline note added to BOTH
  `-viewmodel-test-generator` (1.3) and `Sources/FOSTesting/FOSTesting.docc/ViewModelTesting.md`:
  baseline is a committed artifact for downstream apps; FOS's own baselines are
  regenerable/git-ignored fixtures. Corrected a stale workaround — `expectFullViewModelTests`
  now forwards `#filePath`/`#line` (verified in `LocalizableTestCase.swift`).
- **B8** (L159) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.11) — added
  `SystemVersion`/locale-independent row to the field-type table + anti-pattern callout
  (version → `SystemVersion` via `.versionString`, hostname → `String`, never
  `LocalizableString`). GREEN produced `version: SystemVersion`, `host: String`.
- **B9** (L63) ✅ DONE (GREEN 2026-07-02, viewmodel-generator 2.11) — child template +
  nested-child example drop `: Codable, Sendable` (kept `Identifiable` as a genuine
  extra) + explicit DRY callout. GREEN over-application guard passed: top-level kept
  `: RequestableViewModel`, `Identifiable` kept when a `ForEach` needs it.

### C. `fosmvvm-swiftui-app-setup` (largest cluster — reconcile, don't just add)
Current state: reference.md already has **Template 7** (XcodeGen) *with* an
`SPMLibraries` umbrella, modeled on ConversationPractice. Several entries below
are therefore *upgrade/rationale*, not greenfield.
- **C1** (L135) ✅ DONE (GREEN 2026-07-02, app-setup 1.6) — added "Server-Hosted
  ViewModel Contract Wiring (Both Sides)" with all four rules + anti-drift callout,
  **grounded in the real FOSShowcase** (`WebServer/routes.swift` uses
  `app.routes.register(viewModel:)`, `SwiftUIApp/FOSShowcaseApp.swift` uses clean-host
  base URLs, `Sources/Resources/` sibling `.copy("../Resources")` from server/test — all
  verified). Resources-server-only clarified vs the client-hosted tree (annotated). Added
  native-app-in-root-`.xcodeproj` + Tests-mirror-Sources + link to arch doc. GREEN
  over-application guard: `.grouped(SomeMiddleware())` correct (only string form banned).
- **C2** (L147) ✅ DONE (GREEN 2026-07-02, app-setup 1.6) — added the type-identity
  rationale (`TypeA != TypeA` across targets; generic Xcode/SPM bug) + FOSMVVM-specific
  reason (type comparison) + "do not link per-target" callout; retitled the umbrella
  **REQUIRED** (was "Optional") in the section header, build-system table, and tree
  comment. GREEN over-application guard: UI-test target is the exception (links directly,
  separate process → routes to ui-tests generator).
- **C3** (L118 + L179 + L171) ✅ DONE (GREEN 2026-07-02, app-setup 1.7) — copied the
  build-verified template into **`docs/work/fosmvvm-app-project-template.md`** (Decision 3)
  and folded a "Verified project template" callout + Lifecycle into app-setup: Option-A
  source inclusion, **singular `BUILD_LIBRARY_FOR_DISTRIBUTION`** (fixed the plural no-op
  typo throughout SKILL.md + reference.md), `{Base}UnitTests`/`{Base}UITests` naming,
  `TEST_HOST` pin, app-hosted tests, `supportedDestinations`, `.xctestplan` caveat. GREEN
  confirmed all.
- **C4** (L196) ✅ DONE (GREEN 2026-07-02, app-setup 1.7) — added `.testHost()` no-arg
  display-only baseline + closure form as the typed-config opt-in; corrected `underTest`
  detection to `ProcessInfo…environment["__FOS_ViewModel"]` (verified `presentView` sets
  `launchEnvironment`, no args, in `ViewModelViewTestCase.swift`); replace_all'd the old
  `arguments.count` form. GREEN over-application guard: typed-config app → closure form.
- **C5** (L211) ✅ DONE (GREEN 2026-07-02, app-setup 1.7) — "Lifecycle: XcodeGen scaffolds,
  it does not maintain": one-shot, hand-add synchronized folders + iOS destinations, commit
  the `.xcodeproj`, keep strict-complete concurrency (no Approachable-Concurrency keys),
  destinations-only iOS. GREEN confirmed.
- **C6** (L165) ✅ DONE (GREEN 2026-07-02, app-setup 1.7 / Decision 4 = app-setup owns) —
  the skills already prescribed `SystemVersion+App.swift` everywhere (verified: no skill
  emits `<Module>Version.swift`); added an explicit tree annotation ("name for the TYPE +
  matching header, NOT `<Module>Version.swift`"). GREEN produced `SystemVersion+App.swift`.

### D. `fosmvvm-ui-tests-generator`
- **D1** (L185) ✅ DONE (GREEN 2026-07-02, ui-tests-generator 1.3) — Tier-1 note:
  `.uiTestingIdentifier(_:)` is a FOSMVVM `View` modifier (`import FOSMVVM`,
  `SwiftUI Support/View+Testing.swift` — path + DEBUG-gating verified against source),
  DEBUG-only/no-op-in-release so applied **unconditionally** (not `#if DEBUG`); don't
  define/copy it. Paired with same-string `XCUIApplication` accessor.
- **D2** (L191) ✅ DONE (GREEN 2026-07-02, ui-tests 1.4) — version-floor note for
  `ViewModelDisplayTestCase<VM>` (recent FOSTestingUI where `ViewModelViewTestCase`
  inherits it; verified in `ViewModelViewTestCase.swift`) + older-ref no-op-`ViewModelOperations`
  fallback. GREEN produced the right base class + fallback.
- **D3** (L203) ✅ DONE (GREEN 2026-07-02, ui-tests 1.4) — added "UI-Test Target Wiring
  (Xcode project)": (1) link FOS **directly, NOT via `SPMLibraries`** (separate process,
  trap doesn't apply, testing framework must not ride in the app); (2) source-include the
  shared contract module for the VM type + `.stub()`; (3) copy the server localization tree
  + `resourceDirectoryName:`. GREEN over-application guard: umbrella rule scoped to
  app-hosted unit tests; UI-test links directly.

**Pre-existing bug found + ✅ FIXED (David asked, 2026-07-02):** ui-tests SKILL.md
display-only checklist listed `operations stored from viewModel.operations` under "Views
WITHOUT operations" — a copy-paste contradiction with the "No operations property needed"
line above it. Replaced with a correct bullet (subclass `ViewModelDisplayTestCase<VM>`).

---

## Cross-cutting — resolve before/while editing

- **Dedupe overlaps into single edits:** B4 (L55≡L153); the **file/directory
  organization** story appears in B2 (L43), B-dir (L59), C1 (L135), C5 (L211) —
  tell it **once** in a canonical place and have the others reference it
  (Decision 2). The **`project.yml`** appears in L118/L171/L179 — one consolidated
  task (C3). **Version-line file** spans B/C (C6/L165) — one owner (Decision 4).
- **L59 (directory named for container)** ✅ DONE — folded into app-setup 1.5 "File
  Organization Conventions" (rule 2 + rule 3: grouping repeats across every layer).
- **The naming rules (A1–A3)** feed *both* the new dictionary and the
  serverrequest/viewmodel generators — author the dictionary first, then have the
  generators cite it (DRY: skills show the pattern, dictionary is the reference).

## Decisions for David (RESOLVED 2026-07-02)

1. **Naming dictionary home** → ✅ **`shared/` reference (`NAMES.md`)**. Authored as
   a reference doc in the `shared/` skill dir; the serverrequest- and
   viewmodel-generators cite it (DRY, single-source). (Affects A1–A3.)
2. **Canonical owner of file/directory organization** → ✅ **app-setup owns it**.
   `fosmvvm-swiftui-app-setup` tells the full file-org story once (C1/C5);
   viewmodel-generator references it. So B2/L59/C1/C5 don't triplicate.
3. **`fosmvvm-app-project-template.md`** → ✅ **Copy into this repo's `docs/work/`**
   (version-controlled with the skill), fold inline into app-setup, retire the Harbor
   standalone. (For C3, task-group 4.)
4. **Version-line file owner** — *taking default*: **app-setup** (C6), consistent
   with Decision 2's app-setup ownership of layout/naming.
5. **Sequencing** — *taking the doc's Recommended sequencing* (below) unless
   redirected.
6. **B5 (category-error) scope** → ✅ **Hard rule, enforced**. Generator scaffolds
   a domain-free VM by default + emits a DIP callout; a domain type in a VM is a
   category error. (Strongest SOLID stance.)
7. **Plugin-version cadence** → ✅ **One bump at end of batch** (single version bump
   + consolidated release note once item-#3 lands).

## Recommended sequencing (subject to Decision 5)

1. **Foundations that others cite:** A (naming dictionary) → Decision-2 file-org
   canonical doc. Nothing else should duplicate these.
2. **Quick, low-risk, self-contained conventions** (build confidence, small blast
   radius): B6, B9, B8, D1. Each is a tight RED→GREEN loop like today's stub fold.
3. **The viewmodel-generator conceptual/coupling set:** B1–B5, B7 — these define
   how a correct FOSMVVM VM is authored; B5 is the heaviest (get David's confirm).
4. **The app-setup blockers + template:** C1, C2, then C3 (fold the verified
   template), then C4/C5/C6. Highest customer value, most reconciliation.
5. **UI-test wiring:** D2, D3.
6. Bump plugin version per Decision 7; commit on the working branch; do not push.

## Verification protocol (apply to every edit)

- **Baseline (RED):** subagent using the *current* skill reproduces the wrong
  pattern. **Confirm (GREEN):** fresh subagent reading *only* the edited skill
  produces the right pattern **and does not over-apply** (the failure mode today
  was over-folding — actively test the "keep" cases too).
- Ground every change against SOLID → `FOSMVVMArchitecture.md` → code, and against
  the in-repo precedents the backlog cites (FOSShowcase `routes.swift` /
  `FOSShowcaseApp.swift`, `ObservedFleetState` stubs, etc.).
- Compile code templates against the real macros where feasible.
