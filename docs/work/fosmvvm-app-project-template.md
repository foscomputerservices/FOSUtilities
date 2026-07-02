# FOSMVVM SwiftUI app — reusable `project.yml` template + recipe

> Copied into FOSUtilities from the Harbor Port-Authority worktree on 2026-07-02 (backlog
> item C3). This is the version-controlled home; the `fosmvvm-swiftui-app-setup` skill
> references it. Harbor type names (`HarborViewModels`, `PortAuthority`) are illustrative.

A verified, parameterized XcodeGen `project.yml` for a FOSMVVM SwiftUI **app** that lives beside a
SwiftPM package in one tree, plus the recipe explaining *why* each load-bearing piece exists.
Configuring these projects by hand takes hours because of Xcode's quirks (the `SPMLibraries` umbrella
for type identity, source-inclusion of the shared module, app-hosted test targets, the test plan).
This template makes it a one-shot.

Reverse-engineered from David's hand-built `PortAuthority.xcodeproj` and **verified to build**
(`xcodebuild … build-for-testing` → `** TEST BUILD SUCCEEDED **`: the app + an app-hosted unit-test
bundle + a UI-test bundle all compile and link). It supersedes/refines the `fosmvvm-swiftui-app-setup`
skill's Template 7 — see the deltas at the bottom.

---

## The shape (FOSMVVM "Option A" — source-inclusion)

```
{AppName}.xcodeproj                     ← derived from project.yml; git-ignored
Sources/
  SPMLibraries/SPMLibraries.swift       ← umbrella framework (the ONLY doorway for SPM products)
  {ViewModelsModule}/                    ← shared CONTRACT module: ViewModels/ Requests/ Versioning/
  {ViewsModule}/                         ← the SwiftUI Views layer
  {AppTarget}/                           ← the App layer: {AppName}App.swift + Info.plist + .entitlements
Tests/
  {Base}UnitTests/                       ← app-hosted unit tests (share the app's FOS type identity)
  {Base}UITests/                         ← UI tests
{AppName}.xctestplan                     ← aggregates the two test targets (see the caveat)
```

Three collaborators:

1. **`SPMLibraries`** — a thin framework that links FOSFoundation/FOSMVVM (and any other external SPM
   product). It is the *single* place external products enter the build. Every target that needs FOS
   types links this ONE framework, so there is exactly one copy of each FOS type.
2. **The app (`{AppTarget}`)** — compiles the shared contract module's source (`{ViewModelsModule}`)
   and the Views (`{ViewsModule}`) **directly** alongside its own App layer (Option A: source is
   *included*, not linked as a separate framework). It links **only** `SPMLibraries`.
3. **The test bundles** — host on the app (`TEST_HOST`/`BUNDLE_LOADER`), so they see the app's exact
   FOS type identity. That app-hosted linkage is the real proof the umbrella works.

---

## Why each piece is load-bearing (the recipe)

### 1. The `SPMLibraries` umbrella — type identity (`TypeA != TypeA`)
**Rule:** an Xcode app that consumes SPM package products across more than one target (app + unit
tests + UI tests) MUST vend them through a single umbrella *dynamic* framework that every other
target depends on — **never** link the SPM products directly into each target.

**Why:** linking an SPM library into multiple targets compiles a *separate copy* of its types into
each, and Swift's mangled type name carries the linking context — so the "same" type has a different
runtime identity per target. An instance crossing a target boundary then fails `is` / `as?` / `==` /
`===`. It **compiles clean and breaks at runtime far from the cause.** One umbrella framework = one
canonical copy = one shared identity. This is a generic Xcode+SPM packaging bug, *not* a FOS quirk —
but it bites FOSMVVM especially hard because FOSMVVM internals compare types (type-derived request
paths, ViewModel/Request resolution, versioning). Do NOT "simplify" by linking FOS per-target.

`SPMLibraries.swift` can be almost empty (`import Foundation`); its job is to *link* the products so
they exist once. (Optionally `@_exported import FOSFoundation` / `@_exported import FOSMVVM` to let
consumers write `import SPMLibraries` — but with source-inclusion the included files just
`import FOSFoundation` directly and resolve transitively through the linked umbrella.)

