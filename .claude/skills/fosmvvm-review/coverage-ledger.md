# Coverage ledger — the derivation of the check inventory

This file is the standing derivation for `fosmvvm-review`: every enforceable statement in the truth layer, mapped to the check or doctor rule that enforces it, or recorded as a gap. Completeness is measured here, rule-by-rule — never by counting areas or generators (ruled 2026-08-25).

**Walked 2026-08-25**, at plugin 2.41.0 (50 checks across 8 areas) and doctor R1–R12. Doctor has since grown R13–R14 (the shared-module pair, from this ledger's G16 and G6).

**Inputs** (this ledger is a projection of these; if any is re-cut, this file is stale):

- `.claude/skills/shared/execution-model.md` — *recorded as pending its own re-cut; re-derive the affected entries when that lands*
- `.claude/skills/shared/functional-discipline.md`
- `.claude/skills/shared/architecture-patterns.md`
- `.claude/docs/FOSMVVMArchitecture.md`
- `.claude/skills/shared/NAMES.md`
- repo `CLAUDE.md` (SOLID, encapsulation, documentation audiences, governance principles and lessons)
- `.claude/skills/shared/api-catalog/` — not a statement source; the existence-and-version reference detections resolve against

One further ground counts as truth for consumers: **FOSUtilities' own published API contract** (DocC'd public surface — `testHost()` timing, wire formats, path derivation). A check citing framework behavior anchors there; that is reading a declared input, not "code as pattern."

Check names below are the `## Check:` entries of `checks/<area>.md`, beside this file. Doctor's rules R1–R14 are stated in `docs/work/fosmvvm-doctor-design.md` and implemented under `Sources/FOSMVVMBootstrap/Doctor/`.

## Dispositions

- **COVERED** — an existing check (or doctor rule, marked TIER 1) enforces the statement.
- **PARTIAL** — enforced in one instance or clause; the uncovered remainder is named.
- **GAP — Gn** — no home; registered below with proposed area and severity.
- **OUT OF REACH** — a process rule review cannot see in code; listed so the walk is visibly complete.

---

## Source: execution-model.md (the build-tree rule set — each artifact and its declared inputs)

**Fields ← requirements; the form contract only.** COVERED — `fields-carry-no-identity`, `validation-not-duplicated-downstream`, `every-field-has-its-messages`, `overridable-members-are-requirements`.

**DataModel + Migration ← Fields + domain requirements.** COVERED — the `datamodel` area (was G1): `modelid-outside-id`, `datamodel-adopts-its-fields`, `schema-matches-the-model`, `migration-honors-the-fields-contract`, `stored-enum-decodes-honestly`. QUALIFIED 2026-08-25 against a drifted Fluent codebase (31 conformers, 45 migration types walked; four true positives; nine arguable calls folded back into the check text before shipping); the true positives and the verification target's use were reviewed and confirmed by David same day.

**Known future doctrine, unauthored:** David has more in mind for data models — cross-model validation, for example. No truth-layer statement exists yet; when one is authored and ratified, its checks follow (check-may-lead applies if a check drafts first).

**ViewModel ← ui design (shape) + requirements (operations).** COVERED for the review-reachable core — the `viewmodel` area's ten checks. (Whether the shape matches the *design* needs the design; out of review's reach.)

**FormViewModel ← Fields (adopts).** COVERED from the Fields side — `validation-not-duplicated-downstream` (a Form VM re-declaring labels), `every-field-has-its-messages` (whose three agreeing artifacts — the FormField definitions, the Messages struct, the YAML — gain a competing fourth source when a Form VM declares its own label and placeholder `@LocalizedString`s).

**Factory ← ViewModel + DataModel; the server-side DIP seam.** The import boundary is COVERED, TIER 1 — doctor R14 (was G6: the shared module imports no server/persistence code; the Factory is the one place that sees both). Factory-side review COVERED — `live-invalidation-is-a-pair` (was G10, `serverrequest`), and the area's globs now reach factory files.

**ServerRequest ← ViewModel + requirements.** COVERED — the `serverrequest` area's five checks plus `viewmodel-request-pairing`.

**RequestBody ← Fields (adopts).** COVERED — `requestbody-adopts-its-fields` (was G9, `serverrequest`) catches the body that neither adopts nor copies; the copy-without-adopting shape stays `validation-not-duplicated-downstream`'s (fields).

**Localization YAML — keys project from the VM; values are owner-authored; sample data never becomes a value.** COVERED — key/translation agreement rides the invariant-test channel (`viewmodel-test-covers-the-contract`, `test-yaml-covers-every-locale`); fabricated values in YAML are `stub-leakage`.

**View ← ViewModel + ratified design — three projecting surfaces (SwiftUI, Leaf, React).** COVERED — the `view` area (was `swiftui-view`; re-cut per ruling 4): seven checks with per-surface detections. Verification standing by surface: SwiftUI clauses QUALIFIED (the original swiftui-view era runs); Leaf clauses QUALIFIED 2026-08-25 against a drifted Leaf codebase as *subject*; React clauses **STATIC CHECK only** — no React verification target exists yet.

**Project ← bootstrap.** COVERED, TIER 1 — doctor R1–R14.

**App struct edits ← architecture.** COVERED — the `swiftui-app-setup` area's six checks.

**Invariant tests — ViewModel side.** COVERED — the `viewmodel-test` area's four checks.

