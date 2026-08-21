# `.task(error:)` Twin — Implementation Plan

**Status:** UNRATIFIED — awaiting David's review (the *design* was ratified decision-by-decision on 2026-08-20: both Apple overloads twinned; `error:` before `priority:`, `id:` stays first; hand-written `View` extension independent of `AsyncButtonEngine`; file `View+AsyncTask.swift`; error-routing only, no activity participation).

**Ratification surface (David's ruling, 2026-08-21):** the lifecycle semantics — including the suppress-on-cancel rule and the task-state-not-error-type guard — are documented situation-by-situation with sequence diagrams in `Sources/FOSMVVM/FOSMVVM.docc/AsyncLifecycle.md` (drafted, uncommitted). David red-pens the article; the surviving text settles the open semantic rulings, and implementation projects from it. The article ships in the same PR as the twin.

**Scope:** 2 hand-written `View.task` overloads that route a thrown error into the screen's error binding, plus the ship-time sweep of every site currently teaching the hand-caught interim (`grep "queued in FOSUtilities"`).

**Carried rulings (button arc, do not re-litigate):** label `error:`, type `Binding<Error?>` untyped; clear-on-launch ("the binding holds the outcome of the most recent invocation"); action `@escaping @Sendable () async throws -> Void`; a cancelled invocation writes nothing to the binding; presentation pairs with `alert(error:)` / `LocalizableError`.

**Suppression rulings (2026-08-21, ratified in dialogue — supersede the parity-pin question):**

- The deposit guard is `if !Task.isCancelled, let failure, !(failure is CancellationError)` — **both families**. Cancellation never reaches `error`, of any provenance: a cancelled invocation deposits nothing, and the language's `CancellationError` (the exact sentinel type, nothing wider) is never deposited even from a non-cancelled invocation. This is a **behavior change to the shipped 0.13.0 button engine** — David ratified it explicitly.
- Quiet-exit idiom is thereby supported on purpose: an action throws `CancellationError` to end with nothing presented. Documented in `AsyncLifecycle.md`.
- The filter stays sentinel-only: `URLError.cancelled` and other cancellation-flavored domain errors deposit normally — the framework recognizes the language's type, never interprets domain semantics.
- Every discarded outcome (task-cancelled discard AND sentinel-filtered discard) is logged at debug level, both families — following the shipped `print` notice precedent (`ErrorAlert.swift:126`).

---

## 1. Public surface — every symbol justified

All new API lives in `FOSMVVM`, `#if canImport(SwiftUI)`, file `Sources/FOSMVVM/SwiftUI Support/View+AsyncTask.swift` (ratified — parallels `Button+AsyncAction.swift`; hand-written, NOT `Generated/` — the sweep's input set is Localizable-titled surfaces and `.task` has no Localizable slot).

Exactly two public symbols, twinning Apple's two `.task` overloads — Apple's labels and defaults kept verbatim, `error:` inserted before `priority:`, closure becomes `throws`:

```swift
nonisolated func task(
    error: Binding<Error?>,
    priority: TaskPriority = .userInitiated,
    _ action: @escaping @Sendable () async throws -> Void
) -> some View

nonisolated func task<T: Equatable>(
    id: T,
    error: Binding<Error?>,
    priority: TaskPriority = .userInitiated,
    _ action: @escaping @Sendable () async throws -> Void
) -> some View
```

- Caller need, plain form: view-lifetime loads (`try await operations.loadData()`) without hand-caught `do/catch` — the documented interim this arc retires.
- Caller need, `id:` form: reload-on-parameter-change (refetch when a selection changes) — the call site where the interim goes wrong today: a restart's dying invocation deposits `CancellationError` into the alert.
- **Behavior contract:** invocation start clears the binding; a thrown error lands in it; cancellation never reaches the binding — a cancelled invocation writes nothing (view disappearance auto-cancels, and an `id` change cancels the prior invocation before starting the new one, so neither teardown nor restart can write), and a `CancellationError` from a non-cancelled invocation is filtered by sentinel type. Discards are debug-logged.
- **No activity parameter** (ratified): `.task`'s lifecycle is owned by SwiftUI (appear starts it, disappear/id-change cancels it) — no re-entry to refuse, no cancel face to render, so an activity binding would have nothing true to say. Loading UI stays view-state (`@State isLoading`, or `ViewModelView`'s own binding for VM fetches). A future loading-phase need composes onto this surface; it does not preempt it.
- **Sealed engine:** one internal seam both overloads forward to (working name `AsyncTaskEngine.run(error:action:)`, internal enum in the same file, mirroring `AsyncButtonEngine`'s forwarding shape without sharing its code — tap semantics don't exist here). Internal, never public.
- Existential note (governance flag, answered once in the button arc): `error: Binding<Error?>` is the ratified currency — `any Error` is the language's error type at a UI boundary; typed throws ruled out (Apple's standing guidance for rendered-not-handled errors).

