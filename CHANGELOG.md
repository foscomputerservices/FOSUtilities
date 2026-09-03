# Changelog

All notable changes to **FOSUtilities** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.16.1] - 2026-09-03

### Fixed

- **Skill text teaches the envelope, not the decode order** — the serverrequest
  generator's credential-rejection section and the review's
  `no-defensive-error-for-credential-rejection` check both described the retired
  trial-decode; both now state the typed envelope 0.16.0 ships. Plugin 2.67.0.

## [0.16.0] - 2026-09-03

### Added

- **`expectFullViewModelTests(_:locales:version:)`** — the one-liner forwards a
  `version:` to `expectVersionedViewModel`, so a project whose version line is not
  `1.0.0` mints and checks baselines off its real line without hand-assembling
  the three primitives.
- **`expectTranslations` walks child ViewModels** — stored child ViewModels,
  optionals, and collections are descended, so a missing or blank translation on
  a row fails the parent's pass and names the path (`rows[0].label`).
- **The test encoder is strict** — `LocalizableTestCase.encoder(locale:)` now
  fails an encode on a key the store cannot resolve
  (`LocalizerError.missingTranslation`) instead of encoding an empty string;
  `JSONEncoder.localizingEncoder(locale:localizationStore:strictLocalization:)`
  exposes the switch. Production encoding is unchanged.
- **A UI-test harness with no YAML fails loudly** — `setUp(bundles:)` throws
  `RunError.noLocalizationYAML` when the bundles given yield no YAML; pass
  `bundles: []` to run key-echo on purpose. Key-echo is for a missing key, not a
  missing harness.