**Invariant tests — ServerRequest side (typed request/response).** COVERED — the `serverrequest-test` area (was G2): `request-test-uses-the-typed-door`, `request-test-covers-the-contract` (which also carries the Fields/ValidatableModel invalid-body consistency clause from the minor list).

**Consistency tests (Fields ↔ adopters).** PARTIAL — the review checks verify the coherence directly; whether the project's own suite carries consistency tests is unchecked. Folded into G2's stage as a note, not a separate gap.

**Behavioral tests ← requirements and ratified design only, never the implementation; projected in an isolated context.** COVERED — `behavioral-suite-standing` (was G12, `cross-cutting`), scoped by ruling 5: standing and isolation only, never content against the code — and the check's text binds the reviewer to that scope explicitly (a proposed assertion "fix" is the contamination).

**stub() values ← the reserved-fake vocabulary.** COVERED — `stub-vocabulary`, `stub-leakage` (including the stub-at-a-missing-argument clause).

**verify ← all changed artifacts [fosmvvm-review].** The skill's own dispatch mechanics; doctor (tier 1) is being wired in as the structural first pass.

**The dual-channel rule and its closure (coverage as comparator).** OUT OF REACH — test provenance and projection context are process facts, invisible in code. The one code-visible shadow (a behavioral suite importing implementation modules) belongs to G12.

**Per-call-site execution — review's outer boundary** (noted 2026-08-25, from G2's verification). Review counts coverage per request *type*; it cannot demand that a specific production call site actually be exercised. A client path never driven, against a route with no static smell on either side, surfaces only as a coverage warning — not as the runtime failure it may be. That gap belongs to E2E testing, and review must not claim to close it; the field case that exposed it was caught anyway because the controller side carried a static smell two checks converge on.

**Halt states / UNRATIFIED protocol.** OUT OF REACH as process; the code-visible shadow (a stub value answering a requirements gap) is already `stub-leakage`.

---

## Source: functional-discipline.md

**The one sin's three forms — hand-editing a projected artifact instead of fixing its input; shipping downstream artifacts never re-projected after their input changed; re-projecting artifacts that were not stale.** OUT OF REACH directly — review reads finished code and cannot see provenance: nothing in a file records whether it was hand-edited or regenerated. What review does see is the disagreement these failures leave between sibling artifacts, and the sibling-agreement checks are those detectors: `every-field-has-its-messages`, `validation-not-duplicated-downstream`, `viewmodel-request-pairing`, `all-viewmodelviews-registered`.

**Citing neighbors as the pattern.** OUT OF REACH — a session behavior, not a code shape.

**Hand-rolling what the framework or a generator produces** (JSON coding, test doubles, encoders, fetch plumbing). COVERED — `no-hand-rolled-framework-products` (was G5, `cross-cutting`) for the general form, detections resolved against the api-catalog with a mandatory version-floor step; `no-hand-rolled-element-helpers` (`ui-tests`) keeps the specialized instance; network plumbing stays `server-calls-use-the-request-door`'s.

**Duplicating a dependency's internals downstream instead of surfacing the gap upstream.** COVERED — the second form of `no-hand-rolled-framework-products`: the finding names the upstream report as the remedy, never the fork, with the acknowledged-gap suppression path.

**Design sample data never projects.** COVERED — `stub-vocabulary` / `stub-leakage`. (Layout transcription from an unratified design is out of reach without the design.)

---

## Source: architecture-patterns.md

**Trust the type system — no defensive code against framework guarantees.** PARTIAL — `no-defensive-error-for-credential-rejection` is the one shipped instance; `comment-asserts-an-invariant-the-code-lacks` catches the adjacent shape. The general form stays reviewer guidance; too diffuse for a detection.

**Encapsulation (stringly identity, published representation, representation tests).** COVERED — `stringly-typed-identity`, `published-representation`, `representation-test`.

**Derive on the owner; vend a typed value; one spelling.** PARTIAL — owner-derivation rides `stringly-typed-identity`; the two-spellings clause is a minor uncovered clause (list below).

**Requirement + default = a real override.** COVERED for Fields (`overridable-members-are-requirements`); the statement is general — widening candidate in the minor list.

**Documentation has three audiences.** COVERED — `docc-serves-the-customer` (was G18, `cross-cutting`; ruled IN 2026-08-25 at warning).

**Error UI is not special — per-error client-hosted VM, no generic error architecture.** COVERED — `no-generic-error-architecture` (was G13, `viewmodel`).

**Typed errors are the operation's throw.** COVERED — `status-interpreted-as-result`, `responseerror-models-the-throw`, `controller-throws-the-declared-error`.

**Views render data, they don't shape it.** COVERED — `views-render-they-dont-shape` (was G4, `view`, all three surfaces).

**Don't abstract one-time operations.** Guidance-level judgment; no check.

**ServerRequest is THE way.** COVERED — `server-calls-use-the-request-door` (was G8, `cross-cutting`).

**Computed properties don't serialize.** COVERED — `computed-properties-dont-serialize` (was G11, `viewmodel`), with the read-resolution clause of `view-reads-vm-only` carrying the template side (a read landing on a computed property is not resolved).