### Encapsulation review (separate axis)

Nothing to seal beyond the engine seam — the surface owns no state at all; its whole contract is the three binding rules. No representation exists to publish.

---

## 2. Customer-facing DocC — drafted first

Contract only; rationale lives in §4.

### Plain form

```swift
/// Async form of SwiftUI's `task(priority:_:)` — runs a throwing async action when the view
/// appears and routes its error to a binding
///
/// ```swift
/// @State private var error: Error?
///
/// var body: some View {
///     DocumentList(viewModel: viewModel)
///         .task(error: $error) {
///             try await viewModel.operations.loadDocuments()
///         }
///         .alert(error: $error,
///                title: viewModel.errorTitle,
///                dismissButtonLabel: viewModel.dismissTitle)
/// }
/// ```
///
/// The action starts when the view appears; a thrown error lands in `error`. Starting an
/// invocation clears `error` first — the binding always holds the outcome of the most
/// recent invocation.
///
/// When the view disappears the task is cancelled, and a cancelled invocation writes
/// nothing to the binding — teardown never deposits a `CancellationError` into your alert.
///
/// To restart the load when a value changes, use ``task(id:error:priority:_:)``. For work
/// started by a tap, use the async `Button` forms — they pair with the same binding.
```

### `id:` form

```swift
/// Async form of SwiftUI's `task(id:priority:_:)` — restarts a throwing async action
/// whenever `id` changes and routes its error to a binding
///
/// ```swift
/// @State private var error: Error?
///
/// var body: some View {
///     DocumentDetail(viewModel: viewModel)
///         .task(id: viewModel.selectedDocumentId, error: $error) {
///             try await viewModel.operations.loadDocument()
///         }
///         .alert(error: $error,
///                title: viewModel.errorTitle,
///                dismissButtonLabel: viewModel.dismissTitle)
/// }
/// ```
///
/// The action starts when the view appears and restarts whenever `id` changes to a new
/// value; each start clears `error` first — the binding always holds the outcome of the
/// most recent invocation.
///
/// A restart (or the view disappearing) cancels the in-flight invocation, and a cancelled
/// invocation writes nothing to the binding — a superseded load can never overwrite the
/// current invocation's outcome, and teardown never deposits a `CancellationError` into
/// your alert.
```

---

## 3. Contract tests

`Tests/FOSMVVMTests/SwiftUI Support/AsyncTaskTests.swift` (Swift Testing). Precedent (button arc): semantics are driven through the internal engine seam every public overload forwards to — real `Binding` boxes, harness style of `AsyncButtonActivityTests.swift`; SwiftUI's own `.task` lifecycle (fires on appear, cancels on disappear/id-change) is Apple's contract and is not re-tested here.

- clear-on-launch: pre-deposited error is `nil`ed when an invocation starts, before the action completes
- success: binding is `nil` after the invocation completes
- failure: thrown error lands in the binding
- cancelled invocation writes nothing: cancel the hosting task mid-action; after unwind the binding holds no `CancellationError` and no action error — including when the unwind throws a NON-cancellation failure (the raced-genuine-failure case)
- restart sequence: invocation A cancelled, invocation B fails → binding holds exactly B's error (the superseded invocation contributed nothing)
- sentinel filter: a `CancellationError` thrown by a NON-cancelled invocation is discarded — binding stays `nil` (the quiet-exit idiom)
- sentinel boundary: a non-`CancellationError` failure from a non-cancelled invocation deposits normally, even one that describes a cancellation in domain vocabulary (e.g. a `URLError.cancelled`-shaped error)
- both discard paths are covered in the button family too: extend `AsyncButtonActivityTests` for the sentinel filter (behavior change to the shipped engine)
- compile-surface: both public overloads called from a real `View` body (the `id:` form with an `Equatable` value), matching how generated-surface coverage is done today

---

## 4. Rationale (implementer prose — none of this goes in DocC)

**Why wrap Apple's `.task` rather than build on `onAppear`/`Task`:** SwiftUI already owns the lifecycle (start on appear, cancel on disappear, cancel-and-restart on `id` change); the twin adds exactly one behavior — error routing — so the implementation is a forwarding wrapper: `task(priority:) { await AsyncTaskEngine.run(error:action:) }`.

**Why both overloads (ratified):** the `id:` variant is the reload-on-parameter-change workhorse and the call site most likely to carry the CancellationError-in-alert bug this arc exists to kill; its restart semantics fall straight out of the carried rulings, costing no new contract.

**Why `error:` before `priority:` (ratified):** required parameter before defaulted ones; mirrors the button family where `error:` is the distinguishing required label; leaves `priority:` in Apple's defaulted position so a sync call site becomes error-routed by insertion only. `id:` stays first — it is Apple's selector for the overload.

**Why independent of `AsyncButtonEngine` (ratified):** that enum is tap semantics — refuse/toggle modes, refractory window, activity phases — none of which exists here. The shared piece is only "clear, run, catch, write-unless-cancelled"; both homes pin that contract with their own tests rather than coupling for ~6 lines.

**Why no activity type (ratified):** `AsyncButtonActivity` models a tap lifecycle; here there is no re-entry to refuse and no cancel face to render. A parameter with no behavior behind it is surface bloat; a proven consumer need composes on later.

**Gotchas for the implementer:**

- Apple's `.task` closure is `@_inheritActorContext @Sendable` — at a *body* call site it inherits MainActor, but our wrapper closure is defined inside a nonisolated extension method and inherits nothing. Mark the engine's `run` `@MainActor` so binding writes are main-side; the awaited `@Sendable` action hops off exactly as the button engine's does.
- The full deposit guard — `if !Task.isCancelled, let failure, !(failure is CancellationError)` — goes at the write site, after the catch; cancellation may arrive while the catch is unwinding. The same guard replaces the button engine's `if !Task.isCancelled, let failure` (`AsyncButtonActivity.swift:183` — the engine and hand-written primitives live in `AsyncButtonActivity.swift`; `Generated/Button+AsyncAction.swift` holds only the 12 titled forwarding inits and does not change).
- Discard logging follows the `ErrorAlert.swift:126` `print` precedent — one notice per discard naming the reason (invocation cancelled vs `CancellationError` filtered) and the error type. Behavior change + logging both get explicit CHANGELOG lines.
- Cancellation propagates from Apple's task into the awaited `run` — `Task.isCancelled` inside it reflects the `.task`'s cancellation; no handle plumbing needed.
- Overload resolution against Apple's sync family: the required `error:` label is the disambiguator — don't weaken it to a defaulted parameter.
- Verify `Package.swift` platform floors cover `.task` availability (iOS 15/macOS 12) before assuming no `@available` annotation is needed.
- Skill/doc examples obey the button-arc rules: `@Localized…` properties are plain values (`viewModel.title`, never `$title`); zero client references in any example or fixture.

---

## 5. Decomposition (ordered tasks; PR gate once, at the end)

1. **`AsyncLifecycle.md` ratification** — David red-pens the drafted article; its surviving text is the semantic contract (suppression rules incl. the sentinel filter, quiet-exit idiom, discard logging). DONE when ratified.
2. **Button engine: sentinel filter + discard logging** — replace the deposit guard in `AsyncButtonEngine` (`AsyncButtonActivity.swift:183`), add discard notices, extend `AsyncButtonActivityTests`. Behavior change to shipped 0.13.0 — its own logical commit with its own CHANGELOG line. Depends on 1.
3. **Twin surface + tests** — `Sources/FOSMVVM/SwiftUI Support/View+AsyncTask.swift` (engine + 2 overloads, DocC from §2) + `Tests/FOSMVVMTests/SwiftUI Support/AsyncTaskTests.swift` (§3, projected from the ratified article). Depends on 1; parallel with 2.
4. **Doc sweep** — retire every "queued in FOSUtilities but not yet shipped" interim, and cross-link `AsyncLifecycle.md` from `AsyncActionsAndErrors.md`:
   - `.claude/skills/fosmvvm-swiftui-view-generator/SKILL.md` — op-shape prose (~line 201), § Async Task Pattern (~line 635), comment (~line 1000)
   - `.claude/skills/fosmvvm-swiftui-view-generator/reference.md` — Task on Appear (~line 996) + example bodies
   - `Sources/FOSMVVM/FOSMVVM.docc/AsyncActionsAndErrors.md` — add the view-lifetime section (article already frames the button as the tap-path)
   - `fosmvvm-ui-tests-generator` reference examples using hand-caught `.task { do/catch }` — modernize
   - plugin version bump (skill docs changed)
5. **Bookkeeping** — `fosutilities-api-catalog-update` (FOSMVVM § SwiftUI Support entry + reach-for index line), CHANGELOG under `[Unreleased]` (minor — new public API + button behavior change), `swiftformat`/`swiftlint`, full `swift test`.

Each task lands as granular local commits; squash to logical commits before the branch is offered for review. No PR until David reviews the finished queue and says go.

---

## Open items

1. Internal engine name — working name `AsyncTaskEngine`; internal-only, David may rename at readback.