- **`CredentialChallenge`** — what a server demands of a credential, typed: `.bearer`,
  `.bearerRealm(_:)`, `.basicRealm(_:)`. A `ServerCredentialVerifier` attaches it to
  the rejection it throws; the transport renders `WWW-Authenticate` from it (the
  error token follows the rejection's reason, per RFC 6750), and the client reads
  the same typed value on the decoded error.

- **`LocalizableString.localized(case:parentType:)`** — localizes an enum case by
  the case itself: the YAML key is the enum's type under its parent and the leaf
  is the case name, with no string in user code. The replacement for feeding a
  raw value into `propertyName:`.
- **`fosmvvm-review` gains `no-string-backed-enums`** (cross-cutting, blocker) —
  an enum never takes a `String` raw value: the raw value is a public string door
  anyone can mint or parse, and it makes the case's spelling the user-facing text,
  which cannot localize. The truth statement is now in the architecture doc; the
  serverrequest, fields, and viewmodel generators and both DocC articles teach the
  plain-enum form. Plugin 2.66.0.

### Changed

- **`CredentialRejectedError` is plain data with synthesized `Codable`** — `reason`
  (`Reason.missing` / `.invalid`, replacing `code`/`Code`) and `challenge`
  (`CredentialChallenge?`, now carried across the wire). The hand-rolled
  discriminator envelope is gone. **Every `ServerRequest` error body now crosses
  the wire inside one typed envelope** encoded by `FOSMVVMVapor.ErrorMiddleware`
  and decoded by the client and the `FOSTestingVapor` harness, so the client
  never trial-decodes a body. Wire contract: a client and server on either side
  of this release see each other's error bodies as undecodable and fall to the
  status path; upgrade both together. The rejection no longer conforms to
  Vapor's `AbortError`: its 401 and `WWW-Authenticate` are assigned by
  `FOSMVVMVapor.ErrorMiddleware`, the one place an error becomes a response. A
  server that never installed it — a shape the review already blocks — now
  answers a rejection with Vapor's stock 500 instead of a plain 401; the
  pre-envelope skew fallback that relied on that plain 401 is retired with it.
- **The framework's own enums drop their `String` raw values** —
  `ServerRequestAction`, `FormInputType`, `FormInputOption.Autocapitalize` and
  `.Autocomplete`, and `CredentialRejectedError.Code` are plain enums with
  synthesized `Codable`. Their wire form is now the case-keyed object Swift
  synthesizes rather than a bare string; anything that decoded the old form
  needs the new one. `rawValue` on these types no longer exists.

### Fixed

- **`fosmvvm-review` evaluates project-scope clauses once** — a large area is
  now partitioned by module explicitly (about 100 files per dispatch), and the
  clauses that answer a question about the whole project ("no behavioral suite
  exists", "no committed `.VersionedTestJSON`", "the boot path never installs
  the error middleware") carry a `**Scope:** project` mark and run in exactly one
  partition; the aggregator collapses any duplicate that slips. Surfaced by the
  first full-project run, which split cross-cutting eight ways and reported one
  standing gap seven times. Plugin 2.65.0.

## [0.15.2] - 2026-09-02

### Changed

- **Doctor R4's testing-product remedy names both halves** — removing
  `FOSTesting` from a non-test target is only half the fix; the finding now also
  says to link the testing product directly on each test target that uses it,
  and why the one-doorway rule does not apply there. Surfaced by the first
  customer doctor run, where "remove the link" alone would have broken the
  test bundles.
- **The scaffolder CI job fans out** — the serial seventy-minute job (fast suite,
  walking skeletons, four generated-app UI-test runs) is now three jobs, the last
  a four-leg matrix over app shape × destination. Each leg builds the CLI and
  scaffolds its own app, so nothing waits on anything and the wall clock is the
  longest leg.

## [0.15.1] - 2026-09-02

### Added

- **A doctor finding can name a rule the project may disable** — `Finding.rule`
  (`DisableableRule`, one case: `app_sandbox`) marks the few findings a project
  may hold on purpose, such as an ops app that runs unsandboxed to reach local
  infrastructure. The JSON carries the identifier on those findings only, and the
  text report prints it under the finding. `fosmvvm-review` gains
  `doctor.disabled_rules` in `.fosmvvm-review.yml` (`rule`, `target`, `reason`),
  SwiftLint's vocabulary: a matched finding reports at warning with the reason
  beside it and no longer halts tier 2. Doctor's own verdict is unchanged — it
  reports facts; the skill applies the project's word. Plugin 2.64.0.

### Changed

- **Seeded memories state the settled signing shape** — the scaffold's
  `entitlement-is-a-symptom.md` and `xcode16-dynamic-spm-packages.md` carried an
  unratified 2026-08 evaluation that called `disable-library-validation` a
  required companion of `ENABLE_DEBUG_DYLIB` and floated retiring `SPMLibraries`.
  Both now state the shape the templates ship and `fosmvvm-doctor` audits: one
  `SPMLibraries` doorway, app-only embed with re-sign, hardened runtime off in
  Debug only, `ENABLE_DEBUG_DYLIB` unset, no entitlement. Surfaced by the first
  customer doctor run, where the stale note read as a doctrine conflict.
- **The scaffold's witnessed-tap helper retires** — the UI-test support templates
  drop their hand-rolled `tap(_:until:)`/`poll` pair, and the generated tests call
  FOSTestingUI's `tap(provenBy:)` directly: 0.15.0 ships the framework form, and
  the scaffold's pin now reaches it. The first pin-gated template edit to land
  through the release ritual's step 6.

## [0.15.0] - 2026-08-25

### Changed

- **`fosmvvm-review` checks the View/ViewModel structure** (plugin 2.31.0) — the
  `swiftui-view` area gained `view-conforms-to-viewmodelview` (blocker),
  `viewmodel-view-one-to-one` (blocker), and `preview-uses-previewhost` (warning).
  Previously every check in that area examined what a View body reads or mutates, so
  a project could render ViewModels from plain `View`s, share one ViewModel across a
  family of sub-views, and skip `previewHost` entirely without the review noticing.
  Existing projects should expect new blockers on first run. The triage globs also
  widened to `Sources/**/*Views/**/*.swift`: a target named `FooViews` rather than
  `Views` matched nothing before, and Views living in `Tile`/`Card`/`Row` files matched
  no filename pattern — those files were silently unscanned.

### Added

- **The test-host seam arrives with the App State** (plugin 2.63.0) — ruled: a
  skeleton app whose only environment is `mvvmEnv` correctly uses plain
  `.testHost()`, so the scaffold no longer ships a payload-free `TestConfiguration`
  and dead `presentView(configuration:)` overloads; the seam — a real
  `TestConfiguration` plus the `.testHost { }` decorator — arrives the day
  `.environment(appState)` does, and the app-setup skill teaches the pair together.
  `testhost-mirrors-vm-settings` now grades by what the environment holds: a
  project-authored `@Observable` behind a plain host is the finding, framework-only
  environment is at most a note, and a dead seam is scaffolding noise. Also ruled:
  scaffolds ship no `.VersionedTestJSON` baselines by design — the skeleton is a
  template the user replaces, their own test runs mint their own baselines, and
  `versioned-baseline-committed` is the reminder they get committed.

- **`fosmvvm-review` gains the five ruled-in candidates** (plugin 2.62.0) — the
  gaps the first full pipeline run surfaced, each now a check:
  `directives-spell-their-tool` (a misspelled lint token is inert prose that reads
  as governance), `deferral-pointers-resolve` (a comment deferring work must cite a
  document that exists — path-drifted spellings of a real ledger are the common
  case), `versioned-baseline-committed` (a never-committed `.VersionedTestJSON`
  baseline means the wire-shape canary can never fire), blocker
  `server-installs-the-error-middleware` (verifying *which* module's middleware —
  `Vapor.ErrorMiddleware.default` type-checks while installing the wrong one), and
  `views-dont-mint-prose` (user-visible prose is never a view-body literal, display
  or operation-argument alike; the view generator's Hardcoding Text rule gained the
  same extension).

- **`fosmvvm-review` closes the coverage register for real** (plugin 2.61.0) — the
  last gap, caught open by a same-day bookkeeping audit, ships as `serverrequest`
  blocker `live-invalidation-is-a-pair`: for a `.live` screen, register a dependency
  on what the projection reads and invalidate projections of what changed, both
  naming the same entity — an emit nothing registered nudges nobody, a registration
  nothing emits never refreshes, and a hand-driven Fluent write outside
  `liveTransaction` silently skips the refresh. Detection pairs the registration and
  emit sets by entity expression, enumerates `+Live.swift` and `LiveInvalidation/`
  files before judging (a truncated sweep manufactures dead-emit findings), and
  names the conformant sentinel-projection idiom — one shared `static let observed`
  referenced by both halves. The area's globs now reach factory files.

- **`tap(provenBy:)`** (FOSTestingUI) — taps a tagged view and proves the tap landed
  by the effect it causes, re-tapping once inside the dropped-first-event window a
  freshly launched app exhibits. The witness is any observable effect — a view
  appearing, the transported operations recording becoming readable — and the poll
  absorbs dispatch-and-transport observability only, never operation behavior: a
  stub operation records synchronously, so there is no "work" to wait out. Retires
  the hand-rolled tap-then-poll helpers consumers had to carry. Paired review check
  `stubs-record-they-dont-do` (plugin 2.60.0) guards the frame from the other side:
  a stub Operations body that awaits real work, sleeps, or reaches network/storage
  turns a wiring test into a timing-dependent behavior test and is flagged.

- **The bootstrap templates are brought to the review standard** — the first full
  `fosmvvm-review` run over a fresh scaffold found the walking skeleton drifting
  from doctrine ratified after it shipped; the templates now hold it. The card
  gains a `CardFields` form contract (protocol + localized en/es messages) adopted
  by both the wire body and the record; `CardViewModel` derives `vmId` from the
  record's identity threaded through the factory, and every screen ViewModel uses
  the type-keyed singleton form; the card gets its own `CardView`, registered for
  testing; the create request is renamed noun-first (`CardCreateRequest`); the
  server installs FOSMVVMVapor's `ErrorMiddleware` (without it, Vapor's stock
  middleware flattened typed validation rejections to bare 500s — caught by the
  scaffold's new tests); `BoardServerTests` drives both requests through the typed
  test door, including an invalid-body rejection; stubs use the reserved-fake
  vocabulary; the failed-boot shutdown error is logged; inert lint directives are
  removed; the scaffold ships `docs/deferrals.md`; and the public Operations
  surface carries customer-frame DocC with call examples.

- **`fosmvvm-review`'s two-tier pipeline is qualified end-to-end** (plugin 2.59.0) —
  the first full run of the doctor-into-skill flow (structural halt exercised on a
  seeded error; nine areas dispatched on the clean re-run) fed fixes back into the
  skill text: doctor routing judges the resolved pin rather than the `Package.swift`
  requirement, route 2 documents `--shape` and both routes' non-zero exit, the
  markdown report's finding sections are explicitly tier-2-only (doctor detail lives
  in the Structure section), the coverage-state section reflects the closed register,
  and the `serverrequest-test` area's globs now match `*ServerTests.swift` — the
  scaffolder's own server-test naming had silently escaped the area.

- **`fosmvvm-review` closes the coverage register** (plugin 2.58.0) — final register
  check `suites-serialize-shared-state` (`cross-cutting`, warning): Swift Testing
  parallelizes by default, so suites touching shared mutable state — singletons,
  `static var`s, the process environment, fixed-path fixtures — carry `.serialized`.
  The check states the trait's boundary honestly: it protects within a suite only,
  so cross-suite state needs a test-owned gate scoped to the racing window or
  dependency injection, and findings name one of those. All three test generators
  gained the same statement (§Parallelism and Shared State). With this, every gap
  in the coverage ledger's register (G1–G20) is closed.

- **`fosmvvm-review` reviews documentation discipline** (plugin 2.57.0) — new
  `cross-cutting` check `docc-serves-the-customer`: DocC serves the code's customer
  (lead with how to call it, state the contract), design rationale belongs in
  design/plan prose (relocated, not deleted), and internal comments exist only for
  genuinely non-obvious constraints — theatre is flagged. Undocumented and
  example-free public API is aggregated into one finding graded by whether the
  symbol has customers, and detection walks up past the attribute stack
  (`@ViewModel`, wrappers) so the framework's most idiomatic types are not
  misreported as undocumented.

- **`fosmvvm-review` asks the existential question** (plugin 2.56.0) — new
  `cross-cutting` check `existentials-answer-the-question`, under the ruled scope:
  passing `any P` as a parameter is fine; stored existentials, `[any P]` collections,
  and existential returns must answer the principle's own question — was there any
  other way? Findings state the cost (dispatch, boxing, lost type identity, `Codable`
  friction) and name the alternative (generic, primary associated type, enum over a
  closed conformer set, concrete type). Named answers that are not hits: the
  injected-dependency seam where generics would metastasize type parameters, the
  seam's transitively-erased resources, third-party protocol idioms, and genuinely
  open heterogeneous mixes.

- **`fosmvvm-review` guards the behavioral-test channel** (plugin 2.55.0) — new
  `cross-cutting` check `behavioral-suite-standing`: behavioral suites project from
  requirements + ratified design in a context that never saw the implementation, so
  review verifies only their standing (a visible requirements register with no suite
  is the gap) and their code-visible isolation (`@testable import` or
  implementation-module imports inside a `*BehavioralTests` suite). The check
  explicitly forbids reviewers from judging behavioral assertions against the code —
  a disagreement between the channels classifies upward, never as a finding against
  the test.

- **`fosmvvm-review` enforces tests-never-touch-production** (plugin 2.54.0) — new
  `cross-cutting` blocker `tests-never-touch-production`: a test's isolation is
  constructed, not inherited. The check resolves each test's execution edges and fires
  on mutation paths that can reach non-test infrastructure — write requests at real
  deployment URLs, database bindings read from the ambient environment, pattern-keyed
  cleanup deletes against shared targets. A production hostname literal handed to a
  pure function is inert fixture data, and live external reads are flakiness notes,
  not this blocker. The Fluent generator now states the ephemeral-database rule
  (`.sqlite(.memory)`, never an inherited `DATABASE_URL`) beside its test templates.

- **`fosmvvm-review` enforces the request naming dictionary** (plugin 2.53.0) — new
  `serverrequest` check `request-names-follow-the-dictionary` (NAMES §1a–1c): writes
  and semantic actions are noun-first (`UserCreateRequest`, never `CreateUserRequest`),
  screen reads are the ViewModel's stem with no verb, raw reads keep a noun-first
  `Show`. Detection enumerates `ServerRequest` conformers — never `*Request`-named
  types, so domain types like a GitHub `PullRequest` cannot false-positive — and
  classifies by contract before testing the leading token, so a verb-derived word
  inside a screen noun is not a hit. Wholesale verb-first drift gets one area-wide
  finding framed as rename items per the dictionary's do-not-add-more callout. Also
  carries NAMES §2's clause: a display type renamed only to dodge a harmless
  cross-module collision is flagged — names are chosen for meaning.

- **`fosmvvm-review` flags hand-rolled framework products** (plugin 2.52.0) — new
  `cross-cutting` check `no-hand-rolled-framework-products`: helpers re-implementing
  what the api-catalog already lists (JSON/Codable glue, wire-format dates, network
  mocks, semantic versions, async button/error-alert surfaces) are flagged by the
  contract semantics the hand-roll loses, and framework internals duplicated
  downstream get the upstream report as their only remedy. The version floor is
  mandatory before any finding: a consumer pinned below the API's release gets an
  adoption candidate, not a violation — blaming code for an API its pin cannot see is
  the check's characteristic false positive. Detections resolve against the catalog,
  never memory; network plumbing stays with `server-calls-use-the-request-door`, and
  UI-test helpers keep `no-hand-rolled-element-helpers`.

- **One top-level App State becomes doctrine, and `fosmvvm-review` enforces it**
  (plugin 2.51.0) — new architecture statement (One Top-Level App State, Not an
  Environment of Entries) and its `view`-area check `one-top-level-appstate`: the
  environment injection surface is `MVVMEnvironment` plus one top-level Application
  State `@Observable final class`, with values reaching ViewModels as scalars through
  `.bind(appState:)`. Every custom `@Entry`/`EnvironmentKey` and every additional
  environment-vended `@Observable` is an injection obligation previews and test hosts
  pay — a missing `.environment(...)` crashes an `@Environment(X.self)` read and
  silently defaults a custom key — and the single class doubles as the persistence
  seam for resuming where the user left off. SwiftUI built-ins, the framework's own
  surface, and component-vended styling entries are named non-hits. The
  `fosmvvm-swiftui-app-setup` skill's multiple-environment-values section now teaches
  the discipline instead of inviting the growth.

- **`fosmvvm-review` flags generic error architectures** (plugin 2.50.0) — new
  `viewmodel` check `no-generic-error-architecture`: error UI follows the same
  ViewModel → View pattern as everything else, so each error scenario gets its own
  client-hosted ViewModel taking the specific `ResponseError` (or routes the typed
  throw to the framework's localizing `.alert(error:)` surface). Detection covers the
  unifying display protocol, the one-ViewModel-for-all-errors shape, central
  error-rendering middleware, and the erosion signal — typed errors erased to
  `localizedDescription` for display. Named non-hits keep the doctrine's own shapes
  safe: a shared toast template over per-error ViewModels is the pattern held, not
  violated, and an error-binding routed to the framework alert is transport, not
  architecture.

- **`fosmvvm-review` catches computed properties on wire-crossing ViewModels**
  (plugin 2.49.0) — new `viewmodel` check `computed-properties-dont-serialize`: only
  stored properties exist in the encoded JSON, so a computed presentation value is a
  blocker where the encoded JSON is what renders (a live Leaf template reading it
  misevaluates silently — sections that never show, badges that never appear) and a
  warning where a decoded Swift instance recomputes it, since the derivation still ran
  on the wrong side of the wire. Property-wrapper declarations and the computed
  `operations` idiom are carved out; derive-on-the-owner (a value type's computed
  frozen into a stored VM property at init) is named as the correct shape. Verified
  against a drifted Leaf codebase (five live blocker groups) with a zero-false-positive
  falsifier run on a SwiftUI client. The `view` area's template-read clause now
  resolves reads to **stored** properties only, pairing the two sides.

- **`fosmvvm-review`'s view area goes multi-surface** (plugin 2.48.0) — `swiftui-view`
  becomes `view`: one area, per-surface detections for SwiftUI, Leaf, and React, since
  all three render the same edge (View ← ViewModel + ratified design). The skill's
  scope widens with it — `.leaf`/`.tsx`/`.jsx` files are now reviewable; the Swift-only
  scope had silently exempted two of the three surfaces. New check
  `views-render-they-dont-shape`: views render data, they never compose, format, or
  reorder it — detection keys on the VM's own confessing property names (`…Prefix`,
  `…Suffix`, `…Part1/2/3`) before syntax, carves out identifier interpolation, and
  knows `#date(…)` over a `Localizable` cannot work at all. The Leaf clauses carry the
  decisive framework fact: LeafKit renders template↔VM drift silently empty — a page
  can read a ViewModel that no longer has its properties and ship blank with zero
  errors, so review is the only net. Verified against a drifted Leaf codebase; React
  clauses ship statically checked pending a verification target.

- **`fosmvvm-review` gains the `serverrequest-test` area** (plugin 2.47.0) — the wire
  contract's test-side twin, verified drive-by-drive against a drifted test tree
  before shipping. `request-test-uses-the-typed-door` (blocker): tests drive
  ServerRequest routes through the typed door — `app.testing().test(request, locale:)`
  or `processRequest` — never hand-glued paths and hand-encoded queries, which go
  green against their own invention while the production client fetches something
  else; when the glue mirrors a bespoke controller mount, the finding names the
  production side as the broken party and says the remedy spans both trees.
  `request-test-covers-the-contract` (warning): every request has a typed-door test,
  declared errors are provoked and caught typed (decode-guard declarations accept a
  decode-contract test instead), validating write bodies get one invalid-body test,
  and writes assert effects. The serverrequest-test generator caught up: the shipped
  Fluent harnesses over hand-rolled helpers (naming the async-boot trap), and typed
  rejection asserts over status-sniffing.

- **`fosmvvm-review` checks the write body's contract** (plugin 2.46.0) —
  `requestbody-adopts-its-fields` in `serverrequest`: a write request's body carrying
  user-entered field values must adopt the entity's Fields protocol, with a `validate`
  that actually reaches the Fields helpers — the compiler forces `ValidatableModel`
  onto Create/Update/Replace bodies but cannot stop a `nil`-returning `validate` from
  satisfying it emptily. The enumeration covers the whole write family including
  `ReplaceRequest` and write-actioned plain `ServerRequest`s; the user-values-versus-
  operation-parameters discriminator keeps machine bodies (control-channel commands,
  log tails, CLI keys) out. Verified two-sided before shipping: a drifted codebase
  supplied the true positive, and a zero-Fields codebase produced zero false blockers.

- **`fosmvvm-review` checks the VM's snapshot discipline** (plugin 2.45.0) —
  `vm-holds-scalars-only` in `viewmodel`: a `@ViewModel` type storing an `@Observable`
  class reference is a blocker — directly, buried one level inside an owned value type,
  or laundered behind a stored existential whose conformers include one. Detection
  names the compile-gate fingerprints (a `Codable` retrofit, `@MainActor`/`@unchecked
  Sendable`) and carves out the framework's own patterns: the computed `operations`
  minting idiom and `@FormFieldModel` wrapper backings. Verified against a drifted
  client codebase before shipping. Also fixes the `FormFieldModel` DocC example,
  which showed `@ViewModel final class` against the macro's struct-only rule.

- **`fosmvvm-review` checks the wire door** (plugin 2.44.0) — `server-calls-use-the-request-door`
  in `cross-cutting`: a hand-built HTTP call to the app's own server (raw `URLSession`,
  hand-assembled `URLRequest`, an app-owned socket dialer) is a blocker — the typed
  `ServerRequest` door is the way, through either `processRequest` overload; hand-rolled
  plumbing to external services is a warning where FOSFoundation's `url.fetch()` /
  `send(data:)` / `delete(data:)` front door exists, with `errorType:` when the error
  body is an owned type. Detection keys on the transport, resolves CLI hosts through
  injected bases, and lets client role win over target membership. Where the door
  genuinely cannot express an operation (raw streaming, ranged reads, socket channels),
  the disposition is a suppression naming the gap and its upstream issue — findings
  converge instead of re-firing forever. Verified against a drifted client-server
  codebase before shipping. Leaf/JS template fetches are TBD, reported at warning
  when encountered.

