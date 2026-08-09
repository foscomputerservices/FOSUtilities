# FOSMVVM Project Bootstrap — Design

**Date:** 2026-07-24
**Status:** Draft for review
**Owner:** David Hunt

---

## 1. Problem

Setting up a new FOSMVVM project is a multi-day slog.

The pain is not creativity — it is roughly forty exact settings and
structural decisions that must all be right at once, plus a fresh
Claude instance whose mainstream Xcode/SPM instincts fight the
FOS-mvvm way at every step.

Evidence was mined from the complete conversation history of the
most recent full bootstrap (the client-server witness, 2026-06-30 → 07-09)
and from structural surveys of all canonical example repos.
Findings that shape this design:

- **The slog clusters; it does not arrive as single issues.**
  Standing up one new framework target detonates four failures in
  one afternoon: missing `DEVELOPMENT_TEAM` → Team-ID dyld
  rejection; `BUILD_LIBRARY_FOR_DISTRIBUTION` misspelled plural
  (a silent no-op); localization resource flattening; and a direct
  FOS link that breaks type identity.

- **The single biggest turn-sink is Claude's architectural
  reflexes, not Xcode.** Hand-rolled HTTP gateways, invented
  Operations transports, URL munging, "let me fix the framework"
  escalations — each 10–15+ turns, recurring across sessions.

- **The SPMLibraries war recurs with every fresh Claude.** Four
  distinct counter-argument shapes were catalogued. What ends the
  argument is the correctness failure signature stated first
  (`TypeA != TypeA`: static linking compiles a separate copy of
  the types into each target; `is` / `as?` / `==` fail across
  target boundaries at runtime, far from the cause). What invites
  the argument is prose that justifies the umbrella on DRY or
  hygiene grounds.

- **Prose guidance loses to instinct; deterministic tooling does
  not argue.** A skill section labeled "Optional" was proven (by
  a RED test during skill authoring) to invite deletion of the
  umbrella.

## 2. Goals

- From idea to a **running, verified walking skeleton** for any of
  the four project shapes in one sitting, driven by a customer's
  own Claude Code session with no FOS author in the room.
- Generated projects are **born with the settled doctrine** in
  their context files, so the recurring arguments are pre-won.
- The tooling is **verified by CI on every release**, so templates
  cannot silently rot as FOSUtilities evolves.

**Finish line per generated project** (app-bearing shapes:
local-only, client-server, hybrid): builds, tests pass, app
launches to a stub screen, one ViewModel wired end-to-end per
door, localization YAML round-trip proven, UI-test harness proven,
CI config present, and (server types) the server boots and serves
the walking-skeleton route.

**Finish line, shared-library shape** (no app target exists):
`swift build` and `swift test` green, one ViewModel with
package-hosted localization wired end-to-end, the translations
test proving the YAML round-trip through `Bundle.module`, and CI
config present. App-launch and UI-harness criteria do not apply.

## 3. Non-goals

- Multi-repo project layouts. Single-repo overlay only; multi-repo
  projects are rare enough to assemble manually.
- Maintaining the `.xcodeproj` over the project's lifetime with
  XcodeGen. The generator scaffolds; it does not maintain
  (regeneration destroys hand-built synchronized folders).
- Migrating existing projects to the canonical shape. The `doctor`
  subcommand audits them; it does not rewrite them.
- Server-backed Operations conventions (under active development
  in FOSMVVM; the templates must not freeze an unsettled pattern).

## 4. Decisions already made

- **Approach:** deterministic scaffolder + thin skill wrapper
  (chosen over pure prompt-driven generation and over
  clone-and-rename template repos).
- **Placement:** new repo `foscomputerservices/fosmvvm-bootstrap`.
  The user's front door remains the `fosmvvm-generators` plugin;
  the skill clones the bootstrap repo silently at a pinned tag
  (the `vapor new` pattern — the repo never enters the customer's
  mental model).
- **Repo layout generated:** single-repo overlay only.
- **xcodeproj generation:** XcodeGen one-shot. Convert to
  synchronized folders in Xcode afterward, commit the
  `.xcodeproj`, delete `project.yml`. (Structurally forced:
  XcodeGen cannot emit `PBXFileSystemSynchronizedRootGroup`.)
- **Scaffolder language:** Swift. The type-safety principle
  applies to our own tooling; bash templating is the stringly-
  typed hole the house rules exist to prevent.

## 5. The four project shapes and their witnesses

Each template is extracted from — and stays verified against — a
known-good canonical instance:

