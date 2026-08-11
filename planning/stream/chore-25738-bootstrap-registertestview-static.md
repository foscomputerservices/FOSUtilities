---
status: open
last_updated: 2026-08-11
origin: session
---

Finish `../fosmvvm-bootstrap`'s adoption of the `registerTestView(_:)` instance → static change made in FOSUtilities on 2026-08-11.

**The template edits are already applied** (uncommitted, on `main`, clean tree before the edits). What remains is blocked on the FOSUtilities release.

## Why the change happened

The instance method took `self` and never used it — the registry has been a `@MainActor` static since FOSUtilities 0.10.1. That let registration hide inside a computed `mvvmEnv` and run *after* `testHost()` had already resolved the view under test, which is the class of startup-timing bug the 0.10.1 fix was chasing in the first place. Making it static removes the only plausible-looking wrong home for the call.

`App.init()` is now the sole supported call site. The instance method was **removed outright**, no deprecated shim.

## Done

Both app templates now carry the ratified shape — the aggregator stays an extension on `MVVMEnvironment` (where it already lived), becomes `static`, takes the `#if DEBUG` inside its body, and is called from `App.init()`:

```swift
@main
struct {{PROJECT_NAME}}App: App {
    @State private var mvvmEnv = makeMVVMEnvironment()

    var body: some Scene { ... }

    init() {
        MVVMEnvironment.registerTestingViews()
    }
}

private extension MVVMEnvironment {
    // Every ViewModelView is listed here to enable individualized
    // testing of each view.  Registration must happen before the first
    // render — testHost() resolves the view under test in init().
    @MainActor static func registerTestingViews() {
        #if DEBUG
        registerTestView(WelcomeView.self)
        #endif
    }
}
```

The `env.registerTestingViews()` line was deleted from each env factory rather than relocated — the factory has no business registering views once the registry is static — and each factory collapsed to a single expression.

Files touched:
- `Sources/BootstrapKit/Templates/local-only/Sources/{{PROJECT_NAME}}/App/{{PROJECT_NAME}}App.swift.tmpl`
- `Sources/BootstrapKit/Templates/client-server/Sources/{{PROJECT_NAME}}/App/{{PROJECT_NAME}}App.swift.tmpl`

## The version pin — set ahead of the release (David, 2026-08-11)

`Sources/BootstrapKit/FOSPlatformFloor.swift:13` now reads `pinnedFOSVersion = "0.11.0"` — where this change is expected to land. The platform floor table beside it was checked against FOSUtilities `Package.swift` and is unchanged (iOS 17 / macOS 14 / macCatalyst 17 / tvOS 17 / watchOS 10 / visionOS 1).

**This pin points at an unreleased version.** Generated projects will not resolve until FOSUtilities 0.11.0 ships.

**David's standing objection to the pin itself:** a generated project should build against the FOSUtilities it is aligned with, not a hard-coded version string — so the pin is probably not valid in principle. Related: the question of why `fosmvvm-bootstrap` is a separate repo at all rather than folded into FOSUtilities. Both deliberately deferred — that repo is unreleased, so the reset can wait. Say the word if either should become its own `truth-` item for a ruling.

## Then verify

Generate one project of each shape and run the generated UI tests. A missed site now surfaces as a loud diagnostic on stderr — naming the requested ViewModel, listing what *is* registered, and showing the `init()` fix — not as a silent fall-through to the base view.

## Also carrying the old shape

In *this* repo, historical — update only if the plan is re-run: `planning/implementation-plans/2026-07-25-fosmvvm-bootstrap-plan2-local-only.md:518-527`, whose Task text is what produced the local-only template's original `MVVMEnvironment` extension.

## Note on prior behaviour

The templates were not broken *before* this change: `@State private var mvvmEnv = makeMVVMEnvironment()` is a stored property, so its initializer ran when the App struct was created, before the first `body`, and registration landed in time. That was luck, not design — written as a computed property it would have failed silently. The new shape states the timing in the code's structure instead of relying on it.

## History
- 2026-08-11 minted during the FOSUtilities `registerTestView` static change, from David's instruction to note the cross-repo follow-up; templates updated in the same session once David approved doing the edit directly