- **`fosmvvm-review` gains the `datamodel` area** (plugin 2.43.0) — the Model layer's
  first review home, five checks verified against a drifted Fluent codebase before
  shipping. The firm junction-table principle is now enforced (`modelid-outside-id`:
  raw identity fields outside `@ID`, including identities smuggled through JSONB
  structs and `String` fields, need express, expiring documentation); form-backed
  models must adopt their Fields protocol; the model and the net of its migration
  sequence must agree per dialect; required-ness must agree between Fields and
  schema; and a stored enum decoded with a coalescing fallback into a meaning-bearing
  case is flagged as the silent history-rewrite it is. The fluent-datamodel generator
  caught up in the same stage: `@OptionalParent` for same-database optional FKs, no
  `[UUID]` identity arrays (its own field-type table had offered one), honest enum
  decodes, and a pointer to the post-2.1 framework surface.

- **`doctor` R13 and R14 — the shared-module pair.** Two rules join the table (now
  fourteen), both errors, both running for every shape including shared-library:
  R13 flags `@ViewModel` declarations living outside a shared ViewModels module
  (`Sources/ViewModels` or `Sources/…ViewModels`) — types shared by name instead of
  by module drift apart; R14 flags server imports (`Vapor`, `Fluent*`, `Leaf`,
  `FOSMVVMVapor`, …) inside that module — the dependency points one way, and the
  server-side Factory is the one place that sees both worlds. Test sources are
  exempt: a ViewModel declared in a test target is a fixture.

- **`doctor --json`** — both doctor doors emit the report as stable, sorted-key JSON
  (`findings` with `severity`/`target`/`summary`/`remedy`, `unchecked`, and a
  `hasErrors` verdict), and `Doctor.Report` gains a `json` property beside `text`.
  The `fosmvvm-review` skill (plugin 2.42.0) now runs doctor as its tier-1 structural
  pass: structural errors halt area review — fix structure first, so the area reviews
  find what they expect where they expect — and doctor findings count in the review
  report's single summary, so the existing CI gate covers both tiers without forking.

- **`doctor`** (FOSMVVMBootstrap) — audits an existing project against the rules the
  scaffolder generates by, and reports what has drifted. Two doors, one engine: a
  `swift package fosmvvm-doctor` command plugin (nothing to install for a package that
  already depends on FOSUtilities) and a `fosmvvm-bootstrap doctor` subcommand. It
  reports and never rewrites; every finding names the setting and the value to use.
  Twelve rules cover the failures that surface far from their cause — a second direct
  link to a shipping FOS product, a testing product linked outside a test target,
  embedding without sign-on-copy, a misspelled `BUILD_LIBRARY_FOR_DISTRIBUTION` that
  Xcode silently ignores, an unpinned `TEST_HOST`, a missing `DEVELOPMENT_TEAM`,
  manual code signing, a hardened runtime in Debug, entitlements that do not match the
  shape, stray localization YAML, a test plan pointing at re-minted target
  identifiers, and deployment targets that disagree with `Package.swift` or fall below
  the FOSUtilities floors. Findings are errors or warnings, and the command exits
  non-zero only on errors, so it works as a build step or a generator-skill gate.
  `--shape` is optional: the two shape-conditional rules report as unchecked rather
  than guess. The same rules judge every project the scaffolder emits, in the walking
  skeletons — so the table and the templates cannot drift apart silently.

## [0.14.0] - 2026-08-23

### Added

- **FOSMVVMBootstrap** — the FOSMVVM project scaffolder now ships in FOSUtilities.
  The `fosmvvm-bootstrap` CLI interviews for a project configuration (or reads one
  from `--config` JSON) and emits a complete, buildable FOSMVVM project in one of
  three shapes: local-only (SwiftUI app, no server), client-server (SwiftUI app +
  Vapor web service sharing a ViewModels contract), or shared-library (SPM library).
  Generated apps come with ViewModelOperations wiring, YAML localization stores, and
  a UI-test harness; app projects are emitted as Xcode 16 synchronized-folder
  projects through XcodeGen, with `project.yml` remaining the source of truth.
  Generated projects pin FOSUtilities to the release that generated them, and
  `--verify` runs each shape's verification doors (`swift build`/`swift test`,
  `xcodegen generate`, `xcodebuild`) inside the generated project before handing
  it over.

## [0.13.3] - 2026-08-22

### Fixed

- **`tap()` lands on macOS** (FOSTestingUI) — on macOS, `XCUIElement.tap()` and every
  coordinate-synthesized tap dispatch without failure and never land (measured on 27
  beta, one variable at a time via the probe's composite row: native `tap()` on the
  live, hittable, resolved control — "fired 0"; app-anchored and overlay-anchored
  coordinate taps — "fired 0"; `click()` on the same control — green). Every native
  dispatch now goes through the platform's pointer verb (`click()` on macOS, `tap()`
  elsewhere), and the aimed path resolves its snapshot back to a live element to
  receive it. This also cures the "synthesized taps on native-bridged bar items do not
  land" regression the probe README recorded on this beta — the probe's tab and toolbar
  tap tests pass again. Two supporting hardenings: `XCUIApplication.frame.origin` can
  be non-finite on macOS (measured: `(inf, inf)`), so app-anchored offsets only
  subtract a finite origin; iOS behavior is unchanged (its verb remains `tap()`, its
  origin is zero, and its measured-green app-anchored fallbacks are untouched).

## [0.13.2] - 2026-08-21

### Added

- **`setUp(bundles:resourceDirectoryName:appBundleIdentifier:locales:)`** (FOSTestingUI) —
  `ViewModelDisplayTestCase` / `ViewModelViewTestCase` harnesses can now localize from
  several bundles merged into one store (the harness's own YAML plus another target's
  resources); the existing single-`bundle:` form delegates to it.

### Changed

- **`Localizable.text` is `@MainActor`** (FOSMVVM) — the SwiftUI resolver view it
  constructs belongs on the main actor; call sites in SwiftUI `body` contexts are
  unaffected.

## [0.13.1] - 2026-08-21

### Added

- **`task(error:)` / `task(id:error:)`** (FOSMVVM) — async twins of SwiftUI's `task`
  modifiers for view-lifetime loads: the action becomes throwing, and a thrown error lands
  in the required `error: Binding<Error?>` (cleared on each start — the binding holds the
  outcome of the most recent invocation). Cancellation never reaches the binding: view
  teardown and `id`-change restarts deposit nothing, so a superseded load can never speak
  over the current one and teardown never puts a `CancellationError` in an alert. Pairs
  with `alert(error:)` and the async Button forms on one screen-level binding. The new
  *Async Action Lifecycle and Cancellation* DocC article draws the full contract,
  situation by situation.
- **`LocalizableTestCase.loadLocalizationStore(bundles:)`** (FOSTesting) — loads one
  merged `LocalizationStore` from several bundles, so a suite can verify server-based
  ViewModels against the same YAML the server serves alongside the test bundle's own
  client-hosted localizations.

### Changed

- **Async Button cancellation never reaches `error`** (FOSMVVM) — the engine's deposit
  guard now also filters the language's `CancellationError` sentinel type: a
  `CancellationError` thrown by a *non-cancelled* invocation is discarded instead of
  presented, making the quiet exit (throw `CancellationError` to end with nothing shown)
  a supported idiom. The filter is sentinel-only — errors that describe a cancellation in
  domain vocabulary still deposit and present. Every discarded outcome is recorded with a
  debug notice. The full lifecycle contract is drawn situation-by-situation in the new
  *Async Action Lifecycle and Cancellation* DocC article.
- **View tests no longer require YAML** (FOSTestingUI) — `ViewModelDisplayTestCase` /
  `ViewModelViewTestCase` setUp now resolves any localized string that has no translation
  in the harness bundle to visible placeholder text derived from its key, instead of the
  empty string. SwiftUI collapses empty-labeled elements to zero surface area, which made
  such elements unreachable by XCUI even with a `uiTestingIdentifier()`; with the
  placeholder they stay tappable. Don't assert on placeholder content — localization
  completeness belongs in `LocalizableTestCase.expectTranslations()`.

### Fixed

- **`LocalizationStore` convenience dispatch** (FOSMVVM) — the index-less
  `keyExists(_:locale:)` and `t()` conveniences now dispatch to the store's `keyExists` /
  `translate` implementations; previously both always derived their answer from `value()`,
  silently bypassing stores that customize those requirements.

## [0.13.0] - 2026-08-20

### Added

- **Async Button surface** (FOSMVVM) — every `Localizable` Button form (and the ViewBuilder
  forms) gains an async twin: the action is `@Sendable () async throws -> Void`, a thrown
  error lands in a required `error: Binding<Error?>` (cleared on each launch — the binding
  holds the outcome of the most recent invocation), and an optional caller-owned
  `AsyncButtonActivity` adds deterministic re-entry refusal plus running-state for
  `disabled(_:)` and progress display. Providing the cancel face — `cancelTitle:` (with
  optional `cancelSystemImage:`/`cancelImage:`) or a phase-aware label closure — is what
  enables cancellation: the button becomes two-faced, tap-to-start / tap-to-cancel, with a
  `cancelling` phase while the work unwinds cooperatively and protection against taps aimed
  at a face that just flipped. The titled forms are generated by the overload sweep's new
  Stage 6b (`--emit-async-only` re-renders just that file from the checked-in SDK stamp).
- **`LocalizableError` + `@LocalizableError`** (FOSMVVM) — opt an error type into
  user-presentable, YAML-localized messaging, composed exactly like a ViewModel: declare
  the message with `@LocalizedString`/`@LocalizedSubs`, let the macro provide the
  localization plumbing, and expose it as `localizedMessage`. The server's
  `ErrorMiddleware` resolves the message as it encodes the thrown error, so the client
  displays it with no localization store of its own. Client-*created* errors declare
  `options: [.clientHosted]` (the `ClientHostedLocalizableError` marker) and resolve at
  presentation via `localized(mvvmEnv:locale:)` — the same localizing round-trip a
  `ClientHostedViewModelFactory` runs for a ViewModel, against the app's own YAML.