- **local-only** — witness: the local-only witness app
  No root `Package.swift`. Native Xcode framework targets.
  SPMLibraries umbrella required (FOS via remote package).
  Client-hosted localization: `.clientHostedFactory` ViewModels,
  `resourceBundles` present, `Bundle.main` resource access,
  folder-synced YAML. `deploymentURLs` may still point at a
  foreign server, or be empty for truly serverless apps
  (both variants offered).

- **client-server** — witness: `FOS/FOSShowcase`
  `Package.swift` + xcodeproj at root. No umbrella: the shared
  contract folder is compiled twice (SPM `ViewModels` target and
  Xcode app group). Vapor `WebServer` executable, server-hosted
  YAML (`initYamlLocalization`), `register(viewModel:)` routes,
  no `resourceBundles` on the client.

- **hybrid** — witness: the client-server witness's main checkout **plus**
  a client-hosted witness worktree (the client-hosted half).
  Overlay: 26-target SPM package + xcodeproj over one tree; the
  app re-compiles the client subgraph via synchronized folders
  and consumes FOS only through the SPMLibraries umbrella.
  Server door: contract module (client) + Factory/Live projection
  (server), two ingress groups, `.live` wiring
  (`useAppState` + `register(request:app:)` +
  `useLiveInvalidation`). Client door: a dedicated Xcode-only
  client-VM framework target (absent from `Package.swift`),
  `Bundle(for:)` resource access named `localizationBundle`,
  split YAML trees by hosting, `resourceBundles` with exactly the
  framework bundle and no `resourceDirectoryName`.
  Coexistence: correlation seam — the server VM exposes a
  correlation key (AgentID) and the view joins; never one VM
  serving both doors.

- **shared-library** — witness: the shared-library witness app
  SPM library package. Package-hosted localization
  (`.copy("Resources/Localizations")`, `Bundle.module`).
  Optional preview/UI-test harness xcodeproj and sibling Vapor
  service package.

## 6. Components

### 6.1 Template tree (repo `fosmvvm-bootstrap`)

```
fosmvvm-bootstrap/
├── Package.swift            # CLI executable target
├── Sources/Bootstrap/       # typed Swift scaffolder
├── Templates/
│   ├── shared/              # fragments composed into every type:
│   │   ...                  #   SPMLibraries.swift (full rationale
│   │                        #   comment — never the stripped form),
│   │                        #   SystemVersion+{App}.swift, testplans,
│   │                        #   CI YAML, seeded CLAUDE.md + memory files
│   ├── local-only/
│   ├── client-server/
│   ├── hybrid/
│   └── shared-library/
└── .github/workflows/       # scaffold-all-four, build-green CI
```

Shared fragments live once and are composed per type — no
quadruplication, no drift between types.

Rendering is simple token substitution over a typed manifest.
No general-purpose template language.

### 6.2 Parameters

**Asked** (collected into a typed `BootstrapConfig`; also loadable
from a config file for re-runs):

- project name
- project type (one of the four)
- bundle-id root
- `DEVELOPMENT_TEAM` ID
- platforms + deployment targets
- server flavor: none | in-repo Vapor executable | foreign URL
- deployment environments + URLs (clean hosts, no paths)
- live invalidation on/off (server types only)
- auth: none | credential middleware group (no path prefixes)
- license header text

**Derived — never asked** (leak-proofing; each of these was a real
defect when left as a free input):

- per-module bundle-id suffixes from the single root
  (prevents the `com.example.app.SPMLibraries`-in-another-app
  class of leak)
- `resourceBundles` from localization hosting
  (the real client/server tell; never a free input)
- ResourceAccess form by build model:
  `Bundle.module` (SPM library) / `Bundle(for:)` (Xcode framework)
  / `Bundle.main` (folder-synced into app)
- entitlements posture from project shape. The
  `disable-library-validation` entitlement is a **symptom of
  shape**, not a setting to ask about: required only when the app
  embeds ad-hoc-signed PackageFrameworks dylibs or signing is off;
  the correct fix is usually the shape, not the entitlement.
- localization hosting itself defaults by type
  (client-server: server-hosted; local-only: client-hosted;
  hybrid: both; shared-library: package-hosted)

### 6.3 Scaffolder CLI (`fosmvvm-bootstrap`)

Phases:

1. **interview / load** — gather or read `BootstrapConfig`;
   validate before touching disk.
2. **emit** — render templates and `project.yml`.
3. **generate** — run `xcodegen generate`.
4. **verify** — `swift build`; `xcodebuild build`; run test
   targets; for server types boot the server and fetch the
   walking-skeleton route. Verification failures are fatal and
   reported precisely — the tool never hands over a broken
   skeleton. Note: verify runs on the XcodeGen output, *before*
   the manual synchronized-folder conversion (§6.6); the
   conversion changes ergonomics only, never correctness, so the
   verified artifact and the finished artifact differ only in
   group style.
