# `doctor` — design

**Status:** RATIFIED (David, 2026-08-23). Concepts, names, rule table, and severities all ruled. Implementation plan: `planning/implementation-plans/fosmvvm-doctor.md`.

**Origin:** the Plan 5 item. Declared in spec §6.3 (`docs/superpowers/specs/2026-07-24-fosmvvm-project-bootstrap-design.md:229`), promised for v1 in §9, distributed as an SPM command plugin by the migration design §3b. Never built. David's framing on 2026-08-23: something a legacy user runs to get an existing app aligned with the generated structure.

---

## What you already ruled

These are recorded, not re-argued.

**The rules table is a sibling truth artifact.** Not a thing the templates project from, and not a diff against a reference emission. It is declared once; doctor reads it to audit a customer's project, and a conformance test reads it to prove our own templates still satisfy it.

**XcodeProj models the object graph.** `tuist/XcodeProj` 9.16.0, two small dependencies. The resolve-only cost to Mac consumers of FOSUtilities is not a concern. It tracks pbxproj format drift so we don't.

**Declared values, not resolved.** v1 reads the file as written. `--resolved` (shelling to `xcodebuild -showBuildSettings`) stays available later if xcconfig inheritance turns out to matter in the field.

**`--shape` when known.** A legacy project has no config to read. The two shape-conditional rules report as unchecked rather than guessing.

**Read-only.** Every finding carries an exact remedy; the tool never writes. Rewriting, if it ever happens, is a separate tool with its own name.

**Error/warning split, non-zero exit on errors only.** Generator skills invoke doctor after target-touching changes, so it needs a machine verdict.

**All ten rules in v1, plus the two the templates proved** (R11, R12 below).

**Entitlements posture is an error, not a warning.** A client-server app missing `network.client` fails at runtime, which puts it in the same class as the rest.

**Names:** `ProjectRule`, `Finding`, `AuditedProject`, `Doctor.Report`, `Severity`, `Doctor`. No `RuleSet` type — a static `all` on `ProjectRule` instead. The medical metaphor stops at the command name.

---

## Two of the spec's ten rules are stale

Writing the table forced a reconciliation against the shipped templates. This is the reconciliation, and it is the first evidence that ruling 1 was the right call — nothing else would have surfaced these.

### Rule 4 — "no second direct link anywhere" is now false

Spec `:237`: *"FOS products linked only via the SPMLibraries umbrella; no second direct link anywhere."*

The templates deliberately violate that, and say so. `Sources/FOSMVVMBootstrap/Templates/client-server/project.yml.tmpl:48`:

```yaml
      # FOSTesting is deliberately NOT here: the umbrella embeds in the shipping
      # app, and testing products don't ride along. Test targets link FOSTesting
      # directly — their FOSTesting types are never shared across targets, so
      # the type-identity rule doesn't apply to them. (Ruled 2026-08-19.)
```

Both shapes link `FOSTesting` and `FOSTestingUI` straight into their test targets — `project.yml.tmpl:174` and `:207` in client-server, `:120` and `:142` in local-only.

So the rule splits in two. **Shipping products** (`FOSFoundation`, `FOSMVVM`, and on the server side `FOSMVVMVapor`) enter only through SPMLibraries. **Testing products** enter only through test targets, and never through SPMLibraries.

Worth noting that a doctor written to the spec's text would have flagged our own templates. It would also have flagged `Tools/UITestingProbe`, whose pbxproj carries six direct FOS product links — that one is a deliberate probe rather than a doctrine-conformant app, but it is a useful reminder that the rule needs the split to be usable at all.

### Rule 5 — test bundles do not embed

Spec `:239`: *"umbrella framework embedded with sign-on-copy into app and test bundles."*

The templates embed into the app **only**. Everything else links. `Templates/local-only/project.yml.tmpl:62`:

```yaml
    dependencies:
      - target: SPMLibraries
        embed: false          # link only — the app embeds (single-embed rule)
```

The unit-test target at `:114` does the same, because its `TEST_HOST` is the app, which already carries the embedded copy. Embedding again would put a second copy in the bundle — the exact type-identity failure the umbrella exists to prevent.

So the rule is **single-embed**: the app embeds SPMLibraries and every local framework with sign-on-copy; every other target links only.

---

## The rules table

Twelve, restated against what the templates actually do.

**R1 — `SWIFT_VERSION` is `6.0` on every target.** Severity: error.

**R2 — `BUILD_LIBRARY_FOR_DISTRIBUTION` is spelled singular and set `NO`.** Severity: error. This is the silent-typo class from the friction cluster, so the check also scans for near-miss keys (the plural spelling above all) and reports them by name — a missing setting and a misspelled one look identical to Xcode but not to a reader.