- **`alert(error:title:message:dismissButtonLabel:)`** (FOSMVVM) — one View modifier
  presents whatever lands in the shared error binding: shows while non-`nil`, clears on
  dismissal, localizes `LocalizableError` conformers through the client store (others show
  their debug description), and fills the message's `%{error}` substitution point at
  presentation. Designed as the single presentation point the async buttons' `error:`
  parameter feeds.

## [0.12.7] - 2026-08-20

### Fixed

- **`tap()` and `setText(_:expecting:)` clear a keyboard-occluded target before aiming**
  (FOSTestingUI) — a raised software keyboard occludes everything beneath it, and none of
  XCUITest's signals notice: the covered control exists, reports hittable, and holds a
  stable frame, so a settled frame could still be an occluded frame and the gesture landed
  on the keys, silently. Every aim now checks the *aimable band* — the app frame clipped at
  the keyboard's top edge, with clearance for the accessory bar the reported frame omits —
  and scrolls the target clear with strokes derived from the band itself, so short screens
  cannot be undershot. Over existing text, `setText` additionally requires the edit menu to
  rise before typing — geometry understated occlusion twice in the field; the menu cannot —
  so an unproven selection is never typed over. Verified at all device sizes: the guards
  are load-bearing on the largest iPad as much as the smallest iPhone.
- **`tap()`'s coordinate path re-checks its premise after settling** (FOSTestingUI) — the
  aimed-coordinate branch exists for a resolved control that sits away from the tag's
  midpoint, but dispatches were measured whose computed coordinate equaled the tag's own
  midpoint: the disagreement had evaporated during the settle, and the element path's
  built-in quiescence waiting had been forfeited for nothing. When the frames agree again
  at dispatch time, the tap now takes the element path.
- **`TestDataTransporter` survives a scrolling parent** (FOSMVVM) — a zero-sized transporter
  rendered behind an opaque host inside a `ScrollView` was pruned from the accessibility
  tree entirely, making `viewModelOperations()` throw for exactly the views
  `registerTestView(_:scrollable:)` serves. The transporter now fronts its host at 1×1
  with hit-testing refused — inert for the UI under test, present for the reader.

## [0.12.6] - 2026-08-19

### Fixed

- **Missing environment objects now stop with a teaching diagnostic instead of a bare trap**
  (FOSMVVM) — a view reaching `Localizable.text`, `ViewModelView.bind()`, or a
  `FormFieldView`'s validation display without the required `MVVMEnvironment` or
  `Validations` installed in the SwiftUI environment used to stop with only
  `EXC_BREAKPOINT` inside SwiftUI's `@Environment` read — no message, no named cause. Each
  of those reads now reports, to stderr and the crash log, which API needed the object and
  the exact `.environment(...)` installation that fixes it. The same treatment replaces the
  placeholder failure when `Localizable.text` finds `MVVMEnvironment` installed but no
  client localization store: the diagnostic now names both configuration doors
  (`resourceBundles:` / `localizationStore:`) and surfaces the underlying resolution error.

## [0.12.5] - 2026-08-18

### Added

- **`UITestingElement.setToggle(_:)` flips and verifies** (FOSTestingUI) — a `Toggle` with a
  leading label exposes one accessibility element spanning label and switch, so a midpoint
  tap — XCUITest's default aim — lands beside the switch and flips nothing, and the miss is
  silent. `setToggle(true)` aims at the switch itself, does not return until the switch
  reports the requested state, and retries a missed gesture — the reported state, not the
  tap, is what lets it return, so a retry can never mask a wrong flip. A `Toggle` already
  in the requested state is a verified no-op, so the call is idempotent, and state SwiftUI
  derives from the flip is readable immediately with no wait. iOS-certified; other
  platforms fail loudly until a fixture pins them. Pinned in `Tools/UITestingProbe` on a
  leading-label `Toggle` — the geometry whose merged element defeats the midpoint tap.

### Fixed

- **`selectPickerItem(_:)` reaches items clipped behind a long menu's internal scroll**
  (FOSTestingUI) — a menu with more rows than its presented card can show clips part of the
  list, but the accessibility tree keeps reporting the clipped rows with on-screen frames at
  the positions they would occupy: every frame-based visibility signal passes, the tap lands
  on the scrim below the card, and the menu dismisses without selecting. `selectPickerItem`
  now scrolls within the presented menu when the plain tap does not commit — bounded flings
  in both directions from the checked item (where the menu anchors its scroll), steered by
  the row's hittability and still gated solely by the selection-committed postcondition, so
  the scrolling can never mask a wrong selection. Items beyond the bounded reach fail loudly
  with a message that names the fold. Pinned in `Tools/UITestingProbe` by an overflowing
  menu selected into on both sides of the anchor, including a row so deep it starts outside
  the accessibility tree.

## [0.12.4] - 2026-08-18

### Added

- **`UITestingElement.waitForStableFrame()` waits out a moving frame** (FOSTestingUI) — a view
  that is still being presented (a menu row while the menu animates in) already *exists*, so an
  existence wait passes, yet a coordinate computed from its in-flight frame lands where the view
  *was* and the tap silently misses. `tap()` now settles automatically before its coordinate
  taps (under a short internal budget, so a frame that never settles — a repeating animation —
  costs ~2s, not a stall); call `waitForStableFrame()` yourself only before interactions that
  bypass `tap()`: a native double-tap, addressing a control's child elements, asserting a frame.
  Returns `false` immediately for a view that left the hierarchy — a gone view can never settle.
  Pinned in `Tools/UITestingProbe` by a menu-row selection loop that allows zero missed taps.

- **Views designed for a scrolling parent declare it at registration** (FOSMVVM) —
  `registerTestView(DeviceCardView.self, scrollable: true)` presents the view under test
  inside a vertical `ScrollView`, as production does. Presented bare, a view designed for a
  scrolling parent is taller than the window: content compresses and overlaps, bottom
  controls get buried beyond any tap's reach, keyboard avoidance displaces the whole content
  instead of scrolling, and XCUITest's scroll-to-visible has nothing to scroll. The
  declaration is a design fact, not a per-test option — there is no override, and views
  registered without it present bare, byte-for-byte as before. Pinned in
  `Tools/UITestingProbe` by a card taller than any window: its buried field is reachable
  when registered scrollable and provably off-screen when not.

- **`UITestingElement.selectPickerItem(_:)` selects and verifies** (FOSTestingUI) — driving a
  menu-style `Picker` by hand is a five-step ceremony (open, wait for the row, settle, tap,
  verify the selection committed), and skipping the last step is a race: state SwiftUI derives
  from the selection is not yet readable when the tap returns. `selectPickerItem` owns the
  whole ceremony and does not return until the collapsed control reports the selection, so
  the very next read of selection-derived state needs no wait. A missed gesture is retried
  once and re-verified — the postcondition, not the tap, is what lets it return, so the retry
  cannot mask a wrong selection. Serves `Picker` only (a `Menu` of actions has no selection
  to verify; the failure message teaches the distinction), certified by fixture on iOS —
  other platforms fail loudly naming the gap until a fixture pins them. Pinned in
  `Tools/UITestingProbe` by a six-round selection cycle whose derived-state reads are
  deliberately un-waited.

- **`UITestingElement.setText(_:expecting:)` replaces and verifies** (FOSTestingUI) — every
  hand-rolled text-entry helper walks the same road: taps aimed at row frames that miss the
  field, select-all degrading to caret placement and prepending, typing racing focus, delete
  counts depending on where the caret sat. `setText` owns the interaction: it resolves the
  real text control the tag marks, focuses it, proves the focus, replaces the value with no
  caret or selection assumptions, and does not return until the field reads back exactly the
  expected text — retrying the whole sequence once with a different gesture strategy, and
  failing loudly with the identifier, the entered text, and what the field actually reads.
  `expecting:` serves formatter-backed fields ("45" renders "45.00"), committing the entry
  before verifying; `SecureField`s are excluded with a teaching failure (bullets defeat any
  honest read-back). iOS-certified; other platforms fail loudly until a fixture pins them.
  Pinned in `Tools/UITestingProbe` across prefilled, empty, trailing-aligned, `.numberPad`,
  and formatter-backed fields, through row-spanning and direct tags.

- **`type(_:)` proves focus before typing** (FOSTestingUI) — it now rides the same
  aim-and-focus machinery as `setText` and fails naming the tag when focus never arrives,
  instead of XCTest's opaque "neither element nor any descendant has keyboard focus". Its
  append-at-caret semantics stay deliberately unverified — appending has no general "what
  should the value be now" — and its documentation now steers replacement intent to
  `setText`.

### Fixed

- **A tag spanning a composite resolves to the control it contains** (FOSTestingUI) — a tag on
  a row holding a caption and a field covers both, and the row's midpoint can miss the field
  entirely (measured: 1pt into the caption/field gap on one device width, inside the caption on
  another). Resolution now descends into such a composite: `tap()` aims at the control's own
  midpoint instead of the row's, and `label`/`value`/`isEnabled` answer with the control's
  state where they previously answered from the row's container — empty. When a composite
  holds several controls, the first in document order answers; tag the control itself to
  address one precisely. Tags placed directly on controls are unaffected. Pinned in
  `Tools/UITestingProbe` by caption + field rows with the midpoint in the gap and inside the
  caption.

## [0.12.3] - 2026-08-17

### Fixed

- **The keyboard-dismissal control survives keyboard avoidance** (FOSMVVM's `testHost()`, which
  `dismissKeyboard()` (FOSTestingUI) rides) — when the focused field would be covered and no
  scroll container absorbs it, SwiftUI shifts the application's whole content upward, and
  0.12.2's top-leading overlay rode that shift off screen (measured at y = -48 in a consuming
  app): the coordinate tap landed on nothing, the keyboard stayed up, and `dismissKeyboard()`
  failed at its own second gate blaming corner occlusion it could not have. The control now
  lives in its own tiny window above the application's — outside the application's layout
  entirely, so nothing the content does can displace or cover it — and the failure message
  names the causes that remain. Reproduced in `Tools/UITestingProbe`'s new keyboard-shift
  scenario (tall filler, `.numberPad` field near the bottom, no scroll container), which is
  the regression test 0.12.2 was missing.

## [0.12.2] - 2026-08-17

### Added