5. **handoff** — print the human finishing checklist (§6.6).

**`doctor` subcommand.** Audits an existing project against the
settled rules table:

- `SWIFT_VERSION = 6.0` on every target
- `BUILD_LIBRARY_FOR_DISTRIBUTION` spelled singular, value `NO`
  (the silent-typo class)
- `TEST_HOST` / `BUNDLE_LOADER` pinned when target name ≠
  `PRODUCT_NAME`
- FOS products linked only via the SPMLibraries umbrella;
  no second direct link anywhere
- umbrella framework embedded with sign-on-copy into app and
  test bundles
- `DEVELOPMENT_TEAM` present on every target
- entitlements posture matches shape
- YAML trees split correctly by hosting
- testplan target references not dangling (the re-minted-UUID
  trap)
- deployment-target floors: the xcodeproj deployment targets and
  the `Package.swift` `platforms:` line (both manually
  maintained) agree with each other, **and** both are ≥ the
  pinned FOSUtilities platform minimums — under source-inclusion
  the app's real floor comes from the linked FOS products, not
  from anything the repo declares

`doctor` exists because the friction cluster fires again whenever
a framework target is added *after* bootstrap. Generator skills
invoke it after any target-touching change; it turns the one-shot
scaffolder into a lifetime guardrail. It shares the rules table
with the emitter, so the rules are written once and tested once.

`doctor` reports; it never rewrites.

### 6.4 Walking-skeleton content

FOSShowcase-flavored placeholder domain in every template — never
a customer domain or proprietary reference (zero-tolerance rule).

Per door, one ViewModel wired end-to-end:

- **client-hosted door** — `.clientHostedFactory` ViewModel, YAML
  in the correct tree, `resourceBundles` entry, a
  `ViewModelView`, stub Operations seam (`isStub ? StubOps() :
  LiveOps()`), UI test proving the harness.
- **server door** — RequestableViewModel + Factory, two-locale
  YAML, `register(viewModel:)` (or the auth-grouped form),
  server boots, route fetched during verify.
- **hybrid extras** — one `.live` ViewModel with `useAppState` +
  `register(request:app:)` + `useLiveInvalidation`, and the
  correlation-seam pattern documented in place (server VM exposes
  the key; the view joins; never one VM serving both doors).
- **shared-library shape** — no app door. One ViewModel product
  with package-hosted localization: two-locale YAML under
  `Resources/Localizations` declared with `.copy`, a
  `{Lib}ResourceAccess.localizationBundle` accessor returning
  `Bundle.module`, and a DocC comment showing a downstream app
  passing that bundle in its `resourceBundles`. Tests prove the
  codable round-trip and the translations round-trip. The
  preview/UI-test harness xcodeproj (as in the shared-library witness
  witness) is out of v1 scope.

### 6.5 Skill wrapper (`fosmvvm-project-bootstrap`, in the plugin)

The skill is the customer's entire experience:

1. gather parameters conversationally
2. `git clone --depth 1 --branch <pinned-tag>` the bootstrap repo
   into a scratch directory
3. `swift run fosmvvm-bootstrap` against the new project directory
4. walk the finishing checklist with the user
5. verify green; discard the clone

The skill never hand-builds project structure. If the CLI fails,
the skill reports the failure; it does not improvise the missing
pieces (improvisation is the re-litigation vector this design
exists to close).

### 6.6 Human finishing checklist (printed by `handoff`)

Steps tooling structurally cannot do:

1. Open the project in Xcode; convert the enumerated groups to
   synchronized folders (`PBXFileSystemSynchronizedRootGroup`),
   including any exception sets.
2. Confirm signing: real `DEVELOPMENT_TEAM` on every target.
3. Add secondary destinations (iPad, visionOS) if wanted.
4. Delete `project.yml`; commit the `.xcodeproj`. From here the
   xcodeproj is hand-maintained — do not regenerate.

### 6.7 Doctrine layer (seeded context files)

Every generated project is born with:

- **`CLAUDE.md`** — SOLID grounding plus the instinct-override
  catalog (the largest turn-sink in the mined history):
  - routes are type-derived; middleware ≠ path prefix; never
    munge URLs
  - never hand-roll HTTP gateways or transport parameters —
    `MVVMEnvironment` / ServerRequests are the only door
  - views are generated from ViewModels, never transcribed from
    mockups
  - the generator skills are the way code is added; hand-rolling
    is the exception that needs justification

