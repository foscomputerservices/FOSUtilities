# fosmvvm-bootstrap → FOSUtilities — migration design

**Status:** APPROVED (David, 2026-08-22) — all §10 points ruled; execution began same day.

**Provenance:** David's distribution framing (2026-08-22): the standard use case starts at swiftpackageindex.com / the FOSUtilities README / the FOSFoundation & FOSMVVM DocC — and from any of those it must be trivial to (a) create a project that incorporates FOSUtilities or (b) incorporate FOSUtilities into an existing project and diagnose it with `doctor`. Plus his standing note (2026-08-11): the hard-coded version pin is wrong in principle, and the bootstrap repo likely folds back into FOSUtilities.

---

## 1. Context — observations this design builds on

The decision under review is David's (2026-08-22): distribute the scaffolder through FOSUtilities. This section records the observed facts the design uses; it is not an argument for the decision — §10's questions and the red pen decide.

- Discovery today happens at FOSUtilities (SPI, README, DocC); the bootstrap repo is separate and unpublished.
- The scaffolder currently pins FOSUtilities via a hand-maintained string (`pinnedFOSVersion` + an UPDATE-BOTH comment); four bump rounds were performed during 0.12.6 → 0.13.3.
- FOSUtilities already hosts developer-facing tooling: the `fosmvvm-generators` skills (`.claude/`) and `Tools/UITestingProbe`.
- Three open bootstrap deferrals (release CI, example publishing, plugin-skill wrapper) overlap infrastructure this repo already has or would gain.

## 2. Costs and risks

