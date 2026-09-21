# Designed Parents — Implementation Plan

**Status:** UNRATIFIED — awaiting David's review. The *design* was ratified decision-by-decision on 2026-09-21 (rulings ledger below); this plan projects from those rulings.

**Scope:** replace `registerTestView(_:scrollable:)` with `registerTestView(_:designedFor:)` over a new `ProductionParents` option set, adding `.navigation` alongside `.scrolling`; pin both on iOS and macOS in the UI-testing probe; put the probe into CI; teach the distinction in the UI-test generator; and close the silent-failure gap with a conditional diagnostic.

**Origin:** a field report from a consuming app whose toolbar-bearing screen became untestable. The report is evidence and motivation only — no part of it, and nothing about its author, appears in sources, fixtures, commits, or shipped docs.

---

## Ratified rulings (2026-09-21 — do not re-litigate)

1. **Migration shape (b):** `designedFor:` is the one door. `scrollable:` is deprecated with a migration `message:`, and carries **no default** so existing bare call sites stay unambiguous.
2. **Names:** parameter label `designedFor:`, type `ProductionParents`, cases `.navigation` / `.scrolling`, default `[]`.
3. **Scope:** the navigation parent whole — `.toolbar`, `navigationTitle`, `NavigationLink` destinations, `.searchable`. DocC section becomes `## Declaring a View's Designed Parents`.
4. **Generator skill:** split the navigation test category into *in-view state change* (no parent) and *navigation push* (requires `.navigation`), and teach the distinction rather than deleting or blanket-requiring.
5. **Diagnostic:** `testHost()` plants the resolved registration's declared parents; the not-found message appends its hypothesis **only** when `.navigation` is actually absent.
6. **Platform:** iOS and macOS both pinned at ship. The probe's Mac test target gains the sources it needs to host `presentView()` at all, and the probe joins CI in this arc.

**Parked, not dropped** (to `docs/deferrals.md` in this arc): a per-capability × per-platform certification register, and closing the unmeasured visionOS hole.

---

## 0. Where this sits in the execution model

`shared/execution-model.md`'s dispatch table routes changes in an *app built with* FOSMVVM. This work changes FOSMVVM itself, where the framework's public API **is** the truth layer — there is no layer above to re-project from. So the traversal here is the planning gate's own order (surface → DocC → contract tests → rationale → tasks), not the Fields/DataModel/ViewModel chain. Flagging it because the dispatch table is silent on framework-internal work, which per the halt-state rule is a finding against that page rather than a licence to improvise. Worth a ruling line there eventually; not blocking.

---

## 1. Public surface — every symbol justified

All new API lives in `FOSMVVM`, file `Sources/FOSMVVM/SwiftUI Support/MVVMEnvironment.swift`, under `#if canImport(SwiftUI)`.

**Not under `#if DEBUG`** — and this is load-bearing. `registerTestView` is deliberately *not* DEBUG-gated; only its body is, so consumer helpers compile away to a no-op in release without the call site needing a guard (`MVVMEnvironment.swift:171`). A type appearing in that signature must therefore exist in release builds too.

### 1.1 `ProductionParents`

```swift
public struct ProductionParents: OptionSet, Sendable {
    public static let navigation = ProductionParents(rawValue: 1 << 0)
    public static let scrolling = ProductionParents(rawValue: 1 << 1)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
```

**Caller need:** a view's designed production parents are one fact with a growing set of values. Two independent `Bool` parameters spell one meaning in four ways and leave the nesting order expressible only in prose; an option set states it once and puts the ordering where it belongs — in the harness.