- **`XCUIApplication.dismissKeyboard()` puts the software keyboard away** (FOSTestingUI, with
  FOSMVVM's `testHost()`) — XCUITest offers no way to dismiss the keyboard, and a `.numberPad`
  keyboard has no Return key, so once a test typed into one the keyboard stayed up: a tap aimed
  at a control the keyboard covers lands on the keyboard instead, and the test fails downstream
  with no visible error at the tap. The workaround in circulation — tapping a neutral view —
  resigns nothing and silently does not work.

  ```swift
  app.uiTestingElement("quantityField").type("42")
  app.dismissKeyboard()
  app.uiTestingElement("saveButton").tap()
  ```

  On iOS, `testHost()` now plants an invisible, always-reachable control that resigns first
  responder; `dismissKeyboard()` taps it and waits for the keyboard to leave. With no keyboard
  up the call is a no-op, so call sites stay unconditional. If the keyboard cannot be dismissed
  — the application is not wrapped in `.testHost()`, or the keyboard stays up — the test fails
  naming the cause. The control hit-tests only while the keyboard is up, ships nothing outside
  DEBUG builds, and changes no production behavior.

### Fixed

- **`label` answers with the control's text on every platform** (FOSTestingUI) — AppKit carries a
  static text's string as its accessibility *value* where UIKit carries it as its *label*, so
  `XCTAssertEqual(app.uiTestingElement("titleLabel").label, viewModel.title)` — the documented
  pattern — silently returned `""` on macOS. It reads as a missing view rather than a platform
  difference. `label` now falls through to the value when there is no label, which changes only
  the case that returned an empty string; no control that has a label answers differently, and no
  new API was added to paper over it.

### Changed

- **The iOS tab workaround is documented as a workaround** (FOSMVVM) — 0.12.1 described finding a
  tab by its displayed title in the same voice as the API itself, and it was read as an
  endorsement: the label lookup matches on displayed text, which is precisely what
  `uiTestingIdentifier(_:isEnabled:)` exists to stop a test doing. The DocC now says what it is
  (a workaround for an Apple defect), when it dies (**delete it when the deployment target
  reaches iOS 27**), and how to quarantine it behind `#available` so a project shipping below
  iOS 27 can still exercise the real tag path on the iOS 27 machines it already owns.

- **`Tools/UITestingProbe` covers a toolbar**, on iOS and macOS. A `ToolbarItem` bridges to a
  native bar item the way a tab bar item does, so it was the obvious next suspect after #126 —
  measured on iOS 26.5, iOS 18.6 and macOS 26.4, a tag on a control inside a `ToolbarItem` or a
  `ToolbarItemGroup` holds, and the tap reaches the control. No change was needed; the coverage
  is there so the next platform release is measured rather than assumed.

## [0.12.1] - 2026-08-13

### Fixed

- **`tap()` and `type(_:)` wait for the view** (FOSTestingUI) — both asked once whether the view
  existed and failed the test if it did not, which made every tap a race against the application
  finishing what it was presenting. A tab bar reaches the accessibility tree a few hundred
  milliseconds after launch, so it lost that race every time and a test could not tap a tab at
  all ([#126](https://github.com/foscomputerservices/FOSUtilities/issues/126)):

  ```swift
  app.uiTestingElement("settingsTab").tap()   // the first thing the test does
  ```

  Both now wait as long as `waitForExistence()` does, and fail with the same message naming the
  identifier when the view never arrives. `exists` and `isVisible` are unchanged — they answer
  about the screen as it is now, so a test that *opens* by asking about a tab still wants
  `waitForExistence()` first.

- **The wait defaults are `timeout: 10`**, raised from `3` — `waitForExistence(timeout:)`,
  `waitForDisappearance(timeout:)` and `presentView(timeout:)` together (FOSTestingUI). Measured
  on an idle machine, a tab bar reached the accessibility tree between 0.6 and 2.1 seconds after
  the application came to the foreground, which left a 3 second wait no headroom on a loaded one.
  A wait that succeeds returns the moment it can, so the number only costs anything on a test
  that was going to fail anyway.

  `Tools/UITestingProbe` now covers a live `TabView`, which is what had been missing.

### Changed

- **`TabContent.uiTestingIdentifier(_:isEnabled:)` now requires iOS 27** (FOSMVVM), raised from
  iOS 18. **An iOS project with a lower deployment target will no longer compile a call to it**,
  and that is the point: Apple's `TabContent.accessibilityIdentifier` is declared from iOS 18 but
  puts no identifier on the tab bar item until iOS 27 — on any Xcode, measured one variable at a
  time in `Tools/UITestingProbe/README.md`. Below that floor the call compiled and silently did
  nothing, and the test failed saying no view carried the tag.

  Other platforms are unchanged and unaffected — macOS and tvOS were measured tagging the tab at
  their existing floors. Tagging is also unaffected everywhere else on iOS, including views
  *inside* a tab. An iOS project that cannot raise its floor yet finds the tab bar item by the
  title it displays, resolved from the same ViewModel property that builds the tab's label so the
  lookup holds in every locale:

  ```swift
  let title = try viewModel.settingsTabTitle.localizedString

  app.tabBars.buttons[title].firstMatch.tap()
  ```

## [0.12.0] - 2026-08-12

### Added

- **`uiTestingElement(_:)` and `UITestingElement`** (FOSTestingUI) — find the view an XCUITest
  is looking for by the identifier it was tagged with, and nothing else:

  ```swift
  app.uiTestingElement("nameField").type("Fern")
  app.uiTestingElement("saveButton").tap()

  XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())
  ```

  It offers `exists` (present in the view hierarchy, on screen or not), `isVisible` (on screen
  and tappable), `waitForExistence()`, `waitForDisappearance()`, `tap()`, `type(_:)`, `label`,
  `value`,
  `isEnabled`, and `xcuiElement` as an escape hatch. A `tap()` or `type(_:)` against an
  identifier no view carries fails the test naming the identifier it looked for, rather than
  surfacing as an opaque XCUITest snapshot error. `tap()` falls back to a coordinate tap for
  menus that report themselves as not hittable, and `type(_:)` handles focus, so the
  `XCUIApplication` accessor extensions and the hand-rolled `typeTextAndWait` / `tapMenu` /
  `text` helpers that every project grew are no longer needed.

- **`XCTAssertEqual` / `XCTAssertNotEqual` accept a `Localizable`** (FOSTestingUI) — assert what
  a view displays against the ViewModel it was given, without `try` or `localizedString`:

  ```swift
  XCTAssertEqual(app.uiTestingElement("dashboardTitle").label, viewModel.title)
  XCTAssertEqual(app.uiTestingElement("emailField").value, viewModel.email)
  ```

  Overloads cover `String` and `String?`. A `Localizable` whose translation was never realized
  cannot match displayed text, so the assertion fails and names that as the cause rather than
  reading as a wrong label — and it fails at the assertion instead of throwing, so one
  unrealized translation no longer hides every later assertion in the test.

- **`waitForDisappearance(timeout:)`** (FOSTestingUI) — waits for a tagged view to leave the
  view hierarchy, the counterpart to `waitForExistence(timeout:)`. Asserting `exists == false`
  straight after the action that dismisses a view answers before the view has gone; the
  alternative was an `XCTNSPredicateExpectation` written by hand at each site.

- **Both waits default to `timeout: 3`**, matching `presentView(timeout:)`. The number is a
  property of the machine running the tests, not of any one assertion, and every call site
  restating it was noise.

### Fixed

- **`uiTestingIdentifier(_:isEnabled:)` now holds where it previously did not** (FOSMVVM) — a
  tag applied to a control that bridges to a native element (`Picker`, `DatePicker`,
  `TextField`, `ColorPicker`) was silently discarded, and the surrounding subtree was left
  unhittable: XCUITest could not find the control by any query, and a test that tried spun
  until the runner aborted. A tag applied to a container also overwrote the tags of the
  sub-views composed inside it, so a sub-view's own test suite passed in isolation and failed
  once the sub-view was composed into a screen. Both are resolved: a tag now holds on any view,
  at any nesting depth, and at any position in the modifier chain, and a composed view and each
  of its sub-views can each carry their own tag.

- **`uiTestingIdentifier(_:)` gains `isEnabled:`** (FOSMVVM) — matching the `TabContent`
  overload, which has always had it. Defaulted, so existing call sites are unaffected.

### Changed

- **Tagged views are no longer located by XCUITest element type** (FOSMVVM/FOSTestingUI,
  **breaking for UI tests**). Queries such as `app.buttons["saveButton"]`,
  `app.staticTexts["titleLabel"]`, or `buttons.element(matching: .button, identifier:)` no
  longer match a view tagged with `uiTestingIdentifier(_:)`. Views need no edit — the call
  sites that tag them are unchanged.
  **Migration:** replace each element-type query with `app.uiTestingElement("<identifier>")`
  and delete the `private extension XCUIApplication` accessors that wrapped them.

  ```swift
  // Before
  private extension XCUIApplication {
      var saveButton: XCUIElement {
          buttons.element(matching: .button, identifier: "saveButton")
      }
  }
  app.saveButton.tap()

  // After
  app.uiTestingElement("saveButton").tap()
  ```

  Do not assume an element type for a tagged view — the identifier is the whole contract, which
  is what lets a test survive a `Button` becoming a `Menu`. Views located by *displayed text*
  (the `localizedViewModel()` path) are unaffected.

## [0.11.0] - 2026-08-11

### Changed

- **`MVVMEnvironment.registerTestView(_:)` is now `static`** (FOSMVVM, **breaking**) — call it
  as `MVVMEnvironment.registerTestView(MyView.self)` from your `App`'s `init()`. The instance
  method has been **removed**, not deprecated. It had taken `self` and never used it since the
  registry became a `@MainActor` static in 0.10.1, which let registration hide inside a computed
  `mvvmEnv` and land *after* `testHost()` had already resolved the view under test. With no
  instance in the call there is no longer a plausible-looking wrong home for it.
  **Migration:** keep your `registerTestingViews()` helper but make it a `static` extension on
  `MVVMEnvironment` (where the `registerTestView(_:)` calls read unqualified), move the
  `#if DEBUG` inside it, and call it from `init()` — not from `var mvvmEnv`, `.onAppear`, or
  `.task`. Only the *body* of `registerTestView(_:)` is DEBUG-only, so the helper compiles away
  to a no-op in release and the call site in `init()` needs no guard:

  ```swift
  @main struct MyApp: App {
      init() {
          MVVMEnvironment.registerTestingViews()
      }
  }

  private extension MVVMEnvironment {
      @MainActor static func registerTestingViews() {
          #if DEBUG
          registerTestView(LandingPageView.self)
          #endif
      }
  }
  ```

### Fixed

- **`testHost()` misconfiguration now fails loudly and actionably** (FOSMVVM) — an unregistered
  view under test previously trapped on `fatalError("Unknown testing view: …")`, whose message
  reaches only the crash report. The diagnostic is now written to stderr as well, so it appears
  in `xcodebuild` and CI test logs, and it states the ViewModel the harness requested, every
  ViewModel that *is* registered, which of the two causes applies (nothing registered at all vs.
  this one missing), and the `init()` registration that fixes it.
- **ViewModel decode failures under `testHost()` are no longer silent** (FOSMVVM) — the
  `try?` that discarded decoding errors (and its `no-silent-failure` suppression) is gone.
  A payload that does not decode into the registered view's `VM` now reports the requested
  ViewModel type and the underlying error through the same diagnostic path.

### Documentation

- **`MVVMEnvironment.registerTestView(_:)` gains DocC** — it had none. States the `init()`-only
  contract, the reason (resolution happens before the first render), and the call site.
  `testHost()` / `testHost(decorator:)` now cross-reference it.
- **Test view registration documented for app authors** (fosmvvm-generators plugin, 2.22.0) —
  `fosmvvm-swiftui-app-setup` templates and checklist move to the static call; its Pattern 3 is
  replaced by "Test View Registration — `init()` Only", which shows the correct call site, the
  three wrong ones, and what the loud failure reports. The API catalog entries in
  `shared/api-catalog/FOSMVVM.md` and `FOSTesting.md` match. The previous timing caveat lived
  only in this skill file, where no framework consumer would ever see it.

## [0.10.2] - 2026-08-10

### Added

- **Functional-discipline layer** (fosmvvm-generators plugin, 2.19.0) — a SessionStart
  hook injects the FOSMVVM axiom — *f(requirements, architecture, ui design) → Source
  Code* — at token zero of every consuming session, so adopting projects hold the frame
  from 'go'. The ratified discipline preamble ships at `shared/functional-discipline.md`;
  all 13 `fosmvvm-*` skills open with its read-imperative and carry per-rule derivation
  lines. `shared/execution-model.md` maps the composition of f — the rule set
  (artifact ← inputs [skill]), the dispatch table (change type → stale subtree), halt
  states, and the dual-channel test rule with coverage closure — with six owner-ratified
  rulings recorded in `.claude/docs/execution-model-rulings.md`. A frozen litmus suite
  (`shared/litmus/`, scenarios A–D, with recorded baselines) qualifies the axiom and
  skills per engine generation.
- **`fosmvvm-behavioral-test-generator`** (fosmvvm-generators plugin, 2.20.0) — generates
  behavioral test suites projected from requirements + ratified design by an **isolated**
  writer subagent that has never seen the implementation (the second channel of f);
  ambiguities return as UNRATIFIED clarifications for the owner instead of silent
  decisions. Qualified by an executed two-seed litmus: a dropped requirement and a
  mishandled failure mode both went red, and the suite went all-green against a corrected
  implementation. `fosmvvm-review` gains `stub-vocabulary` and `stub-leakage` blocker
  checks: stub data draws exclusively from the reserved-fake vocabulary (Flintstones
  names/data, numbers at/near ±42, dates around 1914) — self-marking fiction, never
  plausible-real placeholders, and never the answer to a requirements gap.

### Fixed

- **Per-test eager `terminate()` removed** (FOSTestingUI) — `ViewModelDisplayTestCase.setUp`
  no longer calls `XCUIApplication.terminate()` before each test. The call duplicated
  `XCUIApplication.launch()`'s documented contract — a launch always replaces a running
  instance to guarantee a clean state — and a termination-confirmation hiccup under
  distributed-CI load was recorded as an intermittent `Failed to terminate` failure
  against the next product test to run, misattributing harness noise to consumer suites.
  `presentView()` now solely owns and documents the fresh-instance guarantee. No API change.

## [0.10.1] - 2026-08-08

### Fixed

- **`TestingView` race condition** (FOSMVVM) — `TestingView` no longer uses `.onAppear` to
  switch from the base view to the registered test view. The test view is now resolved in
  `init`, before the first render, eliminating the window where XCTest could query the
  accessibility tree and find the base view's elements instead of the test view's.

### Changed

- **`MVVMEnvironment.registerTestView(_:)`** (FOSMVVM, **`@MainActor`**) — the method is
  now `@MainActor` to match the actor isolation of the underlying registry. Callers outside
  an implicit `@MainActor` context (e.g. a free helper function that is not on the `App`
  struct) must add `@MainActor` to the enclosing function. App-struct `init()` and helper
  methods already annotated `@MainActor` are unaffected.

## [0.10.0] - 2026-07-19

### Added

- **`ClientCredentialProvider.credentialHeaders(afterRejection:)`** (FOSMVVM) — a refresh
  seam that lets a client recover from a server-side credential rotation. When a request is
  refused with `CredentialRejectedError`, the provider may supply replacement headers and the
  request is retried exactly once; returning `nil` (the default) preserves the previous
  behavior of throwing the rejection to the caller. The live-invalidation channel nudges the
  same seam when an SSE open is refused with 401. Providers must persist the refreshed
  credential — later requests and reconnects consult `credentialHeaders()`.

## [0.9.0] - 2026-07-17

### Changed

- **`register(request:)` moves to `RoutesBuilder`** (FOSMVVMVapor, **BREAKING**). The four
  registration doors (read, create, update, delete) are now `RoutesBuilder` methods taking
  an `app:` parameter; the `Vapor.Application`-sited versions are removed. Register a request
  on the route group whose middleware you want guarding it — mount privileged requests behind
  your credential group, public ones on the `Application` itself (an `Application` is a
  `RoutesBuilder`). The old siting also deviated from standard Vapor practice, where routing
  surfaces are where processing mounts and the `Application` receiver is for app-wide
  configuration. Where a request mounts is your decision; that its plan is derived is not —
  every door still derives and validates the request's load plan.
  **Migration:** `try app.register(request: X.self)` → `try app.register(request: X.self, app: app)`,
  or mount on a middleware group: `try authed.register(request: X.self, app: app)`. A
  path-prefixing group (`app.grouped("admin")`) is now rejected at boot, because clients derive
  the served URL from the request type; mount only on middleware-only groups.

## [0.8.0] - 2026-07-17

### Added

- **`Application.invalidateProjections(of:)`** / **`Request.invalidateProjections(of:)`**
  (FOSMVVMVapor) — non-Fluent server-side sources (an `Application`-hosted actor, a
  computed aggregate) nudge live clients to refresh when their state changes. Composes
  with `liveTransaction` — inside it the nudge reaches clients only if the transaction
  commits; where live invalidation is not enabled it is a no-op. Fluent-persisted models
  never need it — their saves already notify live clients.
- **`ProjectionContext.registerDependency(on:)`** (FOSMVVMVapor) — a factory registers
  response data the record-load plan can't see (e.g. an `appState` actor snapshot) so
  live clients refresh it when the model changes. Register a dependency on what you read;
  invalidate projections of what you changed.

## [0.7.0] - 2026-07-14

### Added

- **`CredentialRejectedError`** (FOSMVVM / FOSMVVMVapor). A credential rejection from
  `ClientCredentialMiddleware` now crosses the wire as a typed, `Codable` error and is
  rethrown by `processRequest(mvvmEnv:)` — catch it to recover (`.missing` /
  `.invalid`); it always throws to the caller (never `requestErrorHandler`). Requires
  FOS `ErrorMiddleware.default` (already the documented configuration). Retires the
  `DataFetchError.badStatus(401)` client contract and the documented `EmptyError`
  rejection-swallow. `TestingServerRequestResponse` gains `credentialRejection`.

### Changed

- **`ErrorMiddleware`**: an error conforming to both `Encodable` and `AbortError` is
  now served with **both** its typed body and its own status/headers (previously such errors
  were served `400 Bad Request`). Plain `Encodable` errors are unchanged.
- **`ClientCredentialMiddleware`**: any verifier throw that is not a
  `CredentialRejectedError` is now wrapped as one (`.invalid`) — a custom
  verifier that previously threw an `Abort` with its own status/reason now
  rejects as `401` with the typed body. Throw `CredentialRejectedError`
  directly to carry intent; `CancellationError` propagates unchanged.

## [0.6.0] - 2026-07-09

### Added

- **Live ViewModel invalidation — `@ViewModel(options: [.live])`** (FOSMVVM / FOSMVVMVapor).
  Opt a screen in with the one macro option and any view bound with `.bind()` re-fetches
  automatically whenever another actor commits a change to the data that ViewModel was served
  from — no polling, no manual invalidation, nothing else to write. Where no live connection is
  configured the ViewModel behaves exactly like a non-live one (fetch once on appear), so adding
  `.live` to a shipped screen is purely additive. The macro synthesizes a **`LiveViewModel`**
  marker; `.live` combined with `.clientHostedFactory` is a macro diagnostic (a client-hosted VM
  has no server response to derive registrations from).
- **`Application.useLiveInvalidation(on:)`** (FOSMVVMVapor) — the server boot switch. Call once,
  passing the route group your clients authenticate against; every registered container model then
  nudges connected clients after each committed change. Registrations made before or after the
  call are both honored.
- **`Request.liveTransaction` / `Application.liveTransaction`** (FOSMVVMVapor) — the sanctioned
  replacement for a bare `database.transaction { }` in a live application: every write inside the
  closure nudges live clients if — and only if — the transaction commits (a throw/rollback nudges
  nothing). Inside a bare `transaction { }` the framework cannot know whether your writes commit,
  so it stays silent and logs a warning.
- **`InvalidationChannel` / `InvalidationEvent` + `MVVMEnvironment.invalidationChannel`** (FOSMVVM)
  — the transport seam. Most apps configure nothing (leave `invalidationChannel` `nil` and the
  standard channel is synthesized over your deployment URLs, with `invalidationBaseURL` defaulting
  to `serverBaseURL`); conform your own `InvalidationChannel` only to replace the transport
  wholesale. The invalidation nudge carries opaque `ModelIdentity` values only — **never** any
  ViewModel data. Contract: the client authenticates the stream through your
  `ClientCredentialProvider` at connect, and a reconnect refreshes every live screen.
- **`withServedFluentTestApp`** (FOSTestingVapor) — a Fluent test harness that serves the app on
  an ephemeral local port and hands the test a base URL, for exercising long-lived streaming
  endpoints that outlast the in-process `app.test(...)` responder.
- Served responses now carry an **`X-FOS-Registrations`** response header alongside `X-FOS-Version`
  (the data a live client registers to watch). Treat it as opaque — do not parse or hand-construct
  it; only the live resolver reads it.

### Fixed

- **`X-FOS-Version` attaches exactly once** to a served response (FOSMVVMVapor). The version header
  was being appended twice on the served response; `addSystemVersion()` now replaces-or-adds, so
  exactly one value is present. Clients reading the first value were unaffected — this removes a
  latent duplicate on the wire.

- **`ClientCredentialProvider`** (FOSMVVM) — supplies the authentication headers that
  accompany every `ServerRequest`; consulted per request, so a rotating credential is
  picked up on the next call. The dynamic sibling of the static
  `MVVMEnvironment.requestHeaders`. Ships with the stock **`BearerCredentialProvider`**
  (`Authorization: Bearer <token>`; a `nil` token sends the request unauthenticated).
- **`MVVMEnvironment.clientCredentialProvider`** — register a `ClientCredentialProvider`
  once (defaulted parameter on every initializer; additive) and
  `processRequest(mvvmEnv:)` attaches its headers to every request, after the static
  `requestHeaders` so the per-request credential wins on a duplicate field.
- **`ClientCredentialMiddleware` + `ServerCredentialVerifier`** (FOSMVVMVapor) — the
  server half of the credential pair: route groups run an app-supplied
  `ServerCredentialVerifier` before each route; throw to reject, return to admit.
  Consulted per request, so a credential revoked server-side takes effect on the next
  call. Ships with the stock **`BearerCredentialVerifier`** — the matched pair of
  `BearerCredentialProvider` — which extracts `Authorization: Bearer` and asks the
  app whether that token is currently valid (missing or invalid → `401` with
  `WWW-Authenticate: Bearer`, never echoing the presented token). On a FOSMVVM client
  a rejection surfaces as `DataFetchError.badStatus(httpStatusCode: 401)` — this
  requires an error serializer that forwards the `Abort`'s status and headers (FOS
  `ErrorMiddleware.default` does). Known limitation: a request whose `ResponseError`
  decodes from the rejection body swallows the `401` into a typed error instead —
  `EmptyError` always does (its synthesized decode is a no-op, accepting any
  valid-JSON body); pre-existing `DataFetch` behavior.
- **Complete generated `Localizable` overload surface** — every SwiftUI
  initializer and modifier that takes a `LocalizedStringKey` now has a
  `some Localizable`-accepting twin with a `defaultValue:` fallback: 253
  overloads across 44 SwiftUI types (inits and modifiers). Call the twin exactly
  like Apple's API — `Text(viewModel.title)`, `Button(viewModel.cta) { … }`,
  `EmptyView().navigationTitle(viewModel.title)` — passing the ViewModel's
  `Localizable` where the string key goes. The surface is regenerated per SDK by
  `scripts/localizable-overload-sweep.swift`, and a CI staleness gate fails the
  build if the checked-in overloads drift from a fresh sweep. The swept,
  generated, and rejected-candidate coverage ledger lives in
  `Sources/FOSMVVM/SwiftUI Support/SweepCoverage.md`.

### Changed

- **BREAKING: `defaultTitle:` → `defaultValue:` on `TextField` Localizable
  overloads.** The fallback-label argument is now spelled `defaultValue:`,
  uniform with every other overload in the surface. A caller passing the old
  label renames the argument.
- **BREAKING: `any Localizable` → `some Localizable` on the Localizable
  overloads.** The generated inits and modifiers take an opaque `some
  Localizable` rather than an existential `any Localizable`. Ordinary call sites
  are source-compatible; only callers who spelled the parameter type explicitly
  are affected — replace `any Localizable` with `some Localizable` in the
  parameter type annotation.
- **BREAKING: `ContentUnavailableView` `defaultValue:` moved to second
  position.** The Localizable overload `init(_:systemImage:defaultValue:)` is now
  `init(_:defaultValue:systemImage:description:)` — `defaultValue:` follows the
  localizable slot uniformly across the surface. Source-breaking only for callers
  who passed `defaultValue` explicitly.
- **The `Text(_:defaultValue:)` Localizable inits, `Localizable.text`, and
  `LabeledContent(_:defaultValue:value:)` (String value) are unchanged** — no
  source change for callers.

## [0.5.0] - 2026-07-08

### Added

- **`Container` protocol** (`Container: Model`) with `containedRecordTypes` — a
  model that owns and authorizes other records.
- **`ContainerOperation`** — the authorization verb vocabulary
  (`readRecords`/`writeRecords`/`createRecords`/`deleteRecords`/`destroyRecords`/
  `anyOperation`) with `authorizes…Records` intent accessors on the enum and on
  `Sequence`.
- **Client-chosen sort** — `SortCriteria`/`SortKey`/`SortDirection`/`SortTerm`
  and `ServerRequestSort`. `ServerRequest` gains a defaulted `Sort` associated
  type (additive; existing requests are unaffected).
- **`PaginatedQuery`** — an opt-in query trait carrying a `Pagination` window.
- **`ModelIdentity`** — a sealed, opaque, non-generic identity rooted in a `Model`'s stable id
  (`Hashable`/`Codable`/`Sendable`), with `ModelNamespace` (minted only from a type, never a raw
  string), `Model.modelIdentity` / `Model.modelIdentityNamespace`, the opt-in
  `ModelIdentifiedViewModel` protocol, `ModelIdentity.viewModelId`, and `ModelIdentity == some Model`
  filtering sugar. Treat the value as opaque — its encoded form is version-stable and round-trips, and
  changes only on a library major version; do not parse or hand-construct it.
- **`ViewModelId.Freshness`** — an opaque, order-only version clock (a canonical-GMT birth moment)
  carried on every `ViewModelId` under the short wire key `fsh`. Orthogonal to identity: `==`/`hash`
  stay `id`-only and `ViewModelId` is deliberately not `Comparable`.
- **`ContainerDataModel` + `ContainmentRelation`** (FOSMVVMVapor) — declare a container's
  authorization-bearing relationships from its own Fluent `@Children`/`@Siblings`/`@Parent`
  KeyPaths; cardinality and joins come from Fluent, never restated.
- **`Application.register(_:migration:)`** (FOSMVVMVapor) — registering a container's migration
  also registers its identity descriptor; misconfigurations (duplicate namespace, foreign
  KeyPaths, containment drift vs `containedRecordTypes`) throw at boot.
- **`withFluentTestApp`** (FOSTestingVapor) — a scoped in-memory SQLite + Vapor application harness
  for Fluent-backed tests.
- **`ContainerAuthorization`** (FOSMVVM) + **`Sequence<ContainerOperation>.authorizes(_:)`** — the
  shared authorization contract: conform a value type your persisted grant projects to answer "may
  this subject touch these records?"; the operation-set helper honors the wildcard grant so app
  code doesn't drift to a raw `contains(_:)` check that silently ignores it.
- **`SortableDataModel` + `SortMapping`** (FOSMVVMVapor) — declare how a model's published sort
  *meanings* become database ordering, once, applied everywhere the framework sorts that model.
- **`Request.serverRequestSort(ofType:)`** (FOSMVVMVapor) — the server-side parse surface that
  recovers a request's sort criteria, mirroring the existing `serverRequestQuery(ofType:)`.
- **`ContainerAuthorizationProvider`** (FOSMVVMVapor) — conform once to supply the current subject's
  complete `ContainerAuthorization` set for a request; the framework fetches through it when first
  needed and reuses the result for every load in that request.
- **`Application.useContainerAuthorizationProvider(_:)`** (FOSMVVMVapor) — boot-time registration of
  the app's authorization provider; registering a second provider throws rather than silently
  replacing the first.
- **`ComposableFactory`** (FOSMVVM) — the opt-in trait that makes "a composable body declares the
  data it needs" true and automatic: `dataRequirements` lists a factory's own loads, `children` lists
  the child factories it composes. A child that doesn't declare its data can't be listed — composing
  an undeclared child fails to compile. Any `ServerRequestBody` may adopt it (not only ViewModels), so
  a CLI's plain manifest body composes the same machinery. Declarations are aggregated automatically
  at boot and loaded once, before the body is built.
- **`DataRequirement` + `LoadRequirement`** (FOSMVVM) — the typed load a factory declares.
  `DataRequirement` is a sealed public marker (mint through `LoadRequirement`; a foreign conformance
  is rejected at boot with "unknown requirement kind"). `LoadRequirement.read(_:in:via:)` names the
  record type, where it roots (`in:`), and the intermediate containment hops to it (`via:`, terminal
  hop always implicit — a parameter pack, so call sites carry no `any`); `.refinedByRequest` marks the
  one requirement per plan the request's own sort/pagination axes apply to. The write-family verbs
  `.write` / `.create` / `.delete` load a write request's candidate set (`.create` takes no `via:`
  intermediates — the root container is the create scope).
- **`ComposedChild`** (FOSMVVM) — declares one composed child factory: `.child(_:)` shares the
  parent's containment scope (the common case); `.child(_:via:)` descends further; `.child(_:rootedAt:)`
  starts a fresh root (e.g. an apex-rooted sibling tree alongside a request-rooted detail).
- **`RootScope` / `RootSource`** (FOSMVVM) — where a requirement or composed child roots
  (`.parentRoot` / `.newRoot(RootSource)`) and where a fresh root's identity comes from
  (`.query` — the request's own `RootedQuery`; `.apex` — the app's registered apex-container
  resolver), giving every load a rooted, apex-pattern scope.
- **`RootedQuery`** (FOSMVVM) — a `ServerRequestQuery` that vends the container identity its
  request is rooted in, for requirements/children declared with `.newRoot(.query)`.
- **`AuthorityFlow` + `Container.authorityFlow`** (FOSMVVM) — whether authority granted on an
  ancestor container flows through to a container's own records (`.inherits`, the default — one
  grant anywhere above covers the descent) or must be granted anchored at that container itself
  (`.guards`).
