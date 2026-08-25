---
area: view
generator-skill: fosmvvm-swiftui-view-generator
where:
  - "Sources/**/Views/**/*.swift"
  - "Sources/**/*Views/**/*.swift"
  - "Sources/**/*View.swift"
  - "**/Resources/Views/**/*.leaf"
  - "**/*.leaf"
  - "**/components/**/*.tsx"
  - "**/*.tsx"
  - "**/*.jsx"
---

# View Checks

One area, three surfaces (ruled 2026-08-25): SwiftUI views, Leaf templates, and React components are all projections of the same edge — View ← ViewModel + ratified design — and the rules below are per-edge, with per-surface detections. This file covers View bodies/templates and their interaction with ViewModels and the `@Observable` data store.

## Reviewer Guidance

- **Three surfaces, three generators — cite the right one.** The frontmatter names the SwiftUI generator; for `.leaf` files the positive pattern is `fosmvvm-leaf-view-generator`, and for `.tsx`/`.jsx` it is `fosmvvm-react-view-generator`. Cite the surface's own generator in findings, whatever the dispatch prompt's default says.
- Do NOT recommend removing `@Environment(SomeAppState.self)` from a view to "simplify" by reading through `viewModel.someObservableRef.x`. Production may bind both to the same instance, but tests inject independently — collapsing the split breaks test host injection.
- Do NOT recommend collapsing env/VM read-write splits. The split is required for test host injection (TestConfiguration pattern). View reads come from the VM; mutations go through Operations to the `@Observable` store; tests inject the VM stub's state into the env to mirror this.
- The VM is the single source of truth for what Views display — on every surface. If a value needs to appear, it is a frozen scalar (or stored `Localizable`) on the VM at projection time. Do NOT recommend reaching back into the data store, the request, or the session from a view or template for display data.
- **A SwiftUI view is identified by `: View` conformance, not by its filename.** Views routinely live in files named `*Tile.swift`, `*Card.swift`, `*Row.swift`, `*Section.swift`, `*Strip.swift`, or share a file with the screen that uses them. Enumerate every `: View` conformer in the scoped files and evaluate each one; do not limit the structural checks to types whose name ends in `View`.
- **A plain `View` is legitimate when it renders no ViewModel data.** A leaf that takes only primitives, colors, or geometry (a spinner, a swatch, a divider) is a presentational component and is correctly a plain `View` — do NOT flag it. The structural checks below fire only on views that hold ViewModel-typed state.
- Do NOT recommend satisfying the 1:1 rule by deleting a sub-view and inlining its body into its parent. The fix direction is the other way: the sub-view gets its own ViewModel, projected as a child of the parent's.
- **A template-side `fetch('/api/…')` is `server-calls-use-the-request-door`'s finding** (`cross-cutting`), reported at **warning** under that check's name per its TBD ruling (2026-08-25) — JavaScript in a Leaf template is client code, and the WebApp's JS→route bridge is the sanctioned path. Note it when you see it; this area carries the eyes, that check carries the name.
- **Leaf renders `Localizable` values natively** (`LeafDataRepresentable`, FOSUtilities 0.4.0+): `#(card.createdAt)` on a `LocalizableDate` renders the localized string. A template that re-formats instead of rendering is `views-render-they-dont-shape`'s business below.
- **Leaf drift never errors — it renders silently empty.** LeafKit resolves an unknown variable to nothing and emits an unknown tag as literal text, skipped. A template reading properties its VM does not have, or using a tag that is not registered (`#set` does not exist in LeafKit's built-ins), produces a page with blank holes and no log line. The runtime will not catch what these checks catch — say so in findings, because "it renders" is not evidence.
- **Follow `<script src>` into the project's own JS.** Template-side fetches routinely live one directory over, in `Public/js/*.js` referenced from the templates — a detection keyed to inline `<script>` bodies reports a false clean. When noting fetches under `server-calls-use-the-request-door`, walk the src references the templates load.
- **The `data-*` shadow-render channel is an unanticipated shape** — a template exporting essentially its whole VM as `data-*` attributes so client JS can re-render it is a second render path no check owns yet. Note it for the owner when seen; do not improvise a rule.

## Check: view-conforms-to-viewmodelview

**Severity:** blocker · **Surface:** SwiftUI
**What:** A SwiftUI view that renders ViewModel data conforms to `ViewModelView`; it does not take the ViewModel as a plain stored property. (Leaf and React have no conformance to check — their structural twin is `viewmodel-view-one-to-one`'s alignment rule.)
**Anti-pattern:** `struct BerthTile: View { let berth: BerthViewModel; var body: some View { … } }` — a view holding ViewModel state while conforming only to `View`.
**Detection:** For every `: View` conformer in scope, list its stored properties. If any property's type is a `@ViewModel`-declared type — or a collection of one — **and the view body reads it for display**, the view must appear in the `ViewModelView` conformance list. Flag each view that renders ViewModel state without conforming. Report the ViewModel type in the finding so the pairing gap is visible.

Two shapes are NOT hits. A view holding no ViewModel-typed property is a presentational leaf. A view holding ViewModels it never renders — passing a `[SomeViewModel]` straight through as a correlation or lookup argument, and drawing only `ViewModelView` children — is plumbing, not a projection; check the body before flagging.

## Check: viewmodel-view-one-to-one

**Severity:** blocker · **Surface:** all three
**What:** Within each surface, each ViewModel is rendered by exactly one view, and each view renders exactly one ViewModel. **The rule is per-surface:** a ViewModel legitimately has one SwiftUI view *and* one Leaf template *and* one React component — the same projection rendered to three mediums is the architecture working, not sharing.
**Anti-pattern:** One `XViewModel` typed into three SwiftUI views; a screen's `ScreenViewModel` handed to seven sub-views; a `@ViewModel` type with no dedicated view, drawn instead by a parent's private `func row(_ item: ItemViewModel) -> some View` helper; two Leaf templates rendering the same ViewModel's fields; a Leaf template weaving fields from two unrelated ViewModels.
**Detection:** Per surface, build two maps — ViewModel type → views/templates/components that render it, and view → ViewModel it renders. For SwiftUI, hold by type; for Leaf, by the alignment convention the generator prescribes (`{Name}View.leaf` renders `{Name}ViewModel`, and the fields the template reads resolve to that VM's properties); for React, by the `viewModelComponent()` wrapper's bound type. Then flag:

(a) Any ViewModel rendered by more than one view *on the same surface*, naming every holder. A sub-view needing part of a parent's data is a missing child ViewModel, not a shared one.

Name the testing cost when you report it (SwiftUI): the test-view registry holds one entry per ViewModel, so exactly one view in a sharing group can be registered. Every other view in that group is **permanently undriveable in isolation** — not an oversight some later commit can fix, but a consequence of the sharing. That is usually the argument that lands.

(b) Any `@ViewModel`-declared type with **no dedicated view on a surface that renders its siblings**. On SwiftUI the usual shape is an inline helper on the parent view — the same violation wearing a function signature. On Leaf it is a parent template inlining the markup a fragment should own. Say where it is actually drawn, so the finding is not read as "this type is unused". (A VM rendered on only one surface is normal — flag a missing view only where the surface plainly renders that VM's siblings.)

**The sanctioned Leaf page/fragment shape** (the generator's own): the page layout `#extend`s the *one* fragment that owns the markup. Both drifts from it are hits under (a): a layout/fragment *pair* duplicating the same VM's markup (they will diverge — copy drift, then behavior drift), and one file serving both roles through an unconditional `#extend` (the "fragment" response ships a full page shell). When a codebase exhibits both, say which shape is sanctioned rather than letting the reviewer pick between two failures.

**Shared app-shell/base layouts are not content templates.** Their standing under the 1:1 and reads-vm-only rules awaits an owner ruling (candidate on file, 2026-08-25) — note their multi-page service and their context reads; do not grade them until the ruling lands.

(c) Any view whose name does not share a stem with its ViewModel (`LocalDocView` against `LocalDockViewModel`; `dock_card.leaf` against `DockCardViewModel`) — a near-miss name hides a pairing from every reader and every search. NAMES.md §3b states the rule.

Report each view at most once. When a view already appears under (a), fold its (c) mismatch into that finding rather than emitting a second one.

## Check: views-render-they-dont-shape

**Severity:** warning · **Surface:** all three
**What:** Views render data; they never compose, format, or reorder it. Concatenating name parts hardcodes an ordering some locales reverse; a hardcoded date format overrides the locale the VM already carries; a separator baked into markup breaks RTL. The shaping lives in the ViewModel — `LocalizableCompoundValue` for locale-aware composition, `LocalizableDate`/`LocalizableInt` for formatting — and the view renders the one finished value.
**Anti-pattern:**
```swift
// SwiftUI
Text(viewModel.firstName) + Text(" ") + Text(viewModel.lastName)
Text("\(viewModel.count) items")
```
```html
<!-- Leaf -->
#(user.firstName) #(user.lastName)
#date(content.createdAt, "MMM d, yyyy")
```
```tsx
// React
<span>{user.firstName} {user.lastName}</span>
<span>{format(content.createdAt, 'MMM d, yyyy')}</span>
```
**Detection:** The **primary signal is the VM's own field names**, not syntax: properties ending `Prefix`, `Suffix`, `Part1/2/3`, or a bare-count-beside-a-noun pair (`messageCount` + `messagesLabel`) are the projection confessing that a phrase was split for the view to reassemble. Same-text-node adjacency is the secondary signal — label-beside-value in separate block elements is layout, not shaping, and flagging it buries the report. Then the per-surface shapes:

- **SwiftUI:** `Text` concatenation (`+`), string interpolation composing display copy (`"\(a) \(b)"`, `"\(count) items"`), and `.formatted(…)`/`DateFormatter` applied to VM values in a body. Interpolating a *single* already-localized value into a style modifier chain is not a hit.
- **Leaf:** adjacent `#(…)` reads forming one phrase in one text node; hardcoded English glued around VM fields (`Are you sure you want to delete #(x)?`, template-side pluralization `project(s)`); template arithmetic (`#(index + 1)`, page math); comma-joining loops (`#for … #if(!isLast):, #endif`); raw enum encodings rendered as user-visible text (the VM owes a localized display twin beside the raw value); and `#date(…)` over a `Localizable` value — which does not merely mis-shape, it *cannot work*: the tag expects a numeric timestamp and the Localizable renders as a string. The finished value comes through `#(…)` alone.
- **React:** adjacent JSX interpolations forming one phrase; date/number formatting libraries applied to bound VM values in the component.

**Not hits:** identifier and attribute-value interpolation — `class="state-#(x)"`, `id="row-#(id)"`, CSS variable names — builds identifiers, not phrases. Structural composition — a template embedding a child fragment, a view laying out child views — is not shaping; the rule is about *data*, not structure.

**When the VM pre-split the phrase** (`titlePart1/2/3` so one word can render styled), the template merely places the parts: report the symptom here, and route the fix to the `viewmodel` area — the remedy is `LocalizableSubstitutions`/`LocalizableCompoundValue` on the VM, not template surgery. The remedy otherwise is always the same and belongs in the finding: a stored, localized property on the VM (`fullName`, `createdDisplay`, `itemCountDisplay`), projected once.

## Check: preview-uses-previewhost

**Severity:** warning · **Surface:** SwiftUI
**What:** `#Preview` blocks host the view through `previewHost(…)`.
**Anti-pattern:** `#Preview { SomeView(viewModel: .stub()) }` — the view is constructed directly, so it renders without the environment its ViewModel resolves against.
**Detection:** For each `#Preview` block in scope, check whether the view under preview is produced by a `previewHost(` call. Flag blocks that construct the view directly. A preview built without the host lacks the localization and MVVM environment the view needs, so localized text renders as raw keys or fails — and the preview stops being evidence that the view works.

**Scope this to previews of `ViewModelView` conformers.** `previewHost` is not reachable from a plain `View`, so a preview of one cannot satisfy this check and is already reported by `view-conforms-to-viewmodelview`. Flagging it here restates a blocker as a warning and buries the previews that can actually be fixed today.

## Check: view-reads-vm-only

**Severity:** blocker · **Surface:** all three
**What:** Views read display data from the VM, never from anywhere else the runtime happens to offer. On SwiftUI that means not reading `@Environment`-shadowed data-store types when the VM exposes the equivalent; on Leaf, the template's entire world is the encoded ViewModel — request data, session values, or a second context object woven around the VM are shaping outside the projection; on React, the component reads its bound VM props only.
**Anti-pattern:** A SwiftUI View reads `programmingSettings.amplitudeValue` from `@Environment(ProgrammingSettings.self)` for display when the VM already exposes `amplitudeValue` as a frozen scalar. A Leaf route handler stuffing extra non-VM context into the render call for the template to read.
**Detection:** SwiftUI: for each View, find `@Environment` declarations of `@Observable` types; for each property read off those env values in the body, check whether the VM exposes the same property; flag overlapping reads. React: props reaching the component outside the `.bind()`-provided ViewModel. Leaf, in both directions:

- **Render call sites.** A dictionary render (`["card": vm]` impersonating a loop variable) is a hit. A wrapper struct: a bare single-field envelope (`{content: VM}`) is *tolerated pending an owner ruling* (candidate on file, 2026-08-25); an envelope carrying **additional data-bearing members** — an app-shell context, a sidebar, anything assembled route-side instead of projected as a child of the page VM — is the finding, because that data bypassed the projection entirely. A registered tag injecting non-VM data into templates (a `#backendURL()`-style Application read) is the same bypass wearing tag syntax — note it.
- **Template reads.** Every read must resolve to a property of the rendered VM (through the envelope's field if one exists) — a **stored** property: a read that lands on a *computed* property is not resolved, because the Swift source shows a property the encoded JSON does not carry (`computed-properties-dont-serialize` in `viewmodel.md` owns the declaration side). Unresolvable reads are the highest-value findings on this surface *because the runtime hides them*: LeafKit renders them silently empty — a whole landing page can read a VM that no longer has its properties and ship blank with zero errors. Also verify every tag used is a LeafKit built-in or registered in `configure` — an unregistered tag is emitted as literal text and skipped, so a `#set(…)` line assigns nothing and everything downstream of it reads empty.
- **Dead templates** — no render site and no live `#extend` parent — are dead code with unresolvable reads frozen inside; report them once as cleanup, not read-by-read.

## Check: view-no-env-mutation

**Severity:** blocker · **Surface:** SwiftUI (React twin noted)
**What:** View bodies do not mutate `@Observable` state directly. Mutations go through Operations.
**Anti-pattern:** `programmingSettings.isEnabled = true` written inline in a View body or button action closure.
**Detection:** Inside View bodies and the closures they construct, find assignments where the LHS resolves to a property of an `@Observable` env value. Flag any such assignment. (Operations dispatched from button actions are fine — they call methods on a `*ViewModelOperations` conformer, which mutates internally.) The React twin: a component mutating shared app state directly instead of dispatching through the ops/intents layer the generator prescribes — flag it under this name with the surface noted.

## Check: view-no-read-through-vm-ref

**Severity:** warning · **Surface:** SwiftUI
**What:** Views never read display data through an `@Observable` reference reached via the VM — and the VM holding such a reference is itself a violation. Forward-projection rule 4 (architecture-patterns.md → The Four Rules of Forward Projection): the VM holds scalars only; `@Observable` references live on the View via `@Environment`, never on the VM, not even as a pass-through. A chained read through the VM therefore carries two defects — the stored reference, and the display read that bypasses projection.
**Anti-pattern:** `viewModel.userSettings.notificationsEnabled` read in a View body for display — the VM stores `userSettings` (an `@Observable`), and the View reads display state through it.
**Detection:** In View bodies, find chained reads through VM properties whose type is `@Observable`. Flag the read, and name the stored reference as the root cause: the remedy is a frozen scalar on the VM at projection time, with the reference moved to the View's own `@Environment` for ops dispatch. Do NOT accept "the VM keeps the reference for ops dispatch" as a mitigation — ops receive storage from the View's `@Environment` via the mutation closure, never through the VM (ruled 2026-08-25). The stored reference itself is `vm-holds-scalars-only`'s blocker (`viewmodel` area); this check adds the read-site evidence.

## Check: one-top-level-appstate

**Severity:** warning · **Surface:** SwiftUI
**What:** The environment injection surface stays small — one top-level Application State `@Observable final class` injected once at the root beside `MVVMEnvironment`, with values reaching ViewModels through the projection edge (`.bind(appState: .init(...))` scalar extraction), never through `@Environment` reads scattered down the hierarchy (architecture-patterns.md → One Top-Level App State, Not an Environment of Entries). Every custom `@Entry`/`EnvironmentKey` and every additional environment-vended `@Observable` type is an injection obligation on every preview, test host, and scene — forget one `.environment(...)` and an `@Environment(X.self)` read crashes, while a custom-keyed value silently defaults and renders wrong. The single App State is also the persistence seam the scattered form destroys: one storable class resumes the app where the user left off.
**Anti-pattern:** `extension EnvironmentValues { @Entry var currentProject: Project? … @Entry var filterState: FilterState … }` with views deep in the hierarchy each reading `@Environment(\.currentProject)`; or three separate project-authored `@Observable` classes each individually injected and individually required by previews.
**Detection:** Grade the **surface**, not each use. Inventory three things across the app target and view layer:

1. **`@Entry` declarations** in `EnvironmentValues`/`FocusedValues` extensions, and legacy `EnvironmentKey` conformances.
2. **Distinct project-authored `@Observable` types read via `@Environment(X.self)`** across the view hierarchy.
3. **The preview/test symptom** — previews or test hosts chaining multiple `.environment(...)` calls to keep views from crashing, or `#Preview` blocks that omit one and rely on nobody opening them. This is corroboration, and it names the cost in the finding.

One top-level App State plus the framework's types is the conformant shape — and the App State is resolved by **role, not name**: the one project-authored `@Observable` injected at the root *is* it, whatever the project calls it (a `SessionStore` is as much an App State as an `AppState`). For each entry or type beyond it, ask the truth statement's own question — **why can't this live on the App State?** — and flag it when the answer is absent. App-state-shaped values (selection, filters, navigation, session) carried in entries are the core hit. **The finding always states both the consequences and the alternative** (ruled 2026-08-25): the consequences — every preview and test host must inject this entry or crash (`@Environment(X.self)`) / silently render the default (custom keys) — and the suggested remedy — fold the values into the App State class, project scalars through `.bind(appState: .init(...))`, noting the persistence/resume payoff a single storable class brings.

**Not hits:** SwiftUI's built-in environment values (`\.dismiss`, `\.colorScheme`, `\.locale` — always present, no injection obligation); the framework's own environment surface (`MVVMEnvironment`, a form's `Validations`, and FOSMVVM's internal entries — a consumer repo cannot police the framework's internals); an `@Entry` a reusable component vends as **styling configuration** consumed by that component alone — the `buttonStyle`-shaped idiom. A *second* project `@Observable` in the environment is not automatically a finding either — a genuinely subtree-scoped store can answer the question; an unanswered one cannot. Display data read from the environment is already `view-reads-vm-only`'s blocker — this check grades the injection surface those reads ride on, so one scattered-state defect does not get reported twice at two tiers without saying so.

## Check: views-dont-mint-prose

**Severity:** warning · **Surface:** SwiftUI (React twin noted)
**What:** User-visible prose is never a string literal in a View body — whether displayed or handed to an operation (ruled 2026-08-25, the narrowed form). Prose arrives from the user or from the ViewModel, localized; even a deliberate default name (an "untitled folder") is a product decision *sited* on the VM as a localized value, never minted at the call site. This extends the generator's standing Hardcoding Text rule from display positions to operation arguments — where the minted literal persists and renders back to every locale with no YAML owning it.
**Anti-pattern:** `try await operations.createCard(title: "New Card", mvvmEnv: mvvmEnv)` — an English literal in a view body, persisted by the write path, displayed forever after.
**Detection:** In View bodies and the closures they construct, find string literals that are user-visible prose — displayed directly, or passed into an operation/persistence path. **Three carve-outs, all ruled:** user-authored content the view conduits (field bindings, drawings, picks — the user is the author); typed values that localize at render (`.large`, an enum case); and machine text (identifiers, `uiTestingIdentifier` tags, query syntax, analytics keys, URL fragments — the established machine-text carve-out). `#Preview` blocks are development surface, not shipped UI — exempt. Presentation joiners and formatting are `views-render-they-dont-shape`'s business; this check fires on prose *origination*.