**Public symbols introduced: four** (the type, two static members, and `OptionSet`'s required `rawValue`/`init(rawValue:)` pair). No other members. `Equatable`/`Hashable` arrive free via `RawRepresentable`; `Sendable` is declared because a public struct does not get it implicitly across a module boundary, and the registry is `@MainActor` state.

### 1.2 `registerTestView(_:designedFor:)`

```swift
@MainActor public static func registerTestView<V: ViewModelView>(
    _ type: V.Type,
    designedFor: ProductionParents = []
)
```

**Caller need:** unchanged from the shipped contract — declare the view's designed production environment once, at registration, so no two tests can disagree about it.

### 1.3 `registerTestView(_:scrollable:)` — deprecated, transitional

```swift
@available(*, deprecated, message: "Declare the view's designed parents: scrollable: true becomes designedFor: .scrolling")
@MainActor public static func registerTestView<V: ViewModelView>(
    _ type: V.Type,
    scrollable: Bool
)
```

Forwards as `registerTestView(type, designedFor: scrollable ? .scrolling : [])`.

**The missing default is the whole trick.** With defaults on both overloads, `registerTestView(X.self)` is ambiguous and every existing bare call site stops compiling. Without one, bare calls bind to the new signature silently, and only `scrollable:` call sites warn — which is exactly the set that should.

`renamed:` cannot express `Bool` → `OptionSet`, so the migration rides in `message:`. Removal at **1.0**, not in a minor: consumers pin `upToNextMajorVersion`, so a minor removal would break them without a warning window.

### 1.4 The diagnostic channel (ruling 5) — `package`, never `public`

```swift
package enum TestHostFacts {
    package static let accessibilityIdentifier = "__testing_host_facts__"
}
```

**Caller need:** FOSTestingUI is a separate module in a separate *process*; it cannot read FOSMVVM's registry. It needs one thing — whether the hosted registration included `.navigation` — and the only route is the accessibility tree.

**Why `package` and not `public` (David, 2026-09-21).** Accessibility identifiers are transport infrastructure. The framework provides API *built on* that infrastructure; it does not hand the infrastructure to the app. A consumer never types this string, never queries this element, and must never learn that it exists — publishing it makes an implementation detail into a de-facto contract that can then never change.

`package` is the access level this is for, and it clears the repo's access-minimalism bar with a definitive why-required statement rather than a "might be public" hedge: **FOSTestingUI must read what FOSMVVM plants; they are separate targets of the same package (`Package.swift:142`, `:160`); no consumer of either module needs it.** The repo already uses `package` for exactly this shape in 40 declarations across `Sources/`.

**Public symbols introduced: zero.** The value planted is the registration's `rawValue`, reconstituted test-side through `ProductionParents(rawValue:)` — no new serialization, no second format, and nothing added to either module's public surface.

**Name flagged for arbitration.** `TestHostFacts` is a working name.

### 1.5 The same leak, already shipped — demoted (ruled 2026-09-21)

`TestDataTransporter.accessibilityIdentifier` is `public` today (`TestDataTransporter.swift:116`) and is the same category error: transport infrastructure on the consumer's surface.

```swift
    package static let accessibilityIdentifier = "__testing_view_data__"
```

**Ruled in.** Verified safe before proposing, on both boundaries that matter:

- **In-package:** the only reader is `ViewModelViewTestCase.swift:414` — FOSTestingUI, same package, so `package` reaches it.
- **Out-of-package:** nothing in `Tools/UITestingProbe` (a separate package consuming FOSUtilities by path) or in the bootstrap app templates references it. This is the check that could have bitten — `package` access does **not** cross a package boundary, so a probe or generated-app reader would have broken CI rather than merely warned.
- **Taught nowhere:** absent from every skill, the api-catalog, and every shipped document.

So no consumer has been told it exists, and none can be relying on it. This is a public-API removal in the letter and a no-op in practice; it still earns its own CHANGELOG line under Changed, stating the contract (the identifier was never consumer API) rather than the string.

### Gate checklist

**Minimal surface** — ✅ four public symbols total (the option set, its two cases, and `OptionSet`'s required `rawValue`/`init(rawValue:)` pair), plus the changed and deprecated `registerTestView` overloads. Each traced to a caller need above. The diagnostic channel adds **nothing** public. The option set gains no conveniences (`contains` is free). No second spelling of anything.

**Encapsulation** — ⚠️ **deviation, raised not hidden.** `OptionSet` conformance *requires* a public `rawValue` and `init(rawValue:)`, which is a publicly-constructable raw value on a public type. It is inert here: `ProductionParents` is a declaration of design intent consumed in-process by the harness, never an identity, never routed on, never persisted, never parsed by a consumer. The alternative — a bespoke struct with private storage and `ExpressibleByArrayLiteral` — hides `rawValue` at the cost of re-implementing `OptionSet` worse and losing `.contains`, for a value that has no wall to protect. Taking the conformance; recording the deviation.

**No stringly-typing** — ✅ net improvement; a `Bool` becomes a typed value.

**One serialization** — ✅ none added. The diagnostic channel ships an `Int` through an existing transport.

**Requirement + default** — n/a, no protocol.

**Don't publish the representation** — ✅ the bit values never appear in DocC, CHANGELOG, or README, and **no test pins them** — nothing persists them, so a shape test would be the representation assertion the gate forbids.

**Boundaries hold** — ✅ FOSMVVM only; no domain or persistence types involved.

---

## 2. Customer-facing DocC — drafted first

### `ProductionParents`

```swift
/// The production parents a *ViewModelView* is designed to live inside
///
/// Declare them where the view is registered, and `testHost()` presents the view
/// under the same parents production gives it:
///
/// ```swift
/// registerTestView(SettingsView.self, designedFor: .navigation)
/// registerTestView(DeviceCardView.self, designedFor: .scrolling)
/// registerTestView(DeviceDetailView.self, designedFor: [.navigation, .scrolling])
/// ```
///
/// A view that declares both is presented navigation-outermost —
/// `NavigationStack { ScrollView { view } }` — matching the way production nests them.
///
/// > Note: This states the view's *designed* environment, not a per-test preference.
/// > A view that declares nothing is presented bare.
```

### `ProductionParents.navigation`

```swift
    /// The view is designed to live inside a `NavigationStack`
    ///
    /// ```swift
    /// registerTestView(SettingsView.self, designedFor: .navigation)
    /// ```
    ///
    /// Declare it for any view that contributes to its navigation ancestor: `.toolbar`
    /// items, `navigationTitle`, `.searchable`, or `NavigationLink` destinations. All of
    /// those are preferences the *ancestor* renders — presented with no navigation parent
    /// the view still appears, but everything it declared for the bar is absent from the
    /// accessibility tree, and a test looking for a toolbar button finds nothing.
```

### `ProductionParents.scrolling`

```swift
    /// The view is designed to live inside a scrolling parent
    ///
    /// ```swift
    /// registerTestView(DeviceCardView.self, designedFor: .scrolling)
    /// ```
    ///
    /// Declare it for a view taller than a window in isolation — a form card inside a
    /// `ScrollView`, a section of a longer page. Presented bare, such a view compresses and
    /// overlaps, bottom controls sit beyond any tap's reach, keyboard avoidance displaces
    /// the whole content instead of scrolling, and XCUITest's scroll-to-visible has nothing
    /// to scroll.
```

### `registerTestView(_:designedFor:)` — the `designedFor:` parameter and its section

The existing DocC keeps its structure; `## Views Designed for a Scrolling Parent` (`MVVMEnvironment.swift:194`) becomes:

```swift
    /// ## Declaring a View's Designed Parents
    ///
    /// A view is rarely designed to stand alone. One lives inside a `NavigationStack` and puts
    /// its actions in the toolbar; another lives inside a `ScrollView` and is taller than any
    /// window. Presented bare, each loses something silently — the toolbar items never reach
    /// the accessibility tree, the buried controls sit beyond any tap. Declare the design fact
    /// at registration and the harness supplies what production would:
    ///
    /// ```swift
    /// registerTestView(SettingsView.self, designedFor: .navigation)
    /// registerTestView(DeviceCardView.self, designedFor: .scrolling)
    /// registerTestView(DeviceDetailView.self, designedFor: [.navigation, .scrolling])
    /// ```
    ///
    /// Both parents together nest navigation-outermost, as production does. A view that
    /// declares nothing is presented bare.
    ///
    /// > Important: `designedFor:` states the view's *designed* production environment — it
    /// > matches the harness to the design. It is not an escape hatch for a view that
    /// > overflows its production container too; that is a layout bug the harness should
    /// > keep surfacing. There is no per-test override: a suite that needs the same view
    /// > presented two ways is claiming the view has two designed environments — bring that
    /// > evidence to FOSUtilities rather than working around the declaration.
    ///
    /// - Parameters:
    ///   - type: The *ViewModelView* to make available to *ViewModelDisplayTestCase*
    ///   - designedFor: The production parents the view is designed to live inside
    ///     (default: `[]` — the view is presented bare, exactly as before).
```

The ratified `scrollable:` Important paragraph is carried over verbatim in substance — it is the contract this whole ruling turned on — with "both bare and scrolled" generalized to "two ways."

### Six symbol links to repoint

Adding a parameter renames the DocC symbol. All six update in the same commit as the signature: `ViewTesting.md:67`, `:125`, `:382`; `TestHost.swift:54`, `:107`; `UITestingElement.swift:743`.

---

## 3. Contract tests

### 3.1 Headless — `Tests/FOSMVVMTests/SwiftUI Support/TestViewRegistrationTests.swift`

The Linux `swift test` leg is the only one that runs everywhere, so the registry record is pinned there. Replaces the existing `scrollableDeclarationReachesTheRegistry` test:

- `designedFor:` omitted → the registration records `[]`
- `.navigation` alone → records exactly `.navigation`
- `.scrolling` alone → records exactly `.scrolling`
- `[.navigation, .scrolling]` → records both
- the deprecated `scrollable: true` → records `.scrolling`
- the deprecated `scrollable: false` → records `[]`

**Known deviation, carried from the existing file.** These assert through `MVVMEnvironment.registeredTestTypes`, which is internal and reached via `@testable` — the gate says `@testable` is for coverage, never contract. The registry has **no public read on purpose** (encapsulation: the app declares, the harness resolves, nobody enumerates). The file already carries an "Honest gap" header saying exactly this, and the public contract — that the declaration changes what is presented — is verified hosted, in §3.2. Continuing the precedent rather than opening a public read to make a test easier.

The deprecated-overload tests need a local `@available(*, deprecated)` suppression so the suite itself compiles warning-free.

### 3.2 Hosted — `Tools/UITestingProbe`, iOS and macOS

Fixture views added to `ProbeApp.swift`, ViewModels to the shared file:

- **`ToolbarCardView`** — registered `designedFor: .navigation`. Declares one `ToolbarItem` whose button carries a `uiTestingIdentifier`, a `navigationTitle`, and a transporter recording a stub operation.
- **`UnparentedCardView`** — the same shape, registered with nothing. The negative twin.

*(Both names flagged for arbitration — see Open items.)*

Assertions:

1. The toolbar button **exists** under `.navigation`.
2. It is **hittable**, and tapping it **reaches the stub operation** through the transporter. Present-in-the-tree is not the same as tappable — that distinction is what started the stable-frame-tap thread.
3. `navigationTitle` set by the view under test is **queryable**.
4. The twin's toolbar item is **absent** — this pins the default and documents the symptom for the next reader.
5. `[.navigation, .scrolling]` applies both parents, and scroll-to-visible still reaches a buried field beneath a navigation bar.
6. **The transporter survives a navigation parent.** `registerTestView(_:scrollable:)` shipped in 0.12.4 and needed `348ec08` in 0.12.7 because a zero-sized transporter was culled from the accessibility tree inside a `ScrollView`. A `NavigationStack` is the same class of container. Assertion 2 already exercises the read; this is the named claim so a failure reads as what it is.

### 3.3 The keyboard-up case — added 2026-09-21 from a second field measurement

A toolbar item tapped on a quiescent screen is not the case that breaks. The fixture must also tap one **while a text field below it holds focus**, or it will pass while a consuming app stays red.

**Why.** With the keyboard up and no scroll container to absorb it, SwiftUI shifts the *whole hosted tree* upward rather than scrolling. This is measured and already documented in our own source, `TestHost.swift:196`:

```swift
/// The control lives in its own tiny window above the application's, not in the view tree:
/// when the focused field would be covered and no scroll container absorbs it, keyboard
/// avoidance shifts the application's whole content upward, and no modifier opts a child out
/// of an ancestor's offset — a top-leading overlay was measured riding that shift to y = -48,
/// off screen.
```

A navigation bar sits at the **top** of that tree, so it is the first thing displaced off-screen. Before toolbars entered the picture, the same buttons lived at the bottom of a view's body — the direction displacement moves *toward* — which is why this never surfaced.

Two assertions, and **the difference between them is the finding**:

7. `.navigation` alone, keyboard raised by focusing a field below the bar: is the toolbar item still in the tree, and still tappable?
8. `[.navigation, .scrolling]`, same gesture: the scroll parent should absorb keyboard avoidance instead of displacing the tree, so the bar should stay put.

**ANSWERED 2026-09-21, before the fixture was built.** The reporting session re-ran its suite on a current pin (0.12.7) with both parents declared: 16 pass / 1 fail / 2 unrelated pre-existing skips, up from 7 / 10. The decisive case is the **deepest field on the screen** — previously the most complete failure, with the toolbar button missing from the accessibility tree entirely — now passing, along with every field between it and the top.

So the scroll parent absorbs keyboard avoidance and the bar stays put. **No framework change: the answer is a declaration.** `[.navigation, .scrolling]` is sufficient for a view with both a toolbar and a focusable field, which in production is what such a view essentially always has. Open item 6 closes.

Assertions 7 and 8 still get built — this measurement came from one screen on one device, and the fixture is what makes it a pin rather than an anecdote. But they are now expected to confirm a known answer, not to decide an open one, so **T5a loses its "can grow the arc" status** and its early sequencing is no longer load-bearing.

### 3.4 Transporter read mid-flow — reported 2026-09-21, deterministic

The one remaining failure in that re-run is squarely inside this arc's blast radius, and the fixture must cover it.

Reading the operations transporter **between** interactions — rather than at the end — leaves the hosted tree in a state where a toolbar item is afterwards not findable. Isolated to a single variable by the reporting session: same pin, same test, only the registration differs. With a scroll parent it fails; without one it passes. A near-twin test in the same file, identical but for the mid-flow read, passes under both.

The shape is: tap a toolbar button → `viewModelOperations()` → edit a field → tap another toolbar button, and the second tap reports the tag missing.

9. **Under `[.navigation, .scrolling]`: tap a toolbar item, read the transporter, edit a field, tap a second toolbar item.** All four steps succeed.

Mechanism unknown and deliberately not guessed at in this plan. Their hypothesis is that the transporter's 1×1 fronting (`348ec08`) invites XCUITest to scroll it into view and something settles badly afterwards; a scroll-position change that collapses or re-lays-out the navigation bar would also fit. The fixture's job is to reproduce it in the probe, where it can be instrumented — **not** to ship a theory.

Open question the fixture will also settle: whether this is a framework defect or a test that should not read the transporter mid-flow. If it is the latter, the remedy is a documented constraint plus a teaching failure, not a fix.

The macOS twin asserts 1–6. Assertions 7, 8 and 9 are iOS-only (no software keyboard displacement on macOS). On macOS a `.toolbar` inside `NavigationStack` renders into the window toolbar rather than an in-view bar — `ToolbarTaggingMacTests` already proves tags survive that bridge, and `tap()` dispatches `click()` on macOS since the 2026-08-22 re-measure.

**Behavior, not representation** throughout: no assertion touches an encoded shape, a raw value, or a bit pattern.

---

## 4. Rationale (implementer prose — none of this goes in DocC)

### Why the option set rather than a second `Bool`

Two `Bool`s give four states for one meaning, and the nesting order — navigation outer, scroll inner — can then only live in a doc sentence. When a contract has to be carried by prose because the signature cannot express it, the signature is wrong. The next designed parent after these two would add a third `Bool` and a third ordering sentence, which is extending by patching the signature — the thing OCP names.

The cost is honest: `scrollable:` shipped ratified in 0.12.4 and is referenced in DocC, the api-catalog, the generator skills, and consuming apps. A deprecated peer *is* a parallel door for its lifetime. What makes it tolerable here is that it is a mechanical rename with a compiler-visible warning and a fixed removal point, not a legacy lane with its own semantics.

### The label, re-tested and held (2026-09-21)

`designedFor:` was challenged once more against `hostedIn:` after the plan was drafted, and held.

`hostedIn:` is the better *containment* word — it speaks the subsystem's own vocabulary (`testHost()`, `TestingView`), it is shorter, and it removes the one misread `designedFor:` carries (that `.navigation` names a capability of the view rather than its parent).

It was rejected because it states a **harness instruction** rather than a **design fact**, which is the axis every ruling in this arc turned on. "Host it in a navigation stack" is phrased as a request to the test infrastructure — the framing rejected when the per-app test-configuration flag was rejected. When two people disagree about whether a view gets `.navigation`, `designedFor:` names the tiebreaker (*what does production do?*); `hostedIn:` invites *whatever makes my test pass*. A reader who briefly misparses "designed for navigation" self-corrects at the first DocC example; a reader who believes the parameter is theirs to set per-test damages the contract permanently.

`productionParents:` was raised as a third option that carries both halves — unambiguous containment plus the naming of production as the authority — and was passed over as the longer spelling of a settled decision. Recorded so it is not re-derived.

### Why role nouns instead of the concrete containers

`.navigationStack` / `.scrollView` would name what the harness happens to wrap the view in. That publishes the representation: the day a detail-column view wants `NavigationSplitView`, `.navigationStack` is either a lie or a second case. `.navigation` names the parent *role* and leaves the harness free to choose the container. `Container` was additionally ruled out of the type name as a confusable word shape, and `Environment` because it collides with `MVVMEnvironment` and SwiftUI's own.

`ProductionParents` picks up both load-bearing words from the ratified paragraph it generalizes — "the view's *designed* production environment". `DesignedParents` stutters against `designedFor:`; `ViewParents` says neither whose nor which world.

### Why the diagnostic needed a channel rather than a sentence

The knowledge is split across two processes. The app knows the registration but `TestHostDiagnostic` (`TestHost.swift:314`) fires at presentation, before any query, and has no idea what a test will later look for. The test knows what it looked for but `notFound` (`UITestingElement.swift:651`) is an `XCTFail` in a process that never sees the registry.

Appending a standing sentence to the shared `notFound` was the cheap option and was rejected: it fires at all four call sites (`:534`, `:671`, `:729`, `:1179`), on every platform, for every not-found failure — diluting two currently-accurate hypotheses with a usually-irrelevant third. Planting the facts makes the hypothesis *conditional on a fact*, and composes onto a mechanism that already exists rather than opening a parallel one.

`notFound` becomes an instance method to reach `app` (`UITestingElement.swift:85` holds it privately). When the facts element is absent — a probe test driving a plain `XCUIApplication` with no registration at all — the message says nothing extra. Absence is silence, not a guess.

### Why the generator skill is in this arc

`fosmvvm-ui-tests-generator` teaches a "Navigation Tests" category in three places and names the hosting precondition in none of them. `reference.md:1044` taps a `backButton`, which presumes a push that `presentView()` cannot produce. `SKILL.md:473` and `reference.md:345` pass only if "detailView" is an in-view swap rather than a push — and the skill never draws the distinction, so which one a developer gets is luck.

That is the same defect as the field report, reached from the other side: a parent requirement nobody stated. Fixing the framework and leaving the skill scaffolding untestable tests would ship half the answer. Splitting the category is what makes the rule learnable rather than merely enforced.

### A reported `scrollable:` defect that is not one — recorded so it is not re-chased

The same field measurement reported that adding `scrollable: true` corrupted text entry (a field reading `"Yyuuuu300uyyuuuu30041"` after entering `300`, letters arriving under a number pad) and broke the operations transporter outright (`RunError: Cannot retrieve operations data` on a test that passed without the flag), and suggested this may be a latent defect in `scrollable:` that nobody had hit because nobody had combined it with text entry.

It is not a latent defect. All three symptoms are **already-fixed bugs**, and the reporting pin is one release below the fixes. Both `348ec08` and `af46bf2` are contained in tag **0.12.7**; the report is measured on **0.12.6**.

`CHANGELOG.md` § 0.12.7 names each symptom:

- The garbage text is the occlusion bug — *"a raised software keyboard occludes everything beneath it, and none of XCUITest's signals notice: the covered control exists, reports hittable, and holds a stable frame … and the gesture landed on the keys, silently."* Gestures landing on the keyboard are where the stray characters come from.
- The transporter failure is verbatim the third entry — *"a zero-sized transporter rendered behind an opaque host inside a `ScrollView` was pruned from the accessibility tree entirely, making `viewModelOperations()` throw for exactly the views `registerTestView(_:scrollable:)` serves."*
- Their own hypothesis — coordinate taps computed against a moving frame — is the second entry, `tap()`'s coordinate path re-checking its premise after settling.

**Consequence for this arc:** no `scrollable:` investigation, and no defensive work against a phantom. It also sharpens §3.3: if `scrollable:` behaves correctly on a current pin, then `[.navigation, .scrolling]` may absorb the keyboard displacement on its own, and assertion 8 is the thing that decides it.

### Why the probe goes into CI here

An earlier reading of CI was wrong and worth recording so it is not re-derived: CI **does** run XCUITests — `ci.yml:246`, two scaffolder-generated apps × iOS Simulator and macOS — and those exercise the core harness path end to end (`testHost()`, `registerTestView`, `presentView()`, `uiTestingElement`, `viewModelOperations()`).

What has never been in CI is `Tools/UITestingProbe`, where the *capability* fixtures live: `waitForStableFrame`, `selectPickerItem`, `setText`, `setToggle`, `dismissKeyboard`, and the `scrollable:` / bare pair. Those run only by hand.

Adding this feature's fixtures to a suite nothing automated runs would mean shipping a pin that cannot fail the build. And the job is a copy, not an invention: `ci.yml:246-320` already has a working recipe with signing flags, simulator pre-boot, and the retry policy for cold-simulator flake.

### Why the Mac target fix is a prerequisite rather than an improvement

`Tools/UITestingProbe/project.yml:56` gives `UITestingProbeMacUITests` only `sources: [MacUITests]`. The iOS twin also pulls in `App/ScrollProbeShared.swift` and `UITests/Resources/probe.yml` — the shared ViewModels `presentView()` ships across, and the YAML `ViewModelDisplayTestCase.setUp` requires. Without both, no `presentView()`-based test can exist on macOS at all.

That is why `ScrollRegistrationTests` has no Mac twin today. It was never an oversight in that commit; the target could not host it. Ruling 6 pins macOS at ship, so this is forced.

---

## 5. Decomposition (ordered tasks; PR gate once, at the end)

**T1 — Mac probe target can host `presentView()`.** Add `App/ScrollProbeShared.swift` and the `probe.yml` resource to `UITestingProbeMacUITests` in `project.yml`. Prove it by porting `ScrollRegistrationTests` / `BarePresentationTests` to a Mac twin. Closes a pre-existing macOS gap on its own.

**T2 — Probe joins CI.** New job modelled on `bootstrap_generated_app_tests`: install `xcodegen`, generate, `xcodebuild test` for `-scheme UITestingProbe` (iOS Simulator) and `-scheme UITestingProbeMac`. `set -o pipefail`, `fail-fast: false`, simulator pre-boot, and the same retry policy. Lands **before** the feature so its fixtures are protected from birth, and immediately guards T1.

**T3 — The surface.** `ProductionParents`; `registerTestView(_:designedFor:)`; the deprecated overload; `TestViewRegistration.designedFor`; the harness nesting in `TestHost.swift:157-163`. Headless tests from §3.1.

**T4 — Documentation.** The DocC from §2; the `ViewTesting.md` section; the six symbol links; the api-catalog entry at `FOSMVVM.md:1051` and its reach-for line.

**T5 — Hosted fixture.** `ToolbarCardView` / `UnparentedCardView` and their ViewModels; assertions 1–6 from §3.2 on iOS; the macOS twin (1–6); `Tools/UITestingProbe/README.md` "What it covers" entry.

**T5a — Keyboard-up and mid-flow-read cases.** §3.3 assertions 7–8 and §3.4 assertion 9, iOS only. Sequenced right after the fixture views exist and **before** T6–T8. 7 and 8 now confirm a field-measured answer; **9 is the one that can still grow the arc**, so it is the reason this task stays early.

**T6 — Diagnostic, and the access-level correction.** `TestHostFacts` at `package` access; demote `TestDataTransporter.accessibilityIdentifier` to `package` in the same task (§1.5 — one word, same category, and it belongs with the decision that produced it); plant the resolved parents in `TestingView`; `notFound` becomes an instance method with the conditional hypothesis; a probe assertion that the hypothesis appears when `.navigation` is absent and not when present.

**T7 — Generator skill.** Split the navigation category at `SKILL.md:473`, `reference.md:345`, and `reference.md:1044` into in-view change vs navigation push; teach the `.navigation` requirement on the push side; bump `.claude-plugin/plugin.json` (2.67.0 → 2.68.0).

**T8 — Ship.** CHANGELOG entry under a new 0.17.0 heading; `Sources/FOSMVVMBootstrap/Release.swift` stamped in the same commit (the release-stamp test fails CI when they disagree); `docs/deferrals.md` entries for the certification register and the visionOS hole.

**T9 — Review gate.** Squash to logical commits, then David reviews the finished work before any PR is opened.

---

## Open items

1. **`TestHostFacts`** — working name for the diagnostic channel's `package` namespace. Arbitration.
2. **`ToolbarCardView` / `UnparentedCardView`** — fixture view names. Leading `T` vs `U`, no shared shape, and each says what it is; the existing neighbours are `TallCardView` / `BareCardView` / `OcclusionCardView`. Arbitration.
3. **`ScrollProbeShared.swift`** now carries navigation fixtures too, so the filename under-describes it. Rename to something parent-neutral, or leave it — a rename touches `project.yml` in two targets.
4. **Version** — 0.17.0 assumed (new public type + a deprecation, no removal). Confirm.
5. **execution-model dispatch** — no rule covers framework-internal work on FOSMVVM's own public API. Worth a ruling line in `.claude/docs/execution-model-rulings.md`; not blocking this arc.
6. ~~**Keyboard displacement under `.navigation`**~~ — **CLOSED 2026-09-21** by field measurement on a current pin (§3.3). The scroll parent absorbs it; the bar stays put through the deepest field on the screen. No framework change; `[.navigation, .scrolling]` is the answer. Assertions 7 and 8 still ship, now as confirmation rather than adjudication.

6a. **Transporter read mid-flow** (§3.4) — deterministic, reported, mechanism unknown, reproduced in the probe by assertion 9. Whether the remedy is a fix or a documented constraint is decided by what the probe shows, and that ruling is yours. **This is the item that can now grow the arc.**
7. **`dismissKeyboard()` against formatter-backed numeric fields** — reported as not dismissing ("check for a first responder that refuses to resign"), unchased, on the same below-floor pin. Not in this arc. Triage against a current pin first; if it survives, it is its own thread.