- **Boot-time load-plan derivation and validation** (FOSMVVMVapor) — `register(request:)` derives
  each composable request's aggregated data-load plan once, at route registration, and validates it
  against the app's registered containers: composition cycles, duplicate `.refinedByRequest` marks,
  unresolvable containment hops, and `.query`/`.apex` roots missing their required conformance/resolver
  all fail fast at boot, never at request time.
- **`ResponseBodyFactory` (FOSMVVM) + `VaporResponseBodyFactory` (FOSMVVMVapor) + `ProjectionContext`
  (FOSMVVM)** — the one author-facing server factory for every request's `ResponseBody`, ViewModel or
  not. Authored **once on the body**: `static func body<R: ServerRequest>(context:) where
  R.ResponseBody == Self` is generic over the request, so a single factory serves **every** request
  that returns that body — a read *and* the writes that return the same value. `body` is
  **synchronous** (`throws`, never `async`) and is handed a `ProjectionContext` — the typed request,
  the app-declared `AppState`, and typed record reads by the same static handle the factory declared —
  never a `Vapor.Request` or `Database`. Reading a handle that never reached the plan throws (naming
  the handle and request), never returns `[]`; the projection *couldn't* load if it wanted to.
- **`Application.register(request:)`** (FOSMVVMVapor) — one Application-only registration door for
  every request (there is no grouped/`Routes`-level door). Write requests (`CreateRequest` /
  `UpdateRequest` / `DeleteRequest`) get their own overloads picked by Swift; a write request that
  reaches the read door, or a `ReplaceRequest`/destroy conformer, fails fast at boot rather than
  registering GET-only. Boot checks fail-fast on: a non-`Void` `AppState` with no builder; a duplicate
  `useAppState` type; a write request's candidate root-source missing its `RootedQuery`/apex resolver.