- FOSUtilities' dependency graph gains `swift-argument-parser` (resolution-only for library consumers) and its tree gains ~30 template files plus the scaffolder sources/tests.
- The scaffolder's emit-and-verify integration tests — the repo calls them **walking skeletons**: each generates a complete project of one shape into a temp directory and runs that project's own verification doors (`swift build`, `swift test`, `xcodegen`, unsigned `xcodebuild build`) — are slow (~8 min) and network-resolving; ungated they would degrade this repo's `swift test`. §7 proposes the gate; if the gate is judged insufficient, that weighs against the move.
- The release ritual gains a mandatory step (§6's stamp); a test converts forgetting into CI failure, but the ritual is still longer.
- Repo scope widens: issues/PRs about scaffolding land on the framework repo.
- Reversal is cheap before the first release that ships the scaffolder, and expensive after (users will hold clone-and-run instructions).

## 3. What the user sees

**(a) Create a project** — README and DocC show one block, and it works from a bare clone:

```bash
git clone https://github.com/foscomputerservices/FOSUtilities.git
cd FOSUtilities
cat > /tmp/myapp.json <<'EOF'
{ "projectName": "MyApp", "shape": "clientServer",
  "platforms": { "macOS": "14.0" },
  "bundleIdRoot": "com.example.myapp", "teamId": "YOURTEAMID" }
EOF
swift run fosmvvm-bootstrap new --config /tmp/myapp.json --output ~/MyApp
```

Shapes: `localOnly`, `clientServer`, `sharedLibrary`. The generated project pins the FOSUtilities release the scaffolder shipped with (§6). A prebuilt-binary path (GitHub release artifact → optional Homebrew) is scoped to Plan 5, not this migration.

**(b) Incorporate + diagnose** — `doctor` ships as an **SPM command plugin**, so a user whose package already depends on FOSUtilities runs, with zero installation:

```bash
swift package fosmvvm-doctor
```

The plugin is the *distribution decision made now*; the doctor *implementation* remains the Plan 5 item. It shares the rules table with the emitter (same target), per the original spec.

## 4. Platform support for generated projects

**Ruled scope (David, 2026-08-22, red pen on §3):** generated projects must support all Swift-supported platforms in the end; immediately: **iOS, tvOS, watchOS, visionOS, macOS**.

Where this stands and what the design proposes:

- The config layer already accepts and floor-validates all six FOS platforms (the floors table carries iOS 17 / macOS 14 / macCatalyst 17 / tvOS 17 / watchOS 10 / visionOS 1), and the `platforms:` line already flows into the emitted `Package.swift`. The gap is the Xcode layer: `SUPPORTED_PLATFORMS` is pinned to `macosx` and only `MACOS_DEPLOYMENT` is derived (the tracked multi-platform ledger item). macCatalyst is dropped from the supported set (ruled, §10.7).
- **Proposed shape: one multi-platform app target** (supported-destinations style, one bundle id), not per-platform targets. Evidence for feasibility: David hand-added the iPhone destination to the 0.13.3 ServerDemo and the full suite passed both destinations unmodified.
- Emission derives `SUPPORTED_PLATFORMS` and per-platform deployment settings from the config's `platforms` keys, replacing the macosx pin.
- Verification per platform: macOS and iOS run the full UI-test matrix (proven, §7). tvOS and visionOS run on their simulators. **watchOS UI testing is new in Xcode 27** (release notes, Testing → "Fixed: watchOS Unit and UI tests may not run on device", 178874363) — so all five platforms can carry UI tests on current toolchains; the probe README's "no XCUITest on watchOS" predates this cycle and should be updated when the watch harness lands. As with every platform, the probe verifies the tag/tap contract behaviorally when the watch harness is added — availability is Apple's documented word; behavior is measured. The templates' watch UI idioms need their own audit.
- **Proposed sequencing:** the migration lands with macOS + iOS emitted and CI-verified (both proven green today); tvOS, visionOS, watchOS follow inside this arc, each gated by its own probe/skeleton verification, before any release that advertises them. Open ruling: §9.6.

## 5. Target shape in FOSUtilities

Stacked, per piece (names are proposals — see §10):

- **`FOSMVVMBootstrap`** (library target) ← `Sources/BootstrapKit`, including `Templates/` as `.copy` resources. Renamed from `BootstrapKit`: in FOSUtilities the unprefixed name is too generic, and the FOS prefix matches every sibling.
- **`fosmvvm-bootstrap`** (executableTarget + executable product) ← `Sources/BootstrapCLI`. Product name unchanged — it is the documented command.
- **`FOSMVVMBootstrapTests`** ← `Tests/BootstrapKitTests`, split per §7.
- **`fosmvvm-doctor`** (command plugin) — declared in this design, built in Plan 5.

**Dependency:** the CLI adds `swift-argument-parser` to the graph (§2).

**Platform guard:** the scaffolder shells out (`Process`: xcodegen, xcodebuild, swift) and is macOS-only tooling inside a multi-platform package. The targets compile everywhere but the `Process`-using code is `#if os(macOS)`-guarded (pattern already used across FOSUtilities); the CLI prints a clear refusal elsewhere.

## 6. Version pin and floors — proposed derivation

**Pin:** `FOSMVVMBootstrap` carries one release-stamped constant (e.g. `Release.version`). The release ritual — already "stamp CHANGELOG, tag, gh release" — gains one mechanical step: the stamp commit also updates this constant. A unit test parses `CHANGELOG.md`'s topmost stamped release and asserts the constant matches, so a forgotten stamp fails CI, not a user. Generated projects keep the `from:` form, so they float onto later releases with a plain package update (proven by the 0.13.3 round).

**Between releases**, a scaffolder run from a working tree pins the last stamped release — correct behavior, worth one sentence in the DocC article.

**Floors:** the `FOSPlatformFloor` table stays (validation needs it at runtime) but gains a unit test that parses this repo's own `Package.swift` `platforms:` (via `#filePath`) and asserts equality. The UPDATE-BOTH comment dies; drift becomes a test failure.

## 7. Tests and CI — the two-speed split, extended to the full matrix

Ruled intent (David, red pen): CI must automate what the manual verification rounds did — the generated projects' own test suites, across all supported shapes, not just their builds.

- **Fast suite** (config, tokens, emitter file-sets, renderer, verifier unit tests — ~7 s) joins the normal CI matrix' macOS job unconditionally.
- **Walking skeletons** (defined in §2: one emit-and-verify test per shape, network-resolving, ~8 min total) gate behind an env var (e.g. `FOSMVVM_BOOTSTRAP_SKELETONS=1`) using a Swift Testing `.enabled(if:)` trait — bare `swift test` stays fast for everyone. The skeletons keep their current doors (emit + build + package tests + xcodegen + xcodebuild build); they do NOT run the generated UI tests — that is the matrix job's job, next.
- **The generation-matrix CI job** (macOS runner, `brew install xcodegen`) goes further than the skeletons — it automates the BIG TEST: for each app shape, `xcodebuild test` on the macOS destination and on an iOS simulator (the generated UI tests, exactly what David has been running by hand); `swift test` for the server/package sides and the shared-library shape. As platforms land per §4, their simulator destinations join this matrix (watchOS capped at build + unit tests). Runs on every PR (ruled, §10.4 — revisit if too draconian) and on release tags; covers the deferred "release CI" item and later carries example publishing.

CI-runner risk, stated: the local focus-battle activation failures we saw do not typically afflict dedicated CI runners, but the matrix job should retry once on activation failure and surface the xcresult on red — this is the least-proven part of the design.

Note: the skeletons resolve the *released* FOSUtilities from GitHub — they prove the cold-start user experience, not the working tree. A working-tree variant (path-override emission) is possible later but is not this migration.

## 8. Docs surfaces (DocC-first)

- **FOSMVVM DocC** gains the canonical article — `CreatingAProject.md`: the three shapes, the config JSON, the §3 block, what the walking skeleton verifies, the finishing checklist pointer, and the `doctor` teaser. Linked from the FOSMVVM landing page's topics.
- **FOSFoundation DocC** landing gets a short "Starting a new project?" callout linking to that article (FOSFoundation is the SPI default-doc landing, per David's step 2).
- **README.md** gets a "Create a project in one minute" section with the same block — the GitHub-front-door copy of the DocC truth.

One source of truth: the article; README carries the block plus a link, not a fork of the prose.

## 9. Mechanics of the move

**History:** plain copy at a chosen bootstrap SHA (ruled, §10.5). The bootstrap repo was never published and is simply retired — no archival ceremony; its history remains in David's local repo and Time Machine.

**What moves:** `Sources/BootstrapKit` (→ rename), `Sources/BootstrapCLI`, `Tests/BootstrapKitTests`, and the emitted-doctrine template tree (already inside `Templates/`).

**What migrates as content, not files:** the open deferrals-ledger items move into a `docs/deferrals.md` at FOSUtilities (same maintenance rule verbatim); RESUME.md gets a final entry and retires with the repo; bootstrap's CLAUDE.md doctrine merges into FOSUtilities' CLAUDE.md where not already present.

**What dies:** `pinnedFOSVersion` as a maintained string (→ release-stamped constant, §6), the UPDATE-BOTH comment (→ floors test, §6), the bootstrap repo's own CI ambitions (→ §7).

**Witness projects** (TestLocalOnly, TestClientServer) are untouched — they are David's truth layer, not the scaffolder's output.

## 10. Open questions for the red pen

1. **Library target name** — RULED (David, 2026-08-22): `FOSMVVMBootstrap`.
2. **Ledger location** — RULED (David, 2026-08-22): deferred. The planning process is being redesigned in the FOSUtilities-workflow worktree (`feature/fos-development-workflow`); the bootstrap ledger stays where it is until that process merges. The handoff telling that session what to incorporate is `2026-08-22-deferrals-ledger-to-workflow-handoff.md`, beside this design.
3. **Generated pin form** — RULED (David, 2026-08-22): keep `from:`.
4. **CI cadence** — RULED (David, 2026-08-22): the skeleton + generation-matrix jobs run on **every PR** for now; revisit if it proves too draconian.
5. **History** — RULED (David, 2026-08-22): plain copy; the bootstrap repo is simply retired (never pushed; Time Machine holds its history). No archival ceremony.
6. **Platform sequencing (§4)** — RULED (David, 2026-08-22): as proposed — migrate with macOS + iOS emitted and CI-verified; tvOS / visionOS / watchOS follow inside this arc.
7. **macCatalyst** — RULED (David, 2026-08-22): dropped ("I don't think that there's much of a future for macCatalyst"). Its floors entry retires with the multi-platform work; it is not advertised in any set.

## 11. Migration steps (each gate verifiable)

1. This design ratified (red pen → APPROVED).
2. Worktree in FOSUtilities; copy sources/tests; rename target; wire `Package.swift` (products, ArgumentParser dep, platform guards). Gate: `swift build` all products, macOS.
3. Port tests; add the two new enforcement tests (release-stamp ↔ CHANGELOG, floors ↔ platforms); env-gate the skeletons. Gate: fast `swift test` green; `FOSMVVM_BOOTSTRAP_SKELETONS=1 swift test` green.
4. Release-ritual change: stamp step + the constant; document in the release notes/process doc.
5. DocC article + FOSFoundation callout + README section. Gate: `swift package generate-documentation` clean; David reads the article as a first-time user.
6. CI: fast tests into the matrix; the skeleton job. Gate: both workflows green on the PR.
7. The generation-matrix job (§7) runs the automated BIG TEST — all shapes, macOS + iOS destinations, generated UI tests included. Gate: matrix green in CI; David's ⌘U becomes an optional spot-check, not a required step.
8. PR → merge → next release ships the scaffolder. Bootstrap repo: retired (§10.5).
9. Ledger + RESUME updates on both sides; the `fosmvvm-generators` skills' references to the scaffolder updated to the in-repo path.