**The four rules of forward projection.** Rule 1 COVERED (`view-reads-vm-only`). Rule 2 COVERED (`view-no-env-mutation`). Rule 3 (the projection edge lives at the parent that owns `.bind`) — reviewer guidance only; minor list. Rule 4 COVERED whole: `appstate-no-observable-args` (the argument side), `vm-holds-scalars-only` (the stored side — was G7), and the corrected `view-no-read-through-vm-ref` (the read side — B4).

**One top-level App State, not an environment of entries** (statement authored 2026-08-25 at the owner's direction — check-may-lead's inverse: the owner stated the doctrine, statement and check shipped together). COVERED — `one-top-level-appstate` (was G20, `view`, SwiftUI surface).

**Ops conventions.** COVERED — `ops-output-param-last`, `ops-not-async-unless-needed`, `ops-no-output-reads`. One clause uncovered (ops live on the Operations protocol, not free functions) — minor list.

**Never fail silently.** COVERED — `no-silent-failure`.

**Shared module is required.** COVERED, TIER 1 — doctor R13 (was G16).

**MVVMEnvironment configured once.** COVERED — `mvvmenv-built-once`, `deployment-urls-distinguish-environments`; the scattered-raw-fetch shape belongs to G8.

---

## Source: FOSMVVMArchitecture.md

Statements already walked above are not repeated; unique ones:

**The Model is the center — identity, all fields, relationships, persistence.** COVERED — the `datamodel` area (was G1) is its home.

**The request hierarchy and CRUD protocols.** COVERED — grounds the `serverrequest` area.