- **The write path** (FOSMVVM + FOSMVVMVapor) — `TargetedQuery` (FOSMVVM) names which loaded record a
  write targets, by the opaque `ModelIdentity` the client received (the form body carries no
  `ModelIdType`; the server resolves the selector against the candidate set it loaded itself —
  not-yours is indistinguishable from not-found). `WriteTargetProviding` + `DataModelWriter`
  (FOSMVVMVapor) are adopted by a write request's `RequestBody`: `candidates` declares the auth-scoped
  set (exactly one per write request), and `apply(to:)` is a **sealed synchronous** field application
  that cannot touch the database (create reuses the same `apply` on a fresh `Target()`; delete needs
  no `apply`). Each write protocol constrains its `ResponseBody` to a marker
  (`Create`/`Update`/`Delete`/`Replace`/`Destroy` `ResponseBody`; `EmptyBody` conforms to each). After
  a write commits and the mutated containers' records are invalidated, the server re-serves the **write
  request itself** through the genuine read pipeline to build its `ResponseBody` — normally the
  container's updated children, the same value a read of that container returns. No separate refresh
  request: the body factory is generic over the request that returns it, so the write reuses its own
  `ResponseBody`'s factory. Create is gated on the authorization grant directly (a denied create throws
  the same not-found shape as a nonexistent destination — no authorization oracle).
- **`Application.useAppState(_:builder:)`** (FOSMVVMVapor) — registers the one load-phase builder for a
  factory's `AppState` (session-derived display data), computed with full request power and handed to
  the synchronous projection as a plain value. Keyed by the `AppState` type; `Void` needs no
  registration.
- **`Application.useApexContainerResolver(_:)`** (FOSMVVMVapor) — now public: registers the resolver
  that binds `.apex`-rooted loads' root identity per request, making `.apex` roots usable by apps.
- **`SupplementalRecordLoading`** (FOSMVVMVapor) — now public: the load-phase escape hatch for data
  that cannot be declared as containment tuples. Runs after the declarative plan (its records already
  readable) with full request power; a thrown error fails the request, never swallowed to an empty
  result.
- **Boot-time Sort-bridge warning** (FOSMVVMVapor) — a `.refinedByRequest` plan whose request `Sort` is
  neither `EmptySort` nor `SortCriteria`-based logs a warning at registration naming the request and the
  ignored `Sort` type, so the silent zero-terms no-op becomes visible.