- **memory files** (settled-doctrine memos, pre-won arguments):
  - **SPMLibraries** — correctness-first statement
    (`TypeA != TypeA`, the mechanism, "nothing to do with FOS —
    a generic Xcode+SPM packaging bug"), the four catalogued
    counter-argument shapes with their rebuttals, closed with
    "settled — arguing it is a long dead-end."
    The four shapes, mined verbatim from the client-server witness
    history:
    1. *"The umbrella is dead weight / just DRY / Optional."*
       Rebuttal: static linking compiles a separate copy of the
       types into each target; `is` / `as?` / `==` / `===` fail
       across target boundaries at runtime, far from the cause.
    2. *"This second framework needs FOS — I'll link
       FOSFoundation/FOSMVVM directly into it."*
       Rebuttal: two link sites → two non-identical copies
       (e.g. `SystemVersion` from framework A ≠ framework B);
       every framework consumes FOS from SPMLibraries only.
    3. *"The boundary broke my iOS build — let's make the host
       code iOS-safe / invent a transport tier."*
       Rebuttal: the failure is a correct signal from the
       boundary; fix by extracting the platform-bound code, not
       by softening the contract module.
    4. *"Undefined-symbol errors — the umbrella wiring must be
       wrong."*
       Rebuttal: that is Xcode's incremental-build staleness
       artifact (see the stale-build runbook), not a wiring
       defect.
  - **stale-build runbook** — bogus undefined-symbol errors and
    silently-stale `.o` files are an Apple incremental-build
    cache bug: fix with Xcode clean build; never
    `rm -rf DerivedData` (races the SPM re-clone and corrupts
    checkouts); keep the xcodeproj's resolved FOS pin in
    lockstep with `Package.swift`.
  - **entitlement-is-a-symptom** — when to genuinely need
    `disable-library-validation` and why changing the shape is
    usually the fix.
  - **platform FAQ** — `xcodebuild build-for-testing` on macOS
    fails for any framework linking package-frameworks (shared
    Xcode limitation, reproduced across four independent apps):
    run those test targets on the iOS Simulator.

- **FOSUtilities-side change (separate small PR):** add the
  SPMLibraries type-identity section to
  `.claude/docs/FOSMVVMArchitecture.md`. Today the doctrine lives
  only inside one skill; the architecture doc is the source of
  truth the skills defer to.

### 6.8 CI and testing

- **Bootstrap repo CI**, on every tag (tags track FOSUtilities
  releases; bootstrap `0.10.x` pins FOSUtilities `0.10.x`):
  scaffold all four types → `xcodegen` → build → test → server
  smoke. A customer can never receive a skill/template pair that
  does not build.
- **Published outputs:** the four CI-scaffolded skeletons are
  pushed as browsable example repos named
  `fosmvvm-example-{type}` under the `foscomputerservices`
  GitHub org — discharging the standing "examples built on
  FOSShowcase, not customers" goal as a side effect.
- **CLI unit tests:** config-derivation rules and template
  emission snapshots. The rules table shared by emit and `doctor`
  is tested once, used twice.

## 7. Versioning and distribution

- Customer front door: the `fosmvvm-generators` plugin (skills),
  exactly as today.
- The bootstrap skill carries the pinned bootstrap-repo tag.
  Plugin version bumps (already standard practice on skill
  changes) deliver pin updates.
- Bootstrap releases are cut against each FOSUtilities release
  after its CI goes green.

## 8. Risks and mitigations

- **Template drift vs FOSMVVM evolution** — mitigated by
  release-gated CI (§6.8); a template that no longer builds
  blocks the bootstrap release, loudly.
- **XcodeGen capability drift** (e.g. future synchronized-folder
  support) — the finishing checklist shrinks if XcodeGen gains
  the capability; the design does not depend on it.
- **Customers skipping the finishing checklist** — the skeleton
  builds and runs before handoff; skipped steps degrade
  ergonomics (enumerated groups) but not correctness. `doctor`
  flags the omissions.
- **Unsettled FOSMVVM areas** (server-backed Operations) —
  explicitly out of scope; templates carry the "under active
  development, do not treat as settled" marker in the seeded
  `CLAUDE.md`.

## 9. Resolved review questions (decided 2026-07-24)

- **Example repos:** `fosmvvm-example-{type}` under the
  `foscomputerservices` GitHub org (reflected in §6.8).
- **`doctor` ships in v1** (it shares the rules table with the
  emitter; most of its cost is already paid).
- **Platform floor under source-inclusion** — two invariants,
  both encoded:
  1. the xcodeproj deployment targets and the `Package.swift`
     `platforms:` line are manually maintained and must agree;
  2. both must be ≥ the pinned FOSUtilities platform minimums,
     because the app's real floor comes from the FOS products it
     links, not from anything the repo declares.
  Generation seeds defaults from the FOS floor and validates
  asked-for targets against it; `doctor` checks both invariants
  (reflected in §6.3).