**R3 — unit-test targets pin `TEST_HOST` and `BUNDLE_LOADER`.** Severity: error. Required when the target name differs from `PRODUCT_NAME`; the templates pin unconditionally at `project.yml.tmpl:112`. UI-test bundles are exempt — they use `TEST_TARGET_NAME` and carry no `TEST_HOST`.

**R4a — shipping FOS products enter only through SPMLibraries.** Severity: error. See the reconciliation above.

**R4b — testing FOS products enter only through test targets.** Severity: error. Their presence in SPMLibraries means testing code is riding into the shipping app.

**R5 — single-embed.** Severity: error. The app embeds SPMLibraries and each local framework with sign-on-copy; every other target links without embedding.

**R6 — `DEVELOPMENT_TEAM` is present on every target.** Severity: error. Its absence is the Team-ID dyld rejection.

**R7 — entitlements posture matches the shape.** Shape-conditional. Severity: error. Client-server carries `app-sandbox` and `network.client`; local-only carries `app-sandbox` alone. A client-server app without `network.client` cannot reach its own server, and it fails at runtime rather than at build — which is what put this at error rather than warning. `disable-library-validation`, if present, is reported with the symptom explanation from the seeded memory file.

**R8 — localization YAML trees are split by hosting.** Shape-conditional. Severity: warning — this one is a structural convention where a customer's legitimate layout can differ, and it is the only rule in the table doctor cannot be certain about.

**R9 — testplan target references are not dangling.** Severity: error, and only when a `.xctestplan` exists — client-server ships one, local-only does not. This is the re-minted-UUID trap.

**R10 — deployment floors hold, both ways.** Severity: error. The xcodeproj deployment targets and the `Package.swift` `platforms:` line must agree with each other, and both must be at or above the pinned FOSUtilities floors in `FOSPlatformFloor.floors` (`Sources/FOSMVVMBootstrap/FOSPlatformFloor.swift:14`). Projects with no root `Package.swift` — local-only is one — get the floor half only.

### R11 and R12 — the two the spec never named

Neither appears in spec §6.3, because both failures were mined after it was written. Both are correctness rather than style, and both are ruled in.

**R11 — `CODE_SIGN_STYLE` is `Automatic` on app-bearing projects.** Severity: error. Absent, Xcode defaults to Manual and ⌘U cannot sign or launch the app or its test host — the tests simply never run. The setting is the "Automatically manage signing" checkbox, written literally at `Templates/client-server/project.yml.tmpl:23`.

**R12 — `ENABLE_HARDENED_RUNTIME` is `NO` in the Debug configuration of macOS app targets.** Severity: error. Xcode signs SPM package frameworks ad-hoc, with no Team ID; under a hardened runtime, library validation refuses to map them and the app dies in dyld before `main()`, which kills macOS UI testing entirely. Release keeps it `YES` so notarization still works, so the rule is Debug-only — a project with it off in both configurations gets a separate finding.

A third candidate, `SWIFT_STRICT_CONCURRENCY: complete`, is deliberately left out — it is a house preference rather than a thing that breaks.

### R13 and R14 — the shared-module pair (addendum, ruled 2026-08-25)

Ruled onto the table from the fosmvvm-review coverage ledger (its G16 and G6): both are deterministic, so they belong in this tier rather than in a review check. The table grows to fourteen. Neither needs `--shape` or an `.xcodeproj` — they read scanned Swift sources, so they run for every shape, shared-library included. Test sources are excluded from the scan: a ViewModel declared in a test target is a fixture, and test targets legitimately import server products.

**R13 — ViewModels live in a shared ViewModels module.** Severity: error. Every non-test source declaring `@ViewModel` must live under `Sources/ViewModels/` or `Sources/…ViewModels/` — the home every template emits and the architecture doc's own convention. The strays collapse into one finding (one omission, one remedy), and the rule is silent when no `@ViewModel` exists anywhere: there is nothing to place. The typed content anchors the finding; the name only defines the sanctioned home.

**R14 — the shared ViewModels module imports no server code.** Severity: error, per file. No source under a shared-module root may import the server family — `Vapor`, `Fluent*`, `Leaf`/`LeafKit`, `FOSMVVMVapor`, `VaporTesting`/`XCTVapor`/`FOSTestingVapor`. The dependency points one way: the server imports the shared module, never the reverse; the Factory, server-side, is the one place that sees both.

**Stated limits, v1.** The sanctioned home is the `Sources/<module>` layout convention — an Xcode project whose `ViewModels` directory is not actually a separate framework target passes undetected, because per-target source membership is not read. An import of the project's *own* server target by name is not caught either; that needs manifest target parsing. Both wait for field evidence before buying their complexity.

