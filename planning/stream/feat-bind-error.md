# `bind(error:)` and the Loading View — Implementation Plan

**Status:** RATIFIED 2026-10-08 (David: "doc approved"). The design was ruled decision-by-decision on 2026-10-08; this plan carries those rulings, the customer DocC drafts, and the test plan.

**The ask (fosline, relaying David, 2026-10-08):** "ViewModelView.bind() should allow providing a binding to an error." A failed server fetch has no way out of `bind()`: the error is printed and the view shows a spinner forever, so an app's designed "server unreachable" state cannot be reached.

**Branch:** `feat/bind-error`.

---

## Rulings (2026-10-08, do not re-litigate)

- **Label and type:** `error:`, `Binding<Error?>`, optional on `bind` (defaults to none).
- **Same rules as `.task(error:)`:** each fetch attempt clears the binding first; a cancelled attempt writes nothing; `CancellationError` is never written.
- **Clear-to-re-fetch:** when the app sets the binding back to `nil` after a failure, the bound view fetches again. No other retry action is offered; anything more is the app's.
- **The loading view handles errors too.** It receives `Error?`: `nil` while waiting, the failure after one.
- **Which loading view is shown, in order:** the `loadingView:` closure passed to `bind` for that screen; else the app-wide `MVVMEnvironment` `loadingView`; else a plain `ProgressView` that ignores the error (the spinner runs forever).
- **`MVVMEnvironment.loadingView` is restored.** The resolver has ignored it since `c969402` (2025-04-25) and hard-coded `ProgressView()`. It is now read again.
- **Breaking change, made outright:** the `MVVMEnvironment` `loadingView:` initializer parameter becomes a `@ViewBuilder` closure taking `Error?`, and the stored property becomes internal. David: no known users.
- **Name:** `loadingView` in both places (`MVVMEnvironment` and `bind`).
- **Server path only.** Client-hosted overloads get neither `error:` nor `loadingView:`.
- **Guard against the silent switch — amended 2026-10-08 (David: "Close with A"):** a runtime stop, not unavailable overloads. The implementation probe showed `@available(*, unavailable)` overloads never win overload resolution while a usable overload matches, so they were dead code. The server resolver's initializer stops a client-hosted ViewModel with a diagnostic naming the fix (pass `appState:`; drop `error:`/`loadingView:`). It also catches the existing case: a `.clientHostedFactory` macro ViewModel always has a struct `AppState`, so `bind()` without `appState:` used to reach the server path quietly. Like the missing-environment diagnostic, the stop traps in release builds too.

- **Failed live refresh of a screen already showing data:** unchanged for now; `refreshInPlace` (`ViewModelView.swift:499`) keeps the data and does NOT write the binding. The binding covers the first load and navigation. Stale data is its own work item: `planning/stream/feat-stale-data-signal.md`.
- **DocC examples for `bind(error:)`:** both presentations, `.alert(error:)` and an in-place `ContentUnavailableView` card.
- **Guards:** superseded by the runtime stop above.
- **`error:` is its own overload (2026-10-08, from the probe):** defaulting `error:` on the existing server overloads made a plain `bind()` pick the server path for some client-hosted ViewModels, so the existing overloads are unchanged and `error:` overloads take a required binding.
- **Unshared binding (OQ15, David 2026-10-08: "Agreed A; don't share"):** `bind(error:)` gets a binding of its own, never shared with buttons, `task(error:)`, or another bind; the docs say so without limiting it to buttons. Retry-by-clearing cannot tell who cleared a shared binding, so the bind owns its binding outright: every launch clears it, and emptying a delivered failure retries.
- **requestErrorHandler (OQ16, David: "seems reasonable"):** with `error:` the screen owns its fetch failures and the handler is not called; without `error:` the handler is called as before and the loading view still gets the failure. The fetch seam always throws; the handler policy lives in `processRequest(mvvmEnv:)` and the resolver.
- **No crash in release (OQ18, David 2026-10-08):** the client-hosted stop happens only in debug builds; a release build fails the load with the same message (an internal error type) and never fetches. The existing missing-environment release stop is its own work item (OQ19): `planning/stream/chore-release-builds-never-stop-on-missing-environment.md`.
- **Rebuilt lean (OQ20, David 2026-10-08: "rebuild" / "I need bind(error:)… I've got a client waiting"):** `feat/bind-error-v2` rebuilds this from `main` with only what `bind(error:)` needs. The resolver keeps `main`'s fetch triggers; a failure keeps the waiting view up and retry restarts its `.task(id: attempt)`. The resolver bugs the reviews found ship separately: `planning/stream/fix-bind-resolver-review-bugs.md`.
- **Cross-target test lock (OQ17):** separate work item, `planning/stream/chore-systemversion-test-lock-all-targets.md`.