### 2. Source-inclusion of the shared module (Option A)
The app target's `sources:` list the **folders** of the shared contract module and the Views layer,
so they compile *into* the app module. Views then reference ViewModels with no cross-module `import`.
XcodeGen emits classic file references (globs the folders), not Xcode-16 `fileSystemSynchronizedGroups`
— the build resolves identically because both compile the same set of files. `import FOSFoundation` /
`import FOSMVVM` inside the included source resolves through the linked `SPMLibraries` (Xcode
propagates a linked framework's SPM product modules to the linking target).

### 3. App-hosted test targets + the target-name/PRODUCT_NAME trap
Make the unit-test target **depend on the app target** → XcodeGen sets it up as app-hosted
(`TEST_HOST`/`BUNDLE_LOADER`), so it links against the app and shares its FOS types.

**Trap:** if the app **target name differs from its `PRODUCT_NAME`** (here target `PortAuthorityUI`,
product `PortAuthority`, bundle `PortAuthority.app`), XcodeGen derives `TEST_HOST` from the *target*
name (`…/PortAuthorityUI.app/…/PortAuthorityUI`) which does not exist → the unit test fails to link
with `ld: library '…/PortAuthorityUI' not found`. Pin it explicitly:
```yaml
TEST_HOST: "$(BUILT_PRODUCTS_DIR)/{ProductName}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{ProductName}"
BUNDLE_LOADER: "$(TEST_HOST)"
```
(If you keep target name == PRODUCT_NAME, XcodeGen derives this correctly and you can omit it.)

### 4. Test-target naming — never bare `{AppName}Tests`/`{AppName}UITests`
For an app whose name ends in `UI`, `{AppName}Tests` = `PortAuthorityUITests` *reads* as a UI-test
name, and `{AppName}UITests` = `PortAuthorityUIUITests` doubles the "UI". Strip a trailing `UI` to get
`{Base}`, then name them **`{Base}UnitTests`** (unit) and **`{Base}UITests`** (UI). Unit tests should
say "Unit".

### 5. No `disable-library-validation`
Do **not** add `com.apple.security.cs.disable-library-validation` to the app entitlements. That escape
hatch is only needed when a macOS hardened-runtime app loads an **ad-hoc-signed SwiftPM
`PackageFrameworks` dylib** (Team ID mismatch). Here the app links `SPMLibraries.framework`, which is
built and signed with the app's own Team ID, so hardened-runtime library validation passes. The app's
entitlements stay minimal (e.g. `app-sandbox` + `network.client`).

### 6. Deployment target ≥ every **linked** package's platform floor (source-inclusion changes this)
The app's `deploymentTarget` must be **>= the platforms of every package it LINKS** — here that is
**FOSUtilities** (via `SPMLibraries`), not Harbor's own `Package.swift`. This is a real distinction
under Option A: the app **source-includes** `HarborViewModels` rather than linking its product, so
`Package.swift`'s `platforms: [.macOS(.v26)]` **does not constrain the app** — it only constrains code
that *links* the Harbor product (server targets, other packages). The included source imposes only its
own API-availability needs. So the app's floor = the linked FOS products' floor + whatever the included
files require. Keep `SWIFT_VERSION`, `SWIFT_STRICT_CONCURRENCY`, `DEVELOPMENT_TEAM`, and the
distribution flag in `settings.base` so every target inherits them uniformly.

### 7. `BUILD_LIBRARY_FOR_DISTRIBUTION` — mind the spelling
The real Xcode setting is the **singular** `BUILD_LIBRARY_FOR_DISTRIBUTION`. The plural
`BUILD_LIBRARIES_FOR_DISTRIBUTION` used by some templates is a **no-op typo**. For an in-tree app set
`BUILD_LIBRARY_FOR_DISTRIBUTION: NO` — YES enables module stability you don't need and breaks
`@_spi`/`package` access.

### 8. The `.xctestplan` caveat (the one thing XcodeGen can't faithfully reproduce) ⚠
A hand-authored `.xctestplan` pins each test target by a **UUID + container** (e.g.
`identifier: 7A00A3E2…`, `container:{AppName}.xcodeproj`). XcodeGen mints its **own** target UUIDs on
generate, which will NOT match — so after a regenerate the plan's target references dangle and the
`test` action shows missing targets. XcodeGen references the plan file as-is; it does not rewrite it.

The build itself is unaffected (list the test targets in the scheme's `build.targets`), so app + both
test bundles compile/link regardless — only the Xcode `test` action needs the plan valid. Pick one:

- **(A) Regenerable default — no committed plan.** Drop the `.xctestplan`; let the scheme's `test`
  action list the test targets directly (`test.targets:`). Fully regenerable, nothing to reconcile.
  Recommended unless you specifically want a shared plan.
- **(B) Keep the committed plan — reconcile UUIDs once.** After the first real `xcodegen generate`,
  open the plan in Xcode and re-add the two test targets so Xcode writes the *generated* UUIDs.
  XcodeGen UUIDs are deterministic per project+target, so this one-time fix survives future
  regenerations. Also fix any stale `container:` name left in the plan's `defaultOptions`.

---

## The template

Placeholders:

| Placeholder | Meaning | PortAuthority value |
|---|---|---|
| `{AppName}` | Project name = `.xcodeproj` name | `PortAuthority` |
| `{AppTarget}` | App target name (may differ from `{AppName}`) | `PortAuthorityUI` |
| `{ProductName}` | App `PRODUCT_NAME` / `.app` bundle name | `PortAuthority` |
| `{ViewModelsModule}` | Shared contract module folder under `Sources/` | `HarborViewModels` |
| `{ViewsModule}` | Views layer folder under `Sources/` | `PortAuthorityUIViews` |
| `{Base}` | App name with a trailing `UI` stripped (for test names) | `PortAuthority` |
| `{BundleID}` | App reverse-DNS bundle id | `com.cirtecmed.harbor.portauthority` |
| `{BundleIDRoot}` | Reverse-DNS root for framework/test ids | `com.cirtecmed.harbor.port-authority` |
| `{TeamID}` | Apple developer Team ID | `4U3ZN9L8FT` |
| `{macOSDeployment}` | macOS deployment target (≥ package floor) | `26.0` |
| `{FOSUtilitiesRef}` | FOSUtilities version pin (match `Package.swift`) | `branch: main` |

```yaml
name: {AppName}

options:
  deploymentTarget:
    macOS: "{macOSDeployment}"          # >= every depended package's platform floor
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    BUILD_LIBRARY_FOR_DISTRIBUTION: NO   # singular! the plural is a no-op typo
    DEVELOPMENT_TEAM: {TeamID}

packages:
  FOSUtilities:                          # match the SwiftPM Package.swift ref exactly (single copy)
    url: https://github.com/foscomputerservices/FOSUtilities.git
    {FOSUtilitiesRef}

targets:
  # ── SPMLibraries: the ONE doorway for external SPM products (type identity) ──
  SPMLibraries:
    type: framework
    platform: macOS
    sources:
      - path: Sources/SPMLibraries
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIDRoot}.SPMLibraries
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - package: FOSUtilities
        product: FOSFoundation
      - package: FOSUtilities
        product: FOSMVVM
      # Add every other external SPM product HERE, once.

  # ── The app: source-includes the shared module + Views (Option A); links only SPMLibraries ──
  {AppTarget}:
    type: application
    platform: macOS
    sources:
      - path: Sources/{AppTarget}
        excludes:
          - "Info.plist"
          - "{AppTarget}.entitlements"
      - path: Sources/{AppTarget}/Info.plist
        buildPhase: none
      - path: Sources/{AppTarget}/{AppTarget}.entitlements
        buildPhase: none
      - path: Sources/{ViewsModule}
      - path: Sources/{ViewModelsModule}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleID}
        PRODUCT_NAME: {ProductName}
        INFOPLIST_FILE: Sources/{AppTarget}/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/{AppTarget}/{AppTarget}.entitlements  # NO disable-library-validation
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "0.1"
        CURRENT_PROJECT_VERSION: 1
    dependencies:
      - target: SPMLibraries
        embed: true
        codeSign: true

  # ── App-hosted unit tests: share the app's FOS type identity ──
  {Base}UnitTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/{Base}UnitTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIDRoot}-unit-tests
        GENERATE_INFOPLIST_FILE: YES
        # Only needed when {AppTarget} != {ProductName}; pin TEST_HOST to the real product.
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/{ProductName}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{ProductName}"
        BUNDLE_LOADER: "$(TEST_HOST)"
    dependencies:
      - target: {AppTarget}
      - target: SPMLibraries
        embed: false                     # link only; the app already embeds it

  {Base}UITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: Tests/{Base}UITests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {BundleIDRoot}-ui-tests
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: {AppTarget}

schemes:
  {AppName}:
    build:
      targets:
        {AppTarget}: all
        {Base}UnitTests: [test]
        {Base}UITests: [test]
    run:
      config: Debug
    test:
      config: Debug
      # Option A (regenerable default): drop the plan, list targets here instead —
      #   targets: [ {Base}UnitTests, {Base}UITests ]
      # Option B (committed plan): reference it, and reconcile its target UUIDs once (see caveat #8).
      testPlans:
        - path: {AppName}.xctestplan
          defaultPlan: true
    archive:
      config: Release
```

---

## Verify (throwaway name — never overwrite an open project)
If the real `.xcodeproj` is open in Xcode, generate under a throwaway name, build, then delete it:
```bash
sed 's/^name: {AppName}$/name: {AppName}Verify/' project.yml > project.verify.yml
xcodegen generate --spec project.verify.yml
xcodebuild -project {AppName}Verify.xcodeproj -scheme {AppName} \
  -destination 'platform=macOS' build-for-testing CODE_SIGNING_ALLOWED=NO
rm -rf {AppName}Verify.xcodeproj project.verify.yml
```
`build-for-testing` compiling+linking BOTH test bundles against the app is the type-identity proof
(an app-hosted test can only link if it shares the app's single FOS instantiation). Note: under a
throwaway name the committed `.xctestplan`'s `container:{AppName}.xcodeproj` won't match, so verify
via the `build`/`build-for-testing` action (which uses `build.targets`), not the `test` action.

---

## Lifecycle: generators **scaffold**, they don't **maintain** (David, 2026-07-02)

The generator is a **one-shot scaffolder**, not a lifetime project manager. It earns its keep exactly
once — creating the project — because it nails the hard, easy-to-forget setup (the `SPMLibraries`
umbrella, source-inclusion, app-hosted tests, the `TEST_HOST` pin, Swift 6 + strict concurrency) that
is tedious and error-prone by hand, and that Claude in particular should not hand-author into a raw
`.pbxproj`. Once the project is **stable**, the tweaks a project accrues over its life (a build
setting, a destination, a folder) are few and are better made **in Xcode by hand** — regenerating
clobbers them. So:

1. **Scaffold once** with this template (or have Claude run it).
2. **Do the two things XcodeGen structurally can't**, once, in Xcode after the final generate:
   - **Synchronized folders (`PBXFileSystemSynchronizedRootGroup`).** XcodeGen (through 2.45.4) emits
     classic **enumerated** groups — it globs the folder at generate-time and lists each file. It does
     **not** emit Xcode-16 synchronized folders (the ones that auto-mirror the filesystem: add a file
     on disk → it's in the target, no regen). The build is identical either way, but the
     *auto-mirroring* is lost. Re-add `{ViewModelsModule}` / `{ViewsModule}` / `{AppTarget}` as
     **synchronized folders** in Xcode. (Deemed critical here — treat its absence as the reason not to
     keep regenerating.)
   - **iOS/iPadOS destinations** (see below).
3. **Commit the `.xcodeproj`** (stop git-ignoring it) — it is now the hand-maintained source of truth.
   Keep `project.yml` as a documented **seed** (how the project was born), *not* a live regen target.
   Regenerate only for a from-scratch rebuild, re-applying the two hand steps.

### The concurrency win — the template beats Xcode's own new-app default
Verify the generated project carries `SWIFT_VERSION 6.0` + `SWIFT_STRICT_CONCURRENCY complete` and
**zero** `SWIFT_APPROACHABLE_CONCURRENCY` / `SWIFT_DEFAULT_ACTOR_ISOLATION` keys. A fresh Xcode 26 app
enables **Approachable Concurrency** by default (`@MainActor`-by-default, relaxed isolation) — which
you may explicitly *not* want. Because XcodeGen sets only what `project.yml` declares, you get clean
strict-complete concurrency **without** the IDE's relaxed defaults. That is a reason to scaffold from
this template even though you hand-maintain afterward. (If you ever *do* want approachable concurrency,
you must add those keys yourself — they won't appear on their own.)

### iOS/iPadOS is a **destinations-only** change under source-inclusion
Because the app **source-includes** the shared module rather than linking its product (recipe #2 / #6),
supporting iOS/iPadOS needs **no package change** — only destinations, provided the included source is
iOS-clean (no host-only APIs). On the app, `SPMLibraries`, and **both** test targets, replace:
```yaml
    platform: macOS
```
with (single multi-platform target — **not** `platform: [macOS, iOS]`, which splits into per-platform
targets and breaks a single-name scheme entry):
```yaml
    supportedDestinations: [macOS, iOS]
```
and add `iOS: "26.0"` alongside `macOS` under `options.deploymentTarget`. The macOS-specific
`.entitlements` is harmless on iOS (sandbox is implicit there). For Harbor this Just Works: the
included `HarborViewModels` is FOSMVVM-only and iOS-clean, and the not-iOS-clean modules
(`HarborChannel`/`HarborAdmin`) are **not** included, so nothing gates it. This template ships
macOS-only for the walking skeleton; the change above is all that iOS/iPadOS needs.

---

## Deltas vs. the `fosmvvm-swiftui-app-setup` skill's Template 7
This template is the **Option A / source-inclusion** variant, verified against a real project. Vs.
the skill's current Template 7:

- **Option A vs Option B.** Template 7 gives the shared module (`ViewModels`) its own framework target
  that the app links+embeds. This template **source-includes** the shared module's folder into the app
  (Views reference ViewModels with no import) and keeps only `SPMLibraries` as a framework. Both are
  valid; Option A is what PortAuthority uses.
- **`BUILD_LIBRARY_FOR_DISTRIBUTION` spelling.** Template 7 emits the plural (no-op) form; use the
  singular.
- **Test-target names.** Template 7's `{AppName}Tests`/`{AppName}UITests` are ambiguous/doubled for a
  `…UI` app name; use `{Base}UnitTests`/`{Base}UITests`.
- **Target-name ≠ PRODUCT_NAME `TEST_HOST` trap.** Not covered by Template 7; pin `TEST_HOST` when
  they differ.
- **`.xctestplan`.** Template 7 doesn't mention one; if you commit one, reconcile its UUIDs once
  (caveat #8) or use the regenerable no-plan scheme.
- **`platform:` vs `supportedDestinations:`.** For a multi-platform (iOS+macOS) single target, use
  `supportedDestinations: [iOS, macOS]`, not `platform: [iOS, macOS]` (which splits into per-platform
  targets and breaks a single-name scheme entry). This template ships macOS-only for the skeleton;
  because the app source-includes (not links) the shared module, going multi-platform is a
  destinations-only edit — see "iOS/iPadOS is a destinations-only change" above.
- **Lifecycle + synchronized folders + concurrency.** Template 7 frames the generator as the project's
  ongoing definition; this template treats it as a **one-shot scaffolder** — after the final generate,
  hand-add synchronized folders (`PBXFileSystemSynchronizedRootGroup`, which XcodeGen ≤ 2.45.4 can't
  emit) and commit the `.xcodeproj`. It also calls out verifying **no** Approachable-Concurrency keys
  (Xcode 26's new-app default) so you keep strict-complete concurrency. See "Lifecycle" above.

See `docs/work/skill-improvements-triage.md` for the triage that routed this into the skills.