---

## The public surface

Four names. `ProjectRule` and `AuditedProject` are ratified but land **internal** — nothing outside the module constructs a rule or a read model, and the access-minimalism rule says they stay in the engine room until a caller demands otherwise.

```swift
public enum Doctor {
    public static func examine(projectAt: URL, shape: ProjectShape? = nil) throws -> Report
}

extension Doctor {
    public struct Report: Sendable {
        public let findings: [Finding]
        public let unchecked: [String]
        public var hasErrors: Bool { get }
        public var text: String { get }
    }
}

public struct Finding: Sendable {
    public let severity: Severity
    public let target: String?
    public let summary: String
    public let remedy: String
}

public enum Severity: Sendable { case error, warning }
```

**`Finding` carries no rule identity.** The human reader wants prose, the generator skill wants the exit code, and the conformance test wants the list empty. Nobody needs to name a rule programmatically yet, so it is not on the surface. Add it when a caller exists.

### DisableableRule — the one thing a finding names (addendum, ruled 2026-09-02)

The first customer run halted on a finding the customer holds on purpose: an ops app that runs unsandboxed because it must reach local infrastructure. Doctor findings are exempt from every review override, so that project could never reach tier 2. Ruled: the disablement lives in `.fosmvvm-review.yml`, it opens only on findings doctor itself marks, and the vocabulary is SwiftLint's — rules, snake_case rule identifiers, `disabled_rules` — so nothing has to be learned.

The caller that exists needs to name a *disableable rule*, not a table row. A table-row identity would be the wrong grain — R7 emits three different findings for one target, only one of which is a choice — and a per-finding identity catalog would be thirty names nobody asked for. So `Finding` gains one optional field:

```swift
public struct Finding {
    public let rule: DisableableRule?   // nil on every finding that is simply wrong
}

public enum DisableableRule: String, CaseIterable, Codable {
    case appSandbox = "app_sandbox"
}
```

`DisableableRule` is the closed set of rules the generated shape always satisfies but an app may break on purpose. It has one case. `network.client` is not one (without it a client-server app cannot reach its own server); `disable-library-validation` is not (it is a symptom); hardened runtime in Debug is not (it kills UI testing); linkage and embedding are never choices. New cases are ruled onto the enum one at a time, on field evidence, the way rules are ruled onto the table.

The config nests under `doctor:` — `doctor.disabled_rules`, entries of `rule`, `target`, `reason` — so it never sits beside tier 2's `disabled_checks` as a near-twin key. The JSON carries the identifier verbatim on the findings that have one, and omits the key elsewhere, so parsers written against the earlier shape are unaffected. `Report.text` appends one line under such a finding naming the identifier, so the person reading the terminal knows what to write. Doctor's own verdict does not change: `hasErrors` stays true, the exit code stays non-zero, because doctor reports facts. The review skill applies the config — a matched finding reports at warning with the reason beside it, and the skill recomputes its gate from what remains — and an entry naming a rule doctor did not print is reported as unmatched, never honored.

**The fuller alignment, not taken yet.** SwiftLint stamps every violation with its rule identifier. Giving all fourteen doctor rules identifiers would let `disabled_rules` and future reporters address any of them; it is fourteen names to arbitrate and no caller asks for it. It waits, like the rest, for a caller.

**`Report.text` renders once, in the library.** Both front ends print the same thing. This follows `HandoffChecklist.text(for:projectName:)`, which is already the repo's shape for this.

**`unchecked` is display prose, not identity** — entries read like "entitlements posture (needs --shape)". It is a message, in the same category as `summary` and `remedy`, so it is not the stringly-typing the encapsulation rule forbids.

### DocC, drafted from the call site