---

## 1. Public surface

All in `FOSMVVM`, `#if canImport(SwiftUI)`.

**`ViewModelView` server-path overloads** (`Sources/FOSMVVM/SwiftUI Support/ViewModelView.swift`). The existing server overloads are unchanged. Four new overloads: two take a required `error:` binding, two take a required `loadingView:` closure (with `error:` optional). Defaulting `error:` on the existing overloads was tried and rejected; see the rulings.

```swift
@MainActor static func bind(
    query: VM.Request.Query,
    fragment: VM.Request.Fragment? = nil,
    error: Binding<Error?>
) -> some View

@MainActor static func bind(
    query: VM.Request.Query,
    fragment: VM.Request.Fragment? = nil,
    error: Binding<Error?>? = nil,
    @ViewBuilder loadingView: @escaping (Error?) -> some View
) -> some View

@MainActor static func bind(error: Binding<Error?>) -> some View

@MainActor static func bind(
    error: Binding<Error?>? = nil,
    @ViewBuilder loadingView: @escaping (Error?) -> some View
) -> some View
```

**Client-hosted guard:** a runtime stop (see the rulings); unavailable overloads were tried and never win overload resolution.

**`MVVMEnvironment` initializers** (`Sources/FOSMVVM/SwiftUI Support/MVVMEnvironment.swift`). The two public SwiftUI initializers (and the internal preview initializer) change the parameter:

```swift
@ViewBuilder loadingView: @escaping @Sendable (Error?) -> some View = { _ in ProgressView() }
```

**`MVVMEnvironment.loadingView` property:** `public` → `internal`, type `@Sendable (Error?) -> AnyView`.

**Checklist:** minimal surface (one parameter and one closure, both defaulted away); no stringly-typing; nothing serialized; no module boundary crossed; the type-erased `AnyView` is internal storage only.

## 2. Customer DocC (drafts)

**`bind(error:)` — added to each server overload's existing DocC, after the example:**