**Live invalidation: `registerDependency(on:)` and `invalidateProjections(of:)` are a pair and must name the same entity** — emit without registration nudges nobody; registration without emit refreshes never. COVERED — `live-invalidation-is-a-pair` (was G10, `serverrequest`; the area's globs now reach the server-side files both halves live in).

**ServerRequest tests never hand-build URLs — the typed test door.** Content of **G2**; `controller-derives-its-own-route` already states the production-side version of the same guarantee.

**The SPMLibraries umbrella, its carve-outs, and single-embed.** COVERED, TIER 1 — doctor R4a, R4b, R5 (the doc names them).

**Deferred localization; YAML structure.** COVERED — via the test-area checks and `swiftui-app-setup`'s resource checks.

**Hosting modes are per-ViewModel.** Guidance; the enforceable consequence is COVERED (`client-hosted-vms-need-resource-bundles`).

---

## Source: NAMES.md

**Write requests are noun-first (`UserCreateRequest`, never `CreateUserRequest`); screen reads are `<Noun>Request` with no verb; raw reads are `<Entity>ShowRequest`.** COVERED — `request-names-follow-the-dictionary` (was G14, `serverrequest`).

**Duplicate names across modules are fine; never contort a display name to dodge a collision.** COVERED — the collision-contortion clause of `request-names-follow-the-dictionary` (any projection type; the tell is a name whose only explanation is the dodge).

**Stem correspondence VM ↔ Request.** COVERED — the stem clause of `viewmodel-request-pairing` (NAMES §1b grounds both spellings).

---

## Source: repo CLAUDE.md

**SOLID, in FOSUtilities' terms.** Distributed: SRP → `viewmodel-not-a-mega-vm` and the projection checks; OCP → `overridable-members-are-requirements`; LSP → doctor R4a/R4b/R5; ISP → NAMES (`request-names-follow-the-dictionary`, was G14); DIP → doctor R14.

**Encapsulation as its own review axis.** COVERED — `stringly-typed-identity`, `published-representation`, `representation-test`, reviewed separately by explicit guidance.

**`ModelIdType` requires junction tables except for `@ID` (firm).** COVERED — `modelid-outside-id` (was G1, `datamodel`).

**Fields protocols define form contracts only (firm).** COVERED — `fields-carry-no-identity`.

**Existential types are a code smell (firm).** COVERED — `existentials-answer-the-question` (was G17, `cross-cutting`), under the ruled scope: parameters exempt; stored/collections/returns must answer the principle's question, findings name cost + alternative.

**Tests must never modify production data (firm).** COVERED — `tests-never-touch-production` (was G15, `cross-cutting` — write once, caught everywhere, per the standing ruling) owns the principle; `deployment-urls-distinguish-environments` and the live-production-object clause of `testhost-mirrors-vm-settings` remain its named instances in their areas.

**Production systems require type safety; code is artifact.** OUT OF REACH for a per-file review (project-level and process-level respectively).

**Lessons that are check-shaped:** suites sharing a singleton need `.serialized` — COVERED, `suites-serialize-shared-state` (was G19, `cross-cutting`; standing confirmed as doctrine 2026-08-25, statement authored into all three test generators the same stage). CLI-tools-through-ServerRequests → G8. Shared-module-documented → G16. The rest are guidance-shaped, not checks.

---

## Gap register

Ordered by damage; this is the work queue for the coming check-authoring stages. G-numbers are opaque identifiers minted in walk order — the sequence below, not the number, carries the ranking. All twenty gaps G1–G20 appear here (G4 keeps its own entry though it is authored inside G3's stage; G20 was minted after the walk, at the owner's direction). Severities follow the ruled default — blocker when it breaks at runtime, warning when it degrades the development experience — and are proposals until each stage's ruling.

**G1 · `datamodel` — SHIPPED 2026-08-25** (plugin 2.43.0). Five checks, not the sketched three: the junction-table principle (`modelid-outside-id`, blocker — widened to identities smuggled through JSONB structs, `String` fields, and id-keyed dictionaries), `datamodel-adopts-its-fields` (blocker, with the user-values-vs-operation-parameters discriminator), `schema-matches-the-model` (blocker — net-of-sequence, per dialect), `migration-honors-the-fields-contract` (warning), and `stored-enum-decodes-honestly` (split severity — a coalescing enum decode into a meaning-bearing case silently rewrites history). QUALIFIED against drifted Fluent code; the generator caught up in the same stage (its own `[UUID]` table row was the anti-pattern, and its optional-FK advice bypassed `@OptionalParent`).

**G8 · SHIPPED 2026-08-25** as `server-calls-use-the-request-door` (`cross-cutting`, plugin 2.44.0). Blocker for hand-built calls to the app's own server (both `processRequest` overloads are the door — CLIs use `baseURL:`); warning for hand-rolled external-service plumbing where FOSFoundation's `url.fetch()/send()/delete()` front door exists, `errorType:` pushed when the error body is an owned type (ruled 2026-08-25); Leaf/JS templates TBD at warning (ruled same day). QUALIFIED against a drifted client-server codebase: zero dishonest own-server calls (door-disciplined), two external-service warnings, and seven text-breaking arguable calls folded back — transport-keyed detection, the injected-base host prong for CLIs, client-role-wins-over-target-membership, the acknowledged-gap suppression path (gap + upstream issue number, so findings converge instead of re-firing), app-owned socket connects added to detection, JSON-only front door stated, pinned-TLS session factories exempted.

**G7 · SHIPPED 2026-08-25** as `vm-holds-scalars-only` (`viewmodel`, plugin 2.45.0). Blocker: a `@ViewModel` type storing an `@Observable` class reference — directly, wrapped in an owned value type, or laundered behind a stored existential whose conformers include one. QUALIFIED against a drifted client codebase (16 VMs, 135 stored properties; zero hits — the target holds the doctrine — with the near-misses inspected). The run's folds: the compile-gate fingerprints (`Codable` retrofit + `@MainActor`/`@unchecked Sendable`), the existential-resolution step, and two framework-pattern carve-outs — the computed `operations` minting idiom and `@FormFieldModel` wrapper backings, which are `@Observable Codable` classes by the framework's own design and would otherwise have been false blockers on every form VM. Completes rule 4's coverage with `appstate-no-observable-args` and the corrected `view-no-read-through-vm-ref` (B4).

**G6 · The shared module never imports server code — SHIPPED 2026-08-25 as doctor R14.** An `import` of Vapor/Fluent/Leaf/FOSMVVMVapor inside the shared ViewModels module. The dependency points one way — server imports shared, never the reverse; the Factory, living server-side, is the one place that sees both worlds. Error (tier 1). v1 limit recorded in the doctor design: an import of the project's *own* server target by name is not yet caught.

**G10 · SHIPPED 2026-08-25** as `live-invalidation-is-a-pair` (`serverrequest`, plugin 2.61.0) — the register's final stage, authored after the bookkeeping error that had recorded the home ruling as the stage was caught same day. Blocker, three shapes: emit-without-registration (nudges nobody), registration-without-emit (never refreshes — including the read-side form, a live factory reading outside its plan with no registration at all), and the bare-transaction clause (a hand-driven Fluent write to a live model outside `liveTransaction`/`DataModelWriter` — the catalog's own Don't). Detection pairs the registration and emit sets by entity expression and MUST enumerate every file first — registrations live in `+Live.swift` extensions and `LiveInvalidation/` sentinel files, and the verification run's own first sweep manufactured a dead-emit verdict by truncating exactly those. The falsifier holds the contract with an idiom the check now names: a sentinel `FOSMVVM.Model` whose shared `static let observed` is referenced by both halves, making the pairing impossible to misspell. Area globs widened to factories, `+Live` extensions, `LiveInvalidation/`, and `configure.swift`. QUALIFIED as a falsifier run (five live VMs, multiple sentinel pairs, zero false positives after the enumeration fold); the positive detections are STATIC CHECK — no drifted live target exists on file. Generator side already taught (the Fluent generator's framework-surface list states the pairing). The live-invalidation pairing: a factory reading state the record-load plan cannot see must `registerDependency(on:)` it, and the non-Fluent source mutating that state must `invalidateProjections(of:)` it — both naming the same entity. Emit without registration nudges nobody; registration without emit refreshes never. Blocker. Factory-side checks generally take their home in `serverrequest` for now.

**G9 · SHIPPED 2026-08-25** as `requestbody-adopts-its-fields` (`serverrequest` — the area chosen at stage: the subject files are request declarations, and adoption checks live where the adopter lives, per `datamodel-adopts-its-fields`; plugin 2.46.0). Blocker: a write body carrying user-entered field values with no Fields contract, or adopting one whose `validate` never reaches the Fields helpers. QUALIFIED two-sided: the true-positive shape came banked from the Model-layer run (a user-edited entity whose every `validate` returns `nil`); the falsifier run hit a zero-Fields codebase and produced zero false blockers — the user-values-vs-operation-parameters discriminator held on every body. Its folds: the write family is Create/Update/**Replace** (a peer protocol the draft's enumeration missed — and the falsifier's only substantive write body was exactly that), plus write-actioned plain `ServerRequest`s (the conformance-free spelling); `EmptyBody` short-circuits; machine-produced free text and CLI-argument keys are not user text.

**G2 · SHIPPED 2026-08-25** as the `serverrequest-test` area (plugin 2.47.0): `request-test-uses-the-typed-door` (blocker) and `request-test-covers-the-contract` (warning). QUALIFIED against a drifted test tree (17 conformers mapped drive-by-drive; the banked hand-glued `/destroy` helper confirmed as a blocker — with the twist that the glue mirrored a bespoke production mount, making the *production client* the likely-broken party and the test the honest witness; the check now says the remedy spans both trees). Eight folds: drives sorted by who derived the wire pieces (framework-computed instance URLs are warning, not blocker); the inexpressibility carve-out scoped so typed rejections are asserted through the typed `error`/`credentialRejection` fields, never status-sniffed; header-omission tests get their legitimate raw-door lane; coverage grading gained "present through the wrong door" so one migration cause is one finding; decode-guard ResponseErrors accept a decode-contract test (and route their declaration question to `no-defensive-error-for-credential-rejection`); the invalid-body clause widened to plain `ValidatableModel` bodies; effect assertions defined by effect, not response shape. Generator caught up: shipped harnesses over hand-rolled `withTestApp` (with the async-boot trap named), typed rejection asserts over status-sniffing.

**G3 · SHIPPED 2026-08-25** — the `view` area (was `swiftui-view`; plugin 2.48.0): one area, per-surface detections, per ruling 4. The skill's scope widened with it — reviewable files now include `.leaf`/`.tsx`/`.jsx`, which the Swift-only scope had silently exempted. The Leaf verification run's decisive framework fact is now in the checks: LeafKit renders unknown variables silently empty and skips unknown tags as literal text, so template↔VM drift never errors — the runtime cannot catch what this area catches.

**G4 · SHIPPED 2026-08-25** as `views-render-they-dont-shape` (warning, all three surfaces, inside the `view` area). The primary detection signal came from the field: the VM's own property names confess the split (`…Prefix`, `…Suffix`, `…Part1/2/3`, count-beside-noun pairs); adjacency is secondary, and identifier/attribute interpolation is carved out. `#date(…)` over a Localizable cannot work (numeric-timestamp tag, string value) — stated as such.

**Candidates from the Leaf run, awaiting David's ruling (2026-08-25)** — doctrine-shaped, so recorded here rather than folded (the subject codebase has no standing to legislate):

1. **Shared layouts' contract** — scope 1:1 to content templates; a shared app-shell/base layout gets a declared set of context keys it may read, and an undeclared read becomes the violation. Until ruled, layouts are noted, not graded.
2. **The render envelope** — tolerate a bare single-field `{content: VM}` wrapper; flag any additional data-bearing member (route-side app-shell contexts, sidebars) as projection bypass. The flag half is derivable from reads-vm-only; the tolerance half is the candidate.
3. **Presentation branching on raw enum encodings** — icon-per-state branching may be a pure view concern, but every comparison couples the template to the wire representation (`== "superseded"`). Allow the branching, flag the string-literal comparison — or ban both?
4. **The `data-*` shadow-render channel** — a template exporting its whole VM as `data-*` for client JS to re-render is a second render path no check owns. Shape only; no rule proposed.

5. **Shared-template optional-field reads** (registered 2026-08-25, from the fold audit) — a template shared by many per-error VMs reads a field only some of them declare, guarded by `#if`. Under `view-reads-vm-only` the read is unresolved for the VMs that lack the field; whether the `#if` guard makes the absence an intended optional-field contract, or is drift wearing a guard, is the owner's to rule. An earlier clause here graded it tolerated — that tolerance was inferred from code, not the truth layer, and was struck by the audit.

**G11 · SHIPPED 2026-08-25** as `computed-properties-dont-serialize` (`viewmodel`, plugin 2.49.0). Blocker where the encoded JSON is what renders and a live template reads the property (LeafKit misevaluates silently, in conditions too — either direction, no log line); warning for the unsprung forms (unread computed on a JSON-rendered VM, reads inside dead templates) and for the SwiftUI tier, where the decoded instance recomputes but the derivation ran on the wrong side of the wire. QUALIFIED against the drifted Leaf codebase: five live blocker groups (pagination controls, an artifacts section, three step-detail sections, an active-sessions badge, a search-state toggle — all reading computed `has*`/`is*` properties the JSON never carried) and three correct-pattern negatives held (stored-precomputed page-VM properties, the derive-on-the-owner freeze). The falsifier run produced zero hits on 17 VMs — the computed-`operations` idiom and property-wrapper carve-outs did their work, and stub-accessor/enum computeds fell out of scope by construction. Folds: whole-path read resolution through nested stored types; dead templates don't upgrade to blocker; derive-on-the-owner named as the correct shape; resolve reads against the rendered type, never by property name (one codebase held the same name stored on one VM and computed on another); the selection-vending carve-out is SwiftUI-only. The generator already stated the rule (its Codable-and-computed section, including the Leaf built-ins alternative) — no generator edit needed.

**G13 · SHIPPED 2026-08-25** as `no-generic-error-architecture` (`viewmodel`, plugin 2.50.0). Warning. Four detection shapes (unifying protocol, generic VM whose init has forgotten which error it holds, central handler/middleware, and the erosion signal — typed errors erased to `localizedDescription` for display, flagged as a trend when repeated); three named non-hits (a shared toast/alert *template* over per-error VMs — the truth statement's own example; error-binding transport to the framework's `.alert(error:)` surface, whose hand-rolled form belongs to hand-rolled-framework-products; and typed catches per route, however many accumulate — VM count is not a smell). QUALIFIED as a confirming run on both targets: the drifted Leaf codebase holds the doctrine exactly (thirteen typed `catch let error as XxxRequest.ResponseError` sites, zero broad catches, per-error VMs through one shared guarded toast template — the banked "13 VMs through one toast" note adjudicated as the doctrine *held*), and the falsifier surfaced the two boundary shapes the non-hits now name (the error-binding button helper; one `localizedDescription` erasure, correctly a note rather than a finding). Zero false positives available to produce; the generator already states the rule — no edit.

**G5 · SHIPPED 2026-08-25** as `no-hand-rolled-framework-products` (`cross-cutting`, plugin 2.52.0). Warning. Two forms under one name — the hand-rolled product (graded by the contract semantics the hand-roll loses: wire-format dates, locale correctness, typed diagnostics, verified interaction semantics) and duplicated dependency internals (remedy = the upstream report, never the fork, with the acknowledged-gap suppression path). Detections resolve against the plugin's api-catalog, never memory, and **the version floor is mandatory before any finding**: a pin below the API's release means the hand-roll predates the product — an adoption candidate, not a violation; blaming code for not using an API its pin cannot see is the check's characteristic false positive. QUALIFIED both ways: the falsifier's hand-rolled error-binding async button adjudicated to exactly the adoption-candidate tier (its pin predates the 0.13.0 async-button surface — the clause exists because the naive verdict was wrong), and the drifted subject banked a damage-tier true positive (a factory building display text through a hardcoded single-locale `DateFormatter` pattern where the `Localizable` date machinery is the product) plus the shallow-end shape (bare `JSONDecoder()` in CLI tooling — one family note, not per-site findings) and the external-DTO carve-out (LLM-service response coding legitimately owns its coder config). No generator edit: the api-catalog and its discovery skill ARE the positive form, and repo CLAUDE.md already commands catalog-check-first.

**G14 · SHIPPED 2026-08-25** as `request-names-follow-the-dictionary` (`serverrequest`, plugin 2.53.0). Warning. Classification precedes the token test — enumerate `ServerRequest` conformers (never `*Request`-named types: the falsifier's `PullRequest`, a GitHub wire type, is the name-keyed sweep's false positive), classify each by contract (CRUD/write-actioned → noun-first `<Noun><Verb>Request`; `ViewModelRequest` screen read → paired VM stem, verbless; raw read → noun-first `Show`), then test the leading token against the request's **own action** — a verb-derived word inside a screen noun (`DeleteConfirmationViewModel`'s read) is not a hit. Wholesale drift gets ONE area-wide finding framed as rename items per the dictionary's do-not-add-more callout; a new verb-first name in the reviewed diff is the sharper finding; dictionary-silent semantics route to the owner, never improvised. Carries NAMES §2's collision-contortion clause (any projection type). QUALIFIED two-sided: the subject is wholesale verb-first — not drift but provenance: it predates the dictionary and was authored under the REST idiom, so its ~70 conformers (including the dictionary's own anti-pattern example verbatim, beside correct screen reads proving both forms legible in one codebase) are rename items by the dictionary's own callout, not violations — and the falsifier is mixed — correct screen reads and noun-first writes beside verb-first true hits (including the dictionary's own token-mint example row in the wild, and a `Get…Request` raw read whose correction is the noun-first `Show` form). Generator already teaches §Naming the Concrete Request Type — no edit.

**G15 · SHIPPED 2026-08-25** as `tests-never-touch-production` (`cross-cutting` — area chosen at stage over "test areas": non-artifact-specific, write once, caught everywhere; plugin 2.54.0). Blocker. Isolation is constructed, not inherited: the check resolves each test's execution edges (server, database binding, injected stores) and fires on mutation paths that can reach non-test infrastructure — ambient-environment DSNs graded hits regardless of what the shell holds today. Discriminators from the falsifier run: a production URL literal handed to a pure function is inert fixture data (grep-and-flag on hostnames is the characteristic false positive — the run's one real-hostname literal was exactly that), live external reads are flakiness notes not this blocker, and `.sqlite(.memory)` was found as the conformant shape in the wild. The Fluent generator learned the ephemeral-binding rule in the same stage (its Tests section was silent on the database side).

**G16 · Shared module required — SHIPPED 2026-08-25 as doctor R13.** Every `@ViewModel` declaration must live in a shared ViewModels module (`Sources/ViewModels` or `Sources/…ViewModels`); ViewModels embedded in an app or server target are the legacy failure this exists for. Error (tier 1), silent when no ViewModels exist. v1 limit recorded in the doctor design: module-hood is the layout convention, not per-target source membership.

**G12 · SHIPPED 2026-08-25** as `behavioral-suite-standing` (`cross-cutting` — behavioral suites span artifact kinds, and the always-triggering area suits a standing check; plugin 2.55.0). Warning. Two clauses: standing (a visible requirements register with no behavioral suite → one gap note; no visible register → no finding, review cannot demand a projection of arguments it cannot see) and code-visible isolation shadows (`@testable import` anywhere in a behavioral suite — the writer's payload carried public signatures only; implementation-module imports; form drift in the generator's naming/traceability conventions, reported as form only). The check text explicitly forbids the reviewer from judging assertions against the implementation — channel disagreement classifies upward, never as a finding against the test. Verification: the falsifier carries an in-repo specs tree and no behavioral suite — the standing clause fired as designed; the isolation clauses are STATIC CHECK (no behavioral suite exists on any approved target yet).

**G17 · SHIPPED 2026-08-25** as `existentials-answer-the-question` (`cross-cutting`, plugin 2.56.0). Warning, under the ruled scope: parameters exempt; stored `any P`, `[any P]` collections, and existential returns must answer the principle's own question, and the finding names the cost and the alternative (generic, primary associated type, enum over a closed set, concrete type). The falsifier run produced zero unanswered existentials and banked the answers the check now names: the injected-dependency seam (N protocol dependencies where generics metastasize N type parameters — the ruling's exempted burden, strengthened by cold-path dispatch), the seam's transitively-erased resources, third-party protocol idioms, and open heterogeneous mixes. Cross-referenced so nothing double-reports: `vm-holds-scalars-only` keeps the `@Observable`-conformer blocker and delegates its value-typed-remainder note here; the computed `operations` idiom and the platform's untyped-error convention are the framework's and platform's own answers.

**G18 · SHIPPED 2026-08-25** as `docc-serves-the-customer` (`cross-cutting`, plugin 2.57.0). Warning; three judgment clauses, each reported as an aggregate with representative sites: undocumented/example-free public API graded by whether the symbol has customers; implementer's-frame DocC with relocate-don't-delete as the remedy and the frame test (caller-serving vs maintainer-serving) over tell-words; theatrical internal comments — with the lying-comment blocker and published-representation kept under their own names. Falsifier run: zero real hits on an exemplary DocC surface, and both detection folds came from its false alarms — the attribute-stack lookthrough (`@ViewModel` sits between DocC and declaration, so adjacency-keyed detection reports the best-documented idiomatic types as undocumented) and tell-words-are-hints (a provisional-sounding scope note is customer information).

**G20 · SHIPPED 2026-08-25** as `one-top-level-appstate` (`view`, SwiftUI surface, plugin 2.51.0). Warning. Minted at the owner's direction, outside the walk: the environment injection surface stays small — one top-level Application State `@Observable final class` at the root beside `MVVMEnvironment`, values reaching VMs as scalars through `.bind(appState:)`; every custom `@Entry`/`EnvironmentKey` and every additional environment-vended `@Observable` is an injection obligation previews and test hosts pay (crash for `@Environment(X.self)`, silent default for custom keys), and the single class is the persistence seam for resume-where-you-left-off. The statement was authored into architecture-patterns.md in the same stage (check-may-lead's inverse), the app-setup generator's multiple-environment-values section re-taught from invitation to discipline, and the App State resolved by role, not name. Non-hits: SwiftUI built-ins, the framework's surface (`MVVMEnvironment`, `Validations`, FOSMVVM's internal entries), component-vended styling entries, and a subtree-scoped store that answers the statement's question. Falsifier run clean: the SwiftUI target's whole surface is `mvvmEnv` + one root-injected project `@Observable` — zero entries, zero false positives; no `@Entry`-bearing drifted target exists on file, so the proliferation detection itself is STATIC CHECK until one does.

**G21 · SHIPPED 2026-08-25** as `stubs-record-they-dont-do` (`cross-cutting`, plugin 2.60.0). Warning. Minted at the owner's direction during the `tap(provenBy:)` seam design: stub Operations record the call, never perform the operation's work — a UI test proves the button is wired, not that the operation does something, and a working stub turns the wiring test into a timing-dependent behavior test. Statement authored into the viewmodel generator's StubOps line in the same stage (it stated only the positive). Non-hits keep the family coherent: recorder assignments, the handed `output` write (`stub-mutates-what-it-is-handed` requires it), protocol-forced `async` with no `await`; work reaching production-shaped infrastructure escalates to `tests-never-touch-production`. STATIC CHECK — no drifted target on file exhibits a working stub; the falsifier's stubs are recorders throughout.

**G19 · SHIPPED 2026-08-25** as `suites-serialize-shared-state` (`cross-cutting`, plugin 2.58.0) — the register's final stage. Warning. Shared mutable state is more than `X.shared`: `static var`s, the process environment, fixed-path fixtures; read-only `.shared` accessors are not mutations. The framework-fact boundary is stated honestly: `.serialized` protects within a suite only — cross-suite state needs a test-owned gate scoped to the racing window (a conformant shape found in the wild) or dependency injection per the companion lesson, and findings on that shape name one of those, not just the trait. The statement was authored into all three test generators (§Parallelism and Shared State) in the same stage — they were uniformly silent. Falsifier run conformant: nine `.serialized` suites plus a purpose-built env-mutation gate.

**G22 · SHIPPED 2026-08-25** as `directives-spell-their-tool` (`cross-cutting`, plugin 2.62.0). Warning. Fires on the spelling only — a directive-shaped comment whose token matches no tool the repo runs; correctly-spelled directives stay the justification/validity checks' business. Falsifier clean (its directives are all correctly spelled); the true-positive shape is banked from the W1 run's four template files, fixed same day.

**G23 · SHIPPED 2026-08-25** as `deferral-pointers-resolve` (`cross-cutting`, plugin 2.62.0). Warning. QUALIFIED: the falsifier run found two live true positives — deferral comments citing path-drifted spellings of the real ledger (a `docs/<sub>/deferrals.md` that never existed, a plans path likewise) beside siblings citing the real `docs/deferrals.md` correctly — exactly the path-drift shape the check names as the common case. External URLs and issue references are out of scope.

**G24 · SHIPPED 2026-08-25** as `versioned-baseline-committed` (`viewmodel-test`, plugin 2.62.0). Warning. The never-had form, complementing `versioned-baselines-not-regenerated`'s destroyed form; `clientHostedFactory` VMs exempt. Falsifier conformant — a populated, committed baseline tree per server VM; the true positive is banked from the scaffold — and the scaffold ships no baselines BY DESIGN (ruled 2026-08-25): the skeleton is a template the user replaces, and their own first test runs produce their own baselines; this check is the reminder that they get committed. Generator already states the committed-artifact rule — no edit.

**G25 · SHIPPED 2026-08-25** as `server-installs-the-error-middleware` (`serverrequest`, plugin 2.62.0). Blocker. Detection verifies WHICH module's middleware is installed, not merely that a line exists — `Vapor.ErrorMiddleware.default` type-checks while installing the wrong one. Falsifier conformant (module-qualified installation at boot, validating the spelling as field idiom); the true positive is banked from the scaffold's first test run (validator ran, client saw a bare 500). A project-authored equivalent is a judgment call, stated as such.

**G26 · SHIPPED 2026-08-25** as `views-dont-mint-prose` (`view`, SwiftUI surface, plugin 2.62.0). Warning, the narrowed ruled form with its three carve-outs (user-authored input, typed values, machine text) plus the `#Preview` exemption. The view generator's Hardcoding Text section learned the operation-argument extension in the same stage. Falsifier clean (no prose literals flow into ops); the true positive is banked from the scaffold's "New Card" literal (which itself remains the queued G26-shaped template follow-up: the default title belongs on the VM, localized).

**G27 · SHIPPED 2026-09-02** as `no-string-backed-enums` (`cross-cutting`, blocker, plugin 2.66.0). The truth statement was authored the same day into FOSMVVMArchitecture.md (§ Enums never take a `String` raw value) — check-may-lead in reverse: the rule had been stated in review many times and never written down, and the architecture doc's own "Simple Errors" section taught the anti-pattern. Surfaced by a review of the framework's own `CredentialRejectedError`. The same stage swept the framework's five String-backed FOSMVVM enums, the seven teaching sites (architecture doc, three generator references, the serverrequest generator, the serverrequest check's example, two DocC articles), and shipped `LocalizableString.localized(case:parentType:)` so a case localizes without a string in user code.

## Minor uncovered clauses

Recorded for completeness; none warrants its own stage — fold each into the nearest stage's authoring:

- An API offering two spellings of one conversion — both `a.b` and `B(fromA:)` — where the rule is exactly one spelling, on the owner. Fold in beside `stringly-typed-identity`.
- The extension-only-member trap (a conformer's "override" that silently does nothing through the protocol) is checked only for Fields protocols today; the same trap exists on any protocol. A widening of `overridable-members-are-requirements`.
- An operation written as a free function instead of a method on the Operations protocol escapes every ops check. Fold in beside the ops checks.
- ~~A display type renamed only to dodge sharing a name with a domain type~~ — folded 2026-08-25 into `request-names-follow-the-dictionary`'s collision-contortion clause, per plan.
- Whether the project's own test suite verifies Fields ↔ adopter agreement (review verifies the agreement directly today; the project's tests may not). Inside G2's stage.
- Forward-projection rule 3 — re-projection happens in the parent view body that builds the `AppState` — is reviewer guidance today, not a check. Revisit if field drift shows up.

## Backward audit — checks without a truth-statement anchor

Every check not listed here traces cleanly to a statement above, to the framework's published contract, or to the skill's own mechanics (`suppression-without-justification`).

**B1 · `ops-naming-trio` — CLOSED 2026-08-25.** The `{Name}ViewModelOperations` rule appeared in the generator only; NAMES.md §3a now states it (check-may-lead: the check shipped first, the statement caught up).

**B2 · view/VM stem correspondence — CLOSED 2026-08-25.** NAMES.md §3b now states the rule the stem clause of `viewmodel-view-one-to-one` enforces.

**B3 · the `{name}FieldsValidateModel(validations:fields:)` exemption — CLOSED 2026-08-25, ratified.** The composition-seam reasoning (a type adopting two Fields protocols writes one `validate` calling both prefixed helpers; the helper is a seam, not an override point) is now stated in the fields generator beside its requirement-plus-default callout, and the check's pending note is dropped.

**B4 · `view-no-read-through-vm-ref` contradicted the truth layer — RULED 2026-08-25, check corrected.** The check's What began "A VM may hold a reference to its `@Observable` state for ops dispatch" — architecture-patterns.md's rule 4 says the VM **never** stores an `@Observable` reference, even as a pass-through, with the ops-dispatch case handled by the View's own `@Environment`. David ruled the doctrine correct and the check wrong; the check now names the stored reference as the root cause. G7 remains open as the systematic ViewModel-side check (the corrected check still only fires when a View *reads* through the reference; a stored reference nothing reads yet escapes the `view` area's globs).