```swift
/// Audits an existing project against the rules the scaffolder generates by,
/// and reports what has drifted — without changing anything.
///
/// ```swift
/// let report = try Doctor.examine(projectAt: URL(filePath: "/Users/me/MyApp"))
/// print(report.text)
/// if report.hasErrors { throw ExitCode.failure }
/// ```
///
/// Reach for this after adding a framework target by hand, or when adopting
/// FOSUtilities in a project the scaffolder never touched — the settings that
/// go wrong (the misspelled distribution flag, a second direct FOS link, a
/// missing team id) fail at runtime, far from their cause.
///
/// > Note: Pass `shape` when you know it. Entitlements posture and localization
/// > YAML layout can only be judged against a known shape; without one they are
/// > reported as unchecked rather than guessed at.
```

---

## Tests

**Contract tests, public path only.** `Doctor.examine` against fixture projects committed under `Tests/FOSMVVMBootstrapTests/Fixtures/` — one clean project per shape, plus one deliberately broken project per rule. Assert the finding is present and its severity, never the rendered wording.

**The conformance test is the one from ruling 1** — emit a project, run `xcodegen`, examine it, assert no findings. It proves the templates satisfy the table, which is what makes the table truth rather than a second opinion.

That test needs `xcodegen` on the machine, so it cannot join the fast suite. It rides the env-gated walking skeletons in `Tests/FOSMVVMBootstrapTests/IntegrationTests.swift:33`, which already emit each shape and generate its `.xcodeproj` — the assertion is two lines at the end of each existing test rather than a new one. Chosen over the generation-matrix CI job because a red skeleton reproduces locally and a red CI job does not.

**No `@testable`.** Rules and the read model are internal, but everything asserted goes through `examine`.

---

## Rationale and gotchas

**Why the fixtures are committed rather than generated.** A broken-project fixture has to stay broken. If it were emitted, fixing the emitter would silently repair the fixture and the test would pass while checking nothing.

**Why declared values are enough for v1.** Every rule in the table is a setting the templates write literally, at a known level. Inheritance matters when a customer introduces xcconfigs, which is exactly when they will reach for `--resolved`.

**R9 honours `containerPath` (corrected 2026-08-24).** It first validated every `.xctestplan` in the tree against the root project, which is wrong the moment a repo holds more than one Xcode project. Pointed at a real codebase, it reported a dangling reference for a plan whose `containerPath` named a sibling project that had not been generated yet — a confident finding about a file that was not its business. References naming another container are now skipped. Both corrections in this section came from the same exercise, and neither was reachable from a project the scaffolder had generated: those are correct by construction, so they can only confirm the rules, never falsify them.

**The manifest scan reads both spellings (corrected 2026-08-24).** It first read only string literals, on the reasoning that the scaffolder emits `.macOS("14.0")`. That was the wrong subject: doctor exists for projects the scaffolder never created, and those are usually written `.macOS(.v14)` — as FOSUtilities' own manifest is. The narrow scan meant R10's floor check silently did nothing for most of its actual subjects while reporting a warning that read like a limitation rather than a miss. Caught by running the plugin from a throwaway consumer package, which is why that gate was worth executing rather than assuming.

**The sandbox, now measured (2026-08-24).** The prediction was right but imprecise, and the precise answer matters for `--resolved`.

Spawning a process under the plugin sandbox **works** — a throwaway probe plugin ran `xcodebuild -version` to exit 0. What fails is writing: `xcodebuild -showBuildSettings` exits **74**, because it cannot create its DerivedData log store (*"You don't have permission to save the file 'Build' in the folder 'Logs'"*).

So the barrier is a write denial, not a spawn denial, and it is outside the package directory — which means `--allow-writing-to-package-directory` would not lift it. A future `--resolved` either requires `--disable-sandbox`, or is available only from the CLI door and not the plugin.

Reads outside the package directory are permitted: the plugin audited a project elsewhere on disk without complaint.

**Why a third executable target exists.** `Plugins/FOSMVVMDoctor` cannot invoke `FOSMVVMBootstrapCLI`. SwiftPM resolves a command plugin's tool by executable *target* name, and that target is vended under the renamed `fosmvvm-bootstrap` product, so the build fails with *"Could not find target named 'FOSMVVMBootstrapCLI-product'"*. Renaming the documented command to satisfy the plugin would be the tail wagging the dog, so `Sources/fosmvvm-doctor-tool` is a plugin-only entry point that parses two flags and calls the same `Doctor.examine`. It is a door, not a second implementation.

**The `Emitter` is untouched.** Ruling 1 means no re-projection of templates that are not stale, and the load-bearing comments stay where they were mined.

---

## Not in scope

**Rewriting anything.** Ruled read-only.

**The `hybrid` shape.** It has no template tree — `Emitter.swift:56` throws `shapeNotImplemented` — so the table is written against three shapes.

**macCatalyst.** Dropped in migration design §10.7. Its `FOSPlatformFloor` entry retires with the multi-platform work; the table does not carry it.

**The deferred iCloud-output-path check.** Named in the ledger handoff; it is an emitter-side input guard rather than a project invariant, and it does not belong in this table.

---

## Nothing outstanding

Every point raised in review was ruled on 2026-08-23: R11 and R12 in, entitlements posture at error, conformance test in the skeletons. `Severity` and `Doctor` were carried uncontested.

The one rule at warning is R8, and it is there because a customer's localization layout can legitimately differ from ours. Everything else is an error, so the exit code means what a generator skill needs it to mean.