```swift
/// To respond when the fetch fails, pass a binding to an error. Present it as an alert:
///
/// ```swift
/// @State private var error: Error?
///
/// var body: some View {
///     OverviewView.bind(error: $error)
///         .alert(error: $error,
///                title: viewModel.unreachableTitle,
///                dismissButtonLabel: viewModel.tryAgainTitle)
/// }
/// ```
///
/// Dismissing the alert clears `error`, which fetches again, so its button acts as "Try
/// again". The alert's strings come from this view's own ``ViewModel``: the screen being bound
/// has no ``ViewModel`` until its fetch succeeds.
///
/// Or present it in place, as a card:
///
/// ```swift
/// @State private var error: Error?
///
/// var body: some View {
///     OverviewView.bind(error: $error)
///         .overlay {
///             if error != nil {
///                 ContentUnavailableView("Can't reach the server", systemImage: "wifi.slash")
///             }
///         }
/// }
/// ```
///
/// A failed fetch lands in `error`. Each fetch clears `error` first, so the binding always
/// holds the outcome of the latest attempt. To try again, set `error` back to `nil`; the view
/// fetches again.
///
/// > Note: A fetch cancelled because the view went away writes nothing to `error`.
```

**`bind(error:loadingView:)`:**

```swift
/// Retrieves a ``RequestableViewModel`` from the web service and binds it to the
/// [View](https://developer.apple.com/documentation/swiftui/view), showing your own view
/// while it loads or after it fails
///
/// ```swift
/// @State private var error: Error?
///
/// var body: some View {
///     OverviewView.bind(error: $error) { error in
///         if error != nil {
///             ContentUnavailableView("Can't reach the server", systemImage: "wifi.slash")
///         } else {
///             ProgressView("Loading overview")
///         }
///     }
/// }
/// ```
///
/// `loadingView` is shown until the ``ViewModel`` arrives. It receives `nil` while the fetch
/// is in flight and the error if the fetch failed. It replaces the app-wide `loadingView`
/// given to ``MVVMEnvironment`` for this one screen.
///
/// Pass `error` to observe or retry: setting it back to `nil` fetches again. Without it,
/// `loadingView` still receives the error, but nothing can retry.
///
/// - Parameters:
///   - error: Receives the failure of the latest fetch; set it to `nil` to fetch again (default: none)
///   - loadingView: The view shown while loading or after a failure
```

**`MVVMEnvironment` initializer parameter:**

```swift
///   - loadingView: The view shown while a server-hosted ``ViewModel`` is being retrieved,
///     and after its retrieval fails. It receives `nil` while waiting and the error after a
///     failure. A screen can replace it with `bind(error:loadingView:)`.
///     (default: a [ProgressView](https://developer.apple.com/documentation/swiftui/progressview)
///     that ignores the error)
```

With an example in the initializer's DocC body:

```swift
/// MVVMEnvironment(
///     appBundle: .main,
///     deploymentURLs: deploymentURLs,
///     loadingView: { error in
///         if error != nil {
///             ContentUnavailableView("Can't reach the server", systemImage: "wifi.slash")
///         } else {
///             ProgressView()
///         }
///     }
/// )
```

**The six `- See Also: ``MVVMEnvironment/loadingView``` lines** point at a symbol that becomes internal. They change to point at the `MVVMEnvironment` initializer.

## 3. Tests

Following the `.task(error:)` precedent (`Tests/FOSMVVMTests/SwiftUI Support/AsyncTaskTests.swift`): each ruling gets a test, driven through the internal seam the resolver forwards to. SwiftUI's own lifecycle (appear, disappear, re-render) is Apple's contract and not re-tested.

- **Clear-on-launch:** a fetch attempt clears a previous error before it completes.
- **Failure lands in the binding.**
- **Success leaves the binding `nil`.**
- **Cancelled attempt writes nothing;** `CancellationError` is never written.
- **Clear-to-re-fetch:** clearing the binding after a failure starts exactly one new fetch; clearing it when no failure is showing starts none.
- **Loading-view order:** the `bind` closure wins over the environment's; the environment's wins over the default; each receives the current error.
- **Restored environment view:** an app-supplied `loadingView` is actually shown (the `c969402` regression).
- **Client-hosted stop:** the diagnostic's message is tested; the stop itself traps, so it is not.
- **Wiring (hosted):** `ServerBindHostedTests` hosts the bound view in a macOS window, answers every fetch with a counting `URLProtocol`, and checks precedence, the environment's view being shown, one fetch per failed load, exactly one more per retry, and a foreign error surviving in the shared binding. Not reachable: a successful fetch (needs a version-stamped response).
- **Global state:** suites that construct an `MVVMEnvironment` or touch `SystemVersion` share the `.systemVersionAccess` test trait, one test at a time across suites.

## 4. Implementer notes

- `VMServerResolverView` keeps an internal `@State` holding the latest failure, so the loading view gets the error even when no binding was passed. The binding mirrors it.
- The write guard reuses the `.task(error:)` rule: `!Task.isCancelled`, and never `CancellationError`. Reuse or share `AsyncTaskEngine`'s logic rather than copying it.
- The first load and every retry run in the waiting view's `.task(id: attempt)`, so SwiftUI cancels them when the view goes away. Retry is a state (`retryRequested`), not a transition, so a failure written and cleared between two renders still retries.
- Clear-to-re-fetch: observe the binding's `nil`-ness with `onChange`; re-fetch only on a failure → `nil` transition.
- The default `{ _ in ProgressView() }` is a public default-argument expression, so it can only name public symbols; `DefaultLoadingView` (private) is deleted.
- **Verify first:** a plain `bind()` on a client-hosted `AppState == Void` ViewModel must still pick the client overload once the server overload becomes `bind(error: = nil)`. Today the client overload wins on constraints with identical signatures; after the change the server candidate needs a defaulted argument. Probe this before anything else; if Swift picks the server overload, keep the server `bind()` / `bind(query:fragment:)` unchanged and add `error:` as a separate overload with a required binding.
- The non-SwiftUI `MVVMEnvironment` initializer's `#if canImport(SwiftUI)` assignment of `loadingView` changes to the new type.

## 5. Ship-time sites

- CHANGELOG `[Unreleased]`: Added (`bind(error:)`, `bind(error:loadingView:)`); Changed, breaking (`MVVMEnvironment` `loadingView:` parameter type, property no longer public); Fixed (environment `loadingView` ignored since 0.x).
- Skills: `fosmvvm-swiftui-view-generator` and `fosmvvm-swiftui-app-setup` (teach `bind(error:)` and the app-wide `loadingView`); plugin version bump.
- API catalog entry and reach-for index line (`FOSMVVM.md § SwiftUI Support`); run `fosutilities-api-catalog-update`.
- Tell fosline what shipped, once, at the end.