- **`@LocalizedDate`** — a localized, locale-formatted `Date` property wrapper
  (`LocalizableDate`), completing the family alongside `@LocalizedInt` and
  `@LocalizedDouble`. `dateStyle`/`timeStyle`/`dateFormat` pass through to
  `LocalizableDate` (`.medium` date style when nothing is specified); `value:`
  is required.
- **`FOSNetworkSecurity`** — a new module for hardening client↔server transport.
  `ServerCertPinning` pins a server by its SPKI public-key hash (`SPKIPin`), applied through a
  `URLSession` extension so a pinned session drops in wherever `URLSession` is used; `MutualTLS`
  + `ClientIdentityProvider` supply a client certificate for mutual-TLS handshakes.
- **Paginated total-count** — `ProjectionContext.totalCount(for:)` and
  `ContainmentRelation.memberCount` (FOSMVVMVapor): the size of the authorized set a
  `PaginatedQuery` window is a view into, so a client can render window position (e.g.
  "40–65 of 1,204,882"). Counted via `.count()` (no fetch), computed after the grant check so it
  never counts unauthorized rows, and cached per window (0 for an unplanned or denied load).
- **Query-driven filtering** — `FilterableDataModel` (FOSMVVMVapor): a searchable model declares
  the one `ServerRequestQuery` type it reads and hand-writes `apply(filter:to:)` as a database
  `WHERE`. A query *is* a filter, so there is no separate filter type or wire vocabulary; the
  request's query rides the containment refinement into the load, the count, and the cache key, so
  counts and windows reflect the narrowed set. Opportunistic — a non-filterable model, or a query
  that isn't the model's declared type, is simply not narrowed (nothing is dropped or thrown).
- **Server-hosted localization in view previews** — `previewHost(serverHostedResourcesPath:)` loads
  YAML localization from a filesystem directory served by the server, so a server-localized view
  can be previewed against those resources; adds `URL.yamlLocalizationStore()`.

### Changed

- **Authorized container loads can be anchored independently of the container being loaded from.**
  When a load descends through a `.guards` container (see `AuthorityFlow` above), the authorization
  check — and the framework's request-scoped cache — now key off that container's instance rather
  than the record's immediate container, so a grant on one guarded branch can never authorize, or
  share a cached result with, a differently-anchored branch. Existing loads (no `.guards` container
  on the path) are unaffected — the default anchor is unchanged.

- **BREAKING: `ServerRequest.init` now takes `sort:`.** The canonical initializer is
  `init(query:sort:fragment:requestBody:responseBody:)`; a protocol-extension convenience
  (`sort` defaulting to none) keeps existing 4-parameter call sites compiling unchanged. Sort
  criteria, when present, now travel alongside the query in the request's URL; pre-existing
  requests and URLs (no sort) are unaffected and round-trip unchanged.

- **BREAKING (FOSTestingVapor): `VaporServerRequestTest`'s `Request.ResponseBody` constraint is now
  `VaporResponseBodyFactory`** (was `VaporViewModelFactory`). ServerRequest tests whose response body
  adopts the renamed factory compile unchanged; the constraint name is the only change.

- **BREAKING: `ServerRequestController` is the one general dispatch layer.**
  `ActionProcessor` is now `@Sendable (Vapor.Request, TRequest) async throws ->
  TRequest.ResponseBody` — the typed request arrives bound (query + sort parsed
  once by the request middleware; a body verb decodes `requestBody` onto it). All
  six `ServerRequestAction`s now map to HTTP methods (`.show` GET, `.delete`/
  `.destroy` DELETE join POST/PUT/PATCH); `register(request:)` and the write
  overloads are unchanged sugar that pre-specialize this mechanism with the
  framework's guarded pipelines. A controller listing both `.delete` and
  `.destroy` fails fast at boot (one URL, one DELETE handler).

### Removed

- **BREAKING: `Model.modelType`** — the dormant, unused, stringly-typed namespace is removed in favor
  of the opaque `ModelNamespace`. Downstream code referencing `modelType` migrates to
  `modelIdentityNamespace`.
- **BREAKING: `VaporViewModelFactory` + `VaporModelFactoryContext`** (FOSMVVMVapor) — the server factory
  that handed the projection the raw `Vapor.Request` (and thus `req.db`) is removed in favor of
  `VaporResponseBodyFactory` + `ProjectionContext`. The projection intentionally loses `Vapor.Request`
  and the database handle — it can no longer load — and `body(context:)` is synchronous. Conformers
  move their loading to declared requirements (`ComposableFactory`) or `SupplementalRecordLoading`.
- **BREAKING: `Application.register(viewModel:)`** (FOSMVVMVapor) — removed in favor of
  `register(request:)` (which serves every request, ViewModel-bodied or not, and hosts the write
  overloads). Registration is Application-only; grouped/`Routes`-level registration is gone.

### Fixed

- **`EmptyBody` responses are content-agnostic on fetch (PL-8)** — a request whose `ResponseBody`
  is `EmptyBody` no longer requires (or inspects) response content, so a bodyless server response
  decodes cleanly.
- `FOSVaporServerError.debugDescription` now correctly labels itself (it
  previously printed `FOSLocalizableError:`).
- Corrected stale documentation examples: `PDFRenderer.render` shown with
  `try` (both overloads are synchronous), `register(viewModel:)` label,
  `FormFieldView` example includes the required `focusField:` parameter,
  `hexString()` example values, and two `@Localized*` example typos.

## [0.4.0] - 2026-07-03

### Added

- **WebAssembly (WASM) platform support**, including a WASI `URLSession`
  implementation (with JavaScript wrapper functions that preserve `this`
  context) so `FOSFoundation` networking works in the browser.
- **Custom `URLSession` injection** — an application can now supply its own
  `URLSession` through `MVVMEnvironment`.
- **`@LocalizedDouble`** — a localized, locale-formatted `Double` property
  wrapper (`LocalizableDouble`), alongside the existing `@LocalizedInt`.
- **Localizable array access** — localized array properties (`@LocalizedStrings`)
  for binding collections of localized values.
- **`OperationBus`** — a mechanism for dispatching ViewModel operations.
- **`Localizable` support for SwiftUI `Label` and `LabeledContent`.**
- **`ViewModelDisplayTestCase`** (FOSTestingUI) — a display-only ViewModel UI
  test base class that does not require a `ViewModelOperations` type.
- **FOSMVVM React runtime resources** are served from `FOSMVVMVapor` at
  `/fosmvvm/react/` under a global namespace.
- **`ReplaceRequest` protocol** — the PUT verb of the write-request family
  (`Create` / `Update` / `Delete` / `Destroy` / **`Replace`**). It mirrors
  `UpdateRequest` (`RequestBody: ValidatableModel`, `action == .replace`) and
  adds the `ReplaceResponseBody` marker. The generic `ServerRequestController`
  already routes `.replace` to `PUT`, so no server-side change is required to
  serve one.
- **`@ViewModel` synthesizes the `Stubbable` witness.** When a type provides a
  fully-defaulted parameterized `stub(...)` but no zero-argument `stub()`, the
  macro now generates `static func stub() -> Self`, forwarding each parameter's
  default explicitly (so the call binds to the parameterized overload rather than
  recursing into the witness). Types no longer need to hand-write the boilerplate
  witness alongside a parameterized stub.

### Changed

- **Yams dependency now points at the official `jpsim/Yams`** (the WASM support
  is kept dormant).

### Fixed

- **Server-hosted ViewModels are now served localized.** `VaporViewModelFactory`
  gained a default `AsyncResponseEncodable.encodeResponse(for:)` that encodes the
  ViewModel through the request's `Accept-Language` locale (via the shared
  `ServerRequestBody.buildResponse(_:)` / `localizingEncoder` path, which also
  stamps the `SystemVersion` header). A conformer now supplies only
  `model(context:)` — previously the required async `encodeResponse` conformance
  was missing entirely, so no in-repo type could conform and the documented
  pattern would not compile. The docc example is corrected to match.
- **`VaporServerRequestTest` (FOSTestingVapor) boots and tears down correctly.**
  It now runs a full application lifecycle per `test(...)` call — `Application.make()`
  → `asyncBoot()` → dispatch → `asyncShutdown()`. Previously it called `startup()`
  (which launched the `serve` command and left it un-shut, tripping
  `ServeCommand did not shutdown before deinit`) and paired it with a synchronous
  `deinit` shutdown that cannot satisfy the async serve command. Booting with
  `asyncBoot()` also avoids Vapor's console argument parser, resolving the
  long-standing `-NSTreatUnknownArgumentsAsOpen` failure that kept the end-to-end
  serve test disabled. The response is now decoded as the request's `ResponseBody`
  (it was mistakenly decoded as `RequestBody`).
- **`FormFieldView`** now preserves typed whitespace and uses the current
  `onNewValue` closure, and resolves a debounce race and a `FocusState`
  field-clear bug observed on iOS 18.
- **FOSMVVM React resources** are served from the correct bundle root.
- A missing Linux `import` was added.
- **Versioned ViewModel baselines are persisted beside the calling test**, not
  inside FOSTesting's own source. `expectFullViewModelTests` now forwards
  `#filePath` / `#line` to `expectVersionedViewModel`, so the baseline directory
  is resolved at the developer's test file. Previously the convenience wrapper
  resolved `#filePath` to FOSTesting's source and wrote baselines to an
  ephemeral, ignored location, defeating cross-version drift detection.
- **Version-baseline directories anchor on the SwiftPM test-target root**
  (`Tests/<Target>/.VersionedTestJSON`), independent of how deeply the calling
  test file is nested. This keeps equally-named types in sibling test targets
  from colliding on a shared baseline file. Non–SwiftPM layouts fall back to the
  previous behavior.
  - **⚠ Migration (downstream apps that commit baselines):** the baseline path
    changed. If you committed version baselines at the old location, move them to
    `Tests/<Target>/.VersionedTestJSON/`. A baseline left at the old path is not
    found, silently **regenerated**, and the test **passes** — so cross-version
    drift detection is quietly lost until the files are moved. (FOSUtilities' own
    baselines are now git-ignored, so only downstream consumers are affected.)

## Prior releases

Releases up to and including **0.3.7** are recorded as
[Git tags](https://github.com/foscomputerservices/FOSUtilities/tags) and GitHub
Releases. This changelog begins tracking notable changes from the next release
onward.

[Unreleased]: https://github.com/foscomputerservices/FOSUtilities/compare/0.13.2...HEAD
[0.13.2]: https://github.com/foscomputerservices/FOSUtilities/compare/0.13.1...0.13.2
[0.13.1]: https://github.com/foscomputerservices/FOSUtilities/compare/0.13.0...0.13.1
[0.13.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.7...0.13.0
[0.12.7]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.6...0.12.7
[0.12.6]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.5...0.12.6
[0.12.5]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.4...0.12.5
[0.12.4]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.3...0.12.4
[0.12.3]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.2...0.12.3
[0.12.2]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.1...0.12.2
[0.12.1]: https://github.com/foscomputerservices/FOSUtilities/compare/0.12.0...0.12.1
[0.12.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.11.0...0.12.0
[0.11.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.10.2...0.11.0
[0.10.2]: https://github.com/foscomputerservices/FOSUtilities/compare/0.10.1...0.10.2
[0.10.1]: https://github.com/foscomputerservices/FOSUtilities/compare/0.10.0...0.10.1
[0.10.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.6.0...0.7.0
[0.6.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/foscomputerservices/FOSUtilities/compare/0.3.7...0.4.0
