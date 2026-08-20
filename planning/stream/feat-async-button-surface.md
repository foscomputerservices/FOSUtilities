# Async Button Surface — Implementation Plan

**Status:** UNRATIFIED — awaiting David's review of this plan (the *design* it implements was ratified decision-by-decision on 2026-08-20; this document only adds the implementation shape).

**Scope:** `AsyncButtonActivity` engine + 4 hand-written ViewBuilder `Button` primitives, 12 generated Localizable-titled async `Button` inits (sweep second stage), `LocalizableError` protocol, `View.alert(error:)` modifier.

**Deferred by ratified decision (not silently):** `.task(error:)` twin (queued, own arc). Cancellation-handle parameter (Option C, shelved; additive later). Server-side long-op cancellation is guidance (operation-as-resource DocC), not API.

---

## 1. Public surface — every symbol justified

All new API lives in `FOSMVVM`, `#if canImport(SwiftUI)` where SwiftUI is involved. No other module changes.

### `AsyncButtonActivity` (struct) — `Sources/FOSMVVM/SwiftUI Support/AsyncButtonActivity.swift`

The caller-owned in-flight state for one async button (or one shared "operation slot" across several).

- `public init()` — the *only* constructible state (idle). Caller need: declare `@State`. No other public construction; a forgeable `running` state would break every invariant.
- `public var phase: Phase { get }` — read-only. Caller need: drive `.disabled(...)`, progress overlays, and phase-aware labels. No setter — phases advance only through the engine.
- `public enum Phase { case idle, running, cancelling }` — the phase taxonomy is contract (callers render from it); it carries no associated values, so it publishes no representation.
- `public var isRunning: Bool { get }` — convenience over `phase`, **ratified keep**. Justification against the two-ways-to-do-one-thing rule: `phase != .idle` vs `== .running` reads ambiguously at call sites (`cancelling` is also "busy"); `isRunning` is defined as `phase != .idle` — the "should this control be interactable" question, which is the only question callers ask of it.
- `public mutating func cancel()` — caller need: cancel affordances beyond the button's own toggle face (✕ on an overlay, `.onDisappear`). No-op unless `phase == .running`.
- **Sealed:** the `Task` handle and the refractory timestamp. No getters, ever. Not `Codable` — this is view-local interaction state; it is never serialized, and conforming it would publish a representation with no consumer.

### `Button` async inits — 4 hand-written primitives (same file), 12 generated (`Generated/Button+AsyncAction.swift`)

Refuse-mode primitives (zero-arg label):

- `init(role:activity:error:action:label:)` and `init(activity:error:action:label:)` — `activity: Binding<AsyncButtonActivity>? = nil`, `error: Binding<Error?>` required, `action: @escaping @Sendable () async throws -> Void`.

Toggle-mode primitives (phase-taking label — providing the second face's presentation is what enables cancellation):

- `init(role:activity:error:action:label:)` / `init(activity:error:action:label:)` where `label: (AsyncButtonActivity.Phase) -> Label` and `activity: Binding<AsyncButtonActivity>` (required — cancel needs caller-owned storage).

Generated Localizable-titled forms: the 6 existing `Button+Localizable` decorations × {refuse, toggle}. Toggle forms add the cancel face **face-grouped**: do-face args, then `cancelTitle:`/`cancelDefaultValue:` (+ `cancelSystemImage:`/`cancelImage:` on decorated forms, `nil` default = image holds constant). Apple/our ingredient order is otherwise preserved verbatim — a sync call site becomes async by insertion only.

Existential note (governance flag, answered): `error: Binding<Error?>` is ratified — `any Error` is the language's error currency at a UI boundary; typed throws was ruled out (Apple's standing guidance: untyped for API surfaces whose errors are rendered, not exhaustively handled).

**No `String`/`LocalizedStringKey` titled async forms, ever** — they would be a first-class door around YAML localization on a brand-new surface (hole threat model: the prior-art string door stays sealed).

### `LocalizableError` (protocol) — `Sources/FOSMVVM/Protocols/LocalizableError.swift`

```swift
public protocol LocalizableError: Error {
    var localizableMessage: any Localizable { get }
}
```

*Amended in implementation review (2026-08-20):* originally ratified as
`var localizableString: LocalizableString`; David widened it — a `LocalizableString` cannot
express a message carrying the error's own values (`LocalizableSubstitutions` can — the
framework's canonical `QuotaError` example), nothing downstream needs the concrete type,
and the property was renamed so it no longer implies one. The existential is consumed
behind `any Error` and resolved to a `String` immediately (legitimate-use column).

*Second amendment, same review:* the canonical conformer's message is a **stored** property
forwarded by the witness, never a computed one — the YAML lives on the server, and only
stored properties ride `ErrorMiddleware`'s localizing encode; a computed property re-mints
an unresolved reference on the client, where the YAML is not. Computed/unresolved remains
valid only for client-created errors in apps hosting their own localization YAML. The DocC,
catalog entry, and tests all model the wire flow as primary.

*Third amendment, same review — full ViewModel alignment (supersedes the second's conformer
shape):* the protocol became `LocalizableError: Error, RetrievablePropertyNames` with the
requirement renamed **`localizedMessage`** (-ed: by the time anyone reads it, localization
happened). Conformers compose exactly like ViewModels — `@LocalizedString`/`@LocalizedSubs`
message properties, plumbing synthesized by the new **`@LocalizableError` macro** (the
family's third member, cloned from `@FieldValidationModel`). YAML keys derive from
type+property; the manual `localizationKey` ceremony and the stored-`LocalizableSubstitutions`
hand-shape are gone from the docs (only the wrapper composition is taught). An error type
belongs to exactly ONE localization domain (David's ruling — same type never straddles
server/client YAML).

*Fourth amendment — the client-domain unification (designed and shipped in the same review):*
`@LocalizableError(options: [.clientHosted])` (mirroring `@ViewModel`'s options) emits the
`ClientHostedLocalizableError` marker. Client-created errors are resolved **at presentation**
— the error's `bind()`-moment — by `localized(mvvmEnv:locale:) -> Self?`, which runs the same
localizing round-trip `ClientHostedViewModelFactory` runs for a ViewModel (nil ⇒ present the
debug description; a manufactured default error was explicitly rejected). The throwing core is
`localized(locale:localizationStore:)`. The alert was rewritten as pure Localizable **twin
composition** (generated alert/Text/Button twins; the `%{error}` substitution receives the
message as a typed `Localizable`, never a String) — the entire `ErrorAlertResolver` String
ladder was deleted, along with the store rung and the hand-composed conformer shape. Traced
gotcha recorded for posterity: pre-round-trip wrapper reads do NOT throw — `@LocalizedString`
seeds `.empty` ("" ) and `@LocalizedSubs` seeds a constant stub, both reporting `.localized` —
so consumers must localize-then-read, never check-then-read; `localizationUnbound` fires only
for bare `.localized` refs.

Caller need: opt an error type (canonically a `ServerRequestError` conformer) into user-presentable, YAML-localized messaging. Opt-in by ratified decision — `ServerRequestError` does *not* refine it. Name ratified against the Foundation `LocalizedError` adjacency: *-able* = localization pending (the framework's value-until-resolved model), *-ed* = completed fact.

### `View.alert(error:title:message:dismissButtonLabel:)` — `Sources/FOSMVVM/SwiftUI Support/ErrorAlert.swift` (filename ratified)

```swift
func alert(
    error: Binding<Error?>,
    title: some Localizable,
    message: LocalizableString? = nil,   // default: constant "%{error}" — locale-neutral pure substitution
    dismissButtonLabel: some Localizable
) -> some View
```

- Presents when `error != nil`; dismissal (button or system) writes `nil`. One mechanism — the consumer sample's `dismissErrorAction` environment does not come forward.
- `title:`/`dismissButtonLabel:` required (ratified: no framework default copy; the caller owns defaulting) and therefore `some Localizable` — opaque, no existential box.
- `message:` is the **bind target**: a `LocalizableString` whose `%{error}` slot the modifier fills via `.bind(substitutions:)`. The concrete type enforces bindability.
- Resolution is presentation-time, synchronous, inside the modifier: `MVVMEnvironment.clientLocalizationStore` (sync, cached — `MVVMEnvironment.swift:240`) + `Locale.localize(_:localizationStore:)`. No JSON round-trip, no store-caching layer — both consumer-sample hacks are obsolete against current FOSMVVM.
- Fallback ladder (contract): `LocalizableError` → localized message; anything else → `"\(error)"` with a logged notice. The `as? LocalizableError` runtime cast inside the modifier is an existential downcast — raised here per the gate: it is the only possible mechanism (errors arrive as `any Error` by ratified decision), it is internal, and the typed path is one conformance away for any adopter.

### Encapsulation review (separate axis, per repo discipline)

No raw getters anywhere: the task handle, refractory timestamp, and the engine's internals are unreachable. The refractory *duration* is not part of the contract — DocC says "a tap arriving immediately after the button changes faces is ignored", never the number (internal `//` + internal test pin it). `AsyncButtonActivity`'s phase taxonomy is deliberately public contract; everything else about its insides is not.

---

## 2. Customer-facing DocC — drafted first

Representative drafts; the generator stamps per-overload variants of the init DocC in the existing sweep style. Contract only — rationale lives in §4.

### `AsyncButtonActivity`

```swift
/// The in-flight state of an async button — declare one as `@State` and hand it to the button
///
/// ```swift
/// @State private var activity = AsyncButtonActivity()
/// @State private var error: Error?
///
/// var body: some View {
///     Button(viewModel.uploadTitle, cancelTitle: viewModel.cancelTitle,
///            activity: $activity, error: $error) {
///         try await viewModel.operations.upload()
///     }
///     .disabled(activity.phase == .cancelling)
/// }
/// ```
///
/// While the button's work runs, `phase` is `.running`; a cancel-capable button that has been
/// asked to stop is `.cancelling` until its work unwinds. Use `phase` (or `isRunning`) to drive
/// `disabled(_:)`, progress indicators, and phase-aware labels.
///
/// Share one activity between several buttons to make them mutually exclusive — while any of
/// them is running, the others refuse to start, and (for cancel-capable buttons) any of their
/// faces can stop the running operation.
///
/// Call ``cancel()`` to stop the running operation from outside the button — a toolbar ✕,
/// or `.onDisappear { activity.cancel() }`.
```

### Refuse-mode primitive (representative)

```swift
/// Async form of SwiftUI's `Button.init(action:label:)` — runs a throwing async action and
/// routes its error to a binding
///
/// ```swift
/// @State private var error: Error?
///
/// Button(error: $error) {
///     try await viewModel.operations.save()
/// } label: {
///     Text(viewModel.saveTitle)
/// }
/// .alert(error: $error,
///        title: viewModel.errorTitle,
///        dismissButtonLabel: viewModel.dismissTitle)
/// ```
///
/// Tapping starts the action; a thrown error lands in `error`. Starting a new invocation
/// clears `error` first — the binding always holds the outcome of the most recent invocation.
///
/// Pass `activity:` to prevent re-entry: while a run is in flight, further taps are ignored,
/// and `activity` reports the running state for `disabled(_:)` or a progress indicator.
/// Without `activity:`, every tap starts a new concurrent invocation.
///
/// The action runs in a task that is not cancelled by the view disappearing; it runs to
/// completion. For user-cancellable work, use the `cancelTitle:` forms. For long-running
/// *server* work, model the operation as a server-tracked resource and cancel it with another
/// request — client-side cancellation only abandons the response.
```

### Toggle-mode titled form (representative)

```swift
/// A two-faced async button: tap to start the operation, tap again to cancel it
///
/// ```swift
/// @State private var activity = AsyncButtonActivity()
/// @State private var error: Error?
///
/// Button(viewModel.uploadTitle, cancelTitle: viewModel.cancelTitle,
///        systemImage: "arrow.up", cancelSystemImage: "xmark",
///        activity: $activity, error: $error) {
///     try await viewModel.operations.upload()
/// }
/// ```
///
/// While idle the button shows the title and starts the action when tapped. While running it
/// shows `cancelTitle` and a tap cancels the operation; the button then refuses taps until the
/// work unwinds (`activity.phase == .cancelling`). A cancelled invocation writes nothing to
/// `error`. A tap arriving in the instant after the button changes faces is ignored rather
/// than misread against the old face.
///
/// > Important: Cancellation is cooperative. Your action must run cancellation-aware work
/// > (any `URLSession`-backed `ServerRequest` is) for the cancel face to take effect.
```

### `LocalizableError`

```swift
/// Give an error a localized, user-presentable message — conform, and ``SwiftUICore/View/alert(error:title:message:dismissButtonLabel:)`` presents it in the user's language
///
/// ```swift
/// public enum DocumentError: ServerRequestError, LocalizableError {
///     case quotaExceeded
///
///     public var localizableString: LocalizableString {
///         .localized(for: Self.self, propertyName: localizationKey)
///     }
///
///     private var localizationKey: String {
///         switch self {
///         case .quotaExceeded: "quotaExceeded"
///         }
///     }
/// }
/// ```
///
/// ```yaml
/// en:
///   DocumentError:
///     quotaExceeded: "Your document quota has been reached"
/// ```
///
/// Errors that do not conform are presented with their debug description — conforming is what
/// turns an error from developer output into user-facing copy.
```

### `View.alert(error:)`

```swift
/// Presents a localized alert whenever an error lands in the binding
///
/// ```swift
/// @State private var error: Error?
///
/// var body: some View {
///     DocumentForm(viewModel: viewModel, error: $error)
///         .alert(error: $error,
///                title: viewModel.errorTitle,
///                message: viewModel.errorMessage,
///                dismissButtonLabel: viewModel.dismissTitle)
/// }
/// ```
///
/// ```yaml
/// en:
///   DocumentViewModel:
///     errorTitle: "An Error Occurred"
///     errorMessage: "The operation failed: %{error}"
///     dismissTitle: "OK"
/// ```
///
/// The alert shows while `error` is non-`nil`; dismissing it clears the binding. If `message`
/// contains an `%{error}` substitution point, the presented error's localized message fills it
/// — errors conforming to ``LocalizableError`` localize through your YAML; others fall back to
/// their debug description. Omitting `message` presents the error message alone.
///
/// Feed one binding from every async button on the screen — this modifier is the single
/// presentation point the buttons' `error:` parameter is designed to pair with.
```

---

## 3. Contract tests

Test targets: `Tests/FOSMVVMTests/` (Swift Testing) + existing TestYAML fixtures; UI-interaction behaviors through the FOSTestingUI harness where a real tap is the only honest trigger.

**`AsyncButtonActivity` (public path only):** fresh value is `.idle`; `cancel()` on idle is a no-op; `isRunning` derivation (if kept).

**Engine semantics** — each ratified behavior gets a test, exercised through the hand-written primitives hosted in the existing test-host infrastructure (public construction, real bindings; no `@testable` for contract):

- clear-on-launch: deposited error is `nil`ed when a new invocation starts
- refuse mode, no activity: two taps → two invocations (fire-and-forget is the documented default)
- refuse mode with activity: tap-while-running has no observable effect (no error write, no phase write, no second invocation)
- toggle mode: tap-while-running cancels; the closure observes cooperative cancellation
- `cancelling` refuses taps until unwind; phase returns to `.idle` after unwind
- cancelled invocation writes nothing to `error`
- activity resets to `.idle` on error outcomes as well as success
- refractory: a tap immediately after running→idle is discarded (the *duration* is pinned by an internal test, not the public one)
- shared activity: two buttons, one binding — second button refuses while first runs

**`LocalizableError` + alert resolution:** conforming error's message localizes through the store (multi-locale, via existing `LocalizableTestCase` patterns + a TestYAML fixture); non-conforming error falls back to `"\(error)"`; `%{error}` substitution fills; slot-free message passes through unchanged. Resolution behaviors test through the smallest public-behavior seam practical; SwiftUI's alert *presentation* itself is Apple's contract, not ours, and is not UI-tested here.

**Generated surface:** compile-surface coverage of all 12 titled forms (call each overload) + one behavioral spot-check that a titled form forwards to the primitive (title swaps by phase). Matches how `Button+Localizable` output is covered today.

---

## 4. Rationale (implementer prose — none of this goes in DocC)

**Why the state lives in a caller binding:** an init owns no storage across renders; captured boxes die on re-render — and the engine's own phase flip *forces* a re-render. The binding through caller `@State` is the only deterministic home. This same re-render powers the title swap for free: each render re-reads `phase` and picks the face.

**Why `@Sendable`, not `@MainActor`:** the canonical closure is `try await viewModel.operations.x()` — all captures `Sendable` by protocol contract (`ViewModelOperations: Sendable`). Post-success view-poking is the FOSMVVM anti-pattern (state flows by rebind/live invalidation); `@Sendable` makes the architectural pattern frictionless and puts `await MainActor.run` ceremony exactly on deviations. Engine detail: the tap handler does its binding writes on the MainActor before/after awaiting the closure; the `Task { @MainActor in ... }` wrapper owns sequencing.

**Why toggle mode is enabled by presentation args:** a button that cancels while still reading "Save" is UX poison; requiring `cancelTitle:` (or the phase-taking label) makes the poisonous state unrepresentable. Same principle both families: *cancellation is enabled exactly when the call site provides for its presentation.*

**Why the refractory window:** completion racing an incoming cancel-tap is a human-perception race (the finger committed before the face flipped); no lock fixes it. Discarding taps in a brief window after the flip absorbs it framework-side — the pain-class this framework exists to absorb once. The `cancelling` phase closes the other direction (double-tap on Cancel landing on a re-flipped face).

**Rejected alternatives (do not resurrect):** wrapper `AsyncButton` View / runner type (David scoped to the init surface); typed throws (Apple guidance: untyped default for rendered errors); `Binding<Bool>` guard (degenerate case of `AsyncButtonActivity`, two spellings of one meaning); `ServerRequestError` refining `LocalizableError` (breaking change; opt-in ratified); framework-shipped or well-known-key default alert copy (David: caller owns defaulting); overloading the guard binding as a cancel signal (bindings aren't observable; one Bool, two meanings); deposit-time error localization (couples alert to producers; store access is sync now, presentation-time is simpler and producer-agnostic).

**Gotchas for the implementer:**

- `Task {}` from the tap handler inherits MainActor; the awaited `@Sendable` closure hops off. Guard/error writes stay main-side.
- Overload resolution: sync closures convert to async-throws closure types; the required `error:` label is what keeps every async call site unambiguous against the sync family. Don't weaken it to a defaulted param.
- The sweep's second stage takes the *Localizable output set* as input (twin relationship stays structural); mirror the header/`swiftformat:disable` conventions of the existing generated files.
- No `Date.now` in the engine's refractory logic without thought to testability — inject the clock internally (an internal seam, not public API).
- Alert message dispatch: `LocalizableString` → `.bind(substitutions: ["error": ...])`; the substitution key `error` appears only here — internal constant, not public API.
- Zero client references anywhere: the `LocalizableError` bring-in is a re-authored FOS file (Apache header, FOS DocC); nothing from the consumer file's header, naming, or framework references survives.
- `@Localized…` properties are plain values at call sites — `viewModel.title`, never `viewModel.$title`. `_LocalizedProperty.projectedValue` merely returns `wrappedValue`, and the `$` spelling reads as a `Binding` it isn't; ViewModels contain no bindings. Applies to every DocC example the generator stamps.
- Error-type localization keys are type-rooted, never string-rooted: `.localized(for: Self.self, propertyName: localizationKey)` with a private per-case `localizationKey` switch — no type-name string literals in examples or fixtures.

---

## 5. Decomposition (ordered tasks; PR gate once, at the end)

1. **`LocalizableError`** — `Sources/FOSMVVM/Protocols/LocalizableError.swift` + localization contract tests + TestYAML fixture. No dependencies; smallest reviewable unit.
2. **`AsyncButtonActivity` + engine + 4 primitives** — `Sources/FOSMVVM/SwiftUI Support/AsyncButtonActivity.swift` + the engine-semantics test suite (§3). Depends on nothing new.
3. **Sweep second stage** — extend `scripts/localizable-overload-sweep.swift`; emit `Sources/FOSMVVM/SwiftUI Support/Generated/Button+AsyncAction.swift`; regen; compile-surface + forward tests. Depends on 2.
4. **`.alert(error:)`** — `Sources/FOSMVVM/SwiftUI Support/ErrorAlert.swift` + resolution tests. Depends on 1; parallel with 3.
5. **Bookkeeping** — `fosutilities-api-catalog-update` (new §§ entries: async buttons, LocalizableError, error alert), CHANGELOG, version bump (minor — new public API), `swiftformat`/`swiftlint`, full `swift test`.

Each task lands as granular local commits; squash to logical commits before the branch is offered for review. No PR until David reviews the finished queue and says go.

---

## Open items — all resolved (first pass, 2026-08-20)

1. `isRunning` — **keep** (ratified; justification retained in §1).
2. Alert modifier filename — **`ErrorAlert.swift`** (ratified).
3. Plan slug — stands as `feat-async-button-surface.md`; formal numbering to come with the workflow's numbering source.
4. First-pass DocC corrections applied: `@Localized…` properties are plain values (`viewModel.title`, never `$`); error localization keys are type-rooted via `.localized(for:propertyName:)`.
