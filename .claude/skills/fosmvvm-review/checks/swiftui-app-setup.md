---
area: swiftui-app-setup
generator-skill: fosmvvm-swiftui-app-setup
where:
  - "Sources/**/*App.swift"
  - "Sources/**/*ResourceAccess.swift"
  - "Sources/**/*ViewModels.swift"
---

# SwiftUI App Setup Checks

The positive pattern lives in the `fosmvvm-swiftui-app-setup` skill. This file covers the App struct as it is *maintained* — the edits it takes for the rest of the app's life, which is where these defects arrive. A scaffolded App struct starts correct; it drifts one hand-edit at a time.

## Reviewer Guidance

- **The App struct is generated, then hand-edited forever.** Most findings here are an edit made later — a view added without its registration, a bundle, an environment. Frame them that way: the remedy is the missing edit, not a regeneration.
- **But check the templates before assuming the scaffolder is right.** If a check appears to flag what `Sources/FOSMVVMBootstrap/Templates/*/…App.swift.tmpl` emits, stop and resolve the contradiction rather than reporting it — one of the check, the template, or the generator skill is stale, and it has been the skill before now. Say which, and report it as a finding against the framework, not against the app under review.
- **Find the bundle accessor by content, not by filename.** It is `{Module}ResourceAccess.swift` in one project shape and `{Module}.swift` in another — both shipped. Locate it with `grep -l "localizationBundle"` across the module's sources. Keying on a filename convention misses exactly the projects that drifted from it.
- **Do NOT recommend moving test-view registration out of `init()`** to "clean up" the initializer. The timing is load-bearing: `testHost()` resolves the view under test before the first render, so registration from a computed property, `.onAppear`, or `.task` arrives too late. This looks like an obvious tidy-up and breaks UI testing silently.
- **An empty `deploymentURLs` is not a missing configuration.** A wholly client-hosted app talks to no server, and `[Deployment: MVVMEnvironment.URLPackage]()` is the correct expression of that. Do NOT recommend inventing placeholder URLs to fill it.
- Project settings — targets, signing, build settings, the link and embed graph — are not this area's business. `fosmvvm-doctor` audits those. Report an App-struct concern here and leave the project file alone.

## Check: mvvmenv-built-once
**Severity:** warning
**What:** `MVVMEnvironment` is built once by a static factory and held in `@State` — not rebuilt on every `body` pass.
**Anti-pattern:** `private var mvvmEnv: MVVMEnvironment { MVVMEnvironment(...) }` — a computed property referenced from `body`.
**Detection:** In the `@main` App struct, find the `MVVMEnvironment` declaration. Flag a **computed** form. `body` is evaluated repeatedly, so a computed property constructs a new `MVVMEnvironment` each pass and hands `.environment()` a different instance every render — churn on a value meant to be stable for the app's lifetime, plus repeated bundle and URL resolution. `@State private var mvvmEnv = makeMVVMEnvironment()` with a `@MainActor static func` factory is the shape the scaffolder emits and is **not** a hit.

## Check: test-views-registered-in-init
**Severity:** blocker
**What:** Test-view registration happens in the App struct's `init()`.
**Anti-pattern:** `registerTestView(_:)` calls reached from a computed property, `.onAppear`, `.task`, or any point after the first render.
**Detection:** Find every `registerTestView(` call site and the path that reaches it. Flag any not reachable from the App's `init()`. `testHost()` resolves the view under test before the first render, so a later registration is simply absent when it is needed. The framework does emit a diagnostic naming the missing ViewModel — but the fix is always to move the registration earlier, never to register later still.

## Check: all-viewmodelviews-registered
**Severity:** warning
**What:** Every `ViewModelView` in the app is registered, so it can be driven in isolation under test.
**Anti-pattern:** An app with eight `ViewModelView` conformers and six `registerTestView` calls — the two that were added last are the two nobody can test.
**Detection:** Enumerate `ViewModelView` conformers across the app's sources — they live in the View layer, outside this area's globs, so go read them — and compare against the `registerTestView(_:)` calls.

**Resolve each conformer's `VM` associated type first; this step is mandatory, not an aside.** The registry holds one entry *per ViewModel*, not per view, so several views sharing one ViewModel are correctly represented by a single registration. Skipping this produces a false hit for every extra view in such a group. That sharing is itself a defect, but it belongs to `viewmodel-view-one-to-one` in `swiftui-view.md` — do not double-report it here.

A conformer is a hit when it renders a ViewModel no registration covers **and** is reachable in the running app (something `bind()`s it). A conformer nothing binds is dead code — a finding, but not this one.

**Anchor the finding at the App file's registry**, not at the conformer: the registry is the file in scope and the missing `registerTestView` line is the remedy. Name the unregistered conformer and its ViewModel in the message so the edit is obvious.

## Check: deployment-urls-distinguish-environments
**Severity:** blocker
**What:** Each declared deployment environment resolves to the host it names.
**Anti-pattern:**
```swift
deploymentURLs: [
    .production: .init(serverBaseURL: URL(string: "https://api.example.com")!),
    .debug: .init(serverBaseURL: URL(string: "https://api.example.com")!),  // ← production
    // .debug: .init(serverBaseURL: URL(string: "http://localhost:8080")!)  ← commented out
]
```
**Detection:** Compare the URLs across environments. `MVVMEnvironment` accepts both a `[Deployment: MVVMEnvironment.URLPackage]` and a plain `[Deployment: URL]`; the defect and the check are identical in either, so do not pattern-match on the `.init(serverBaseURL:)` spelling alone. Flag two environments resolving to the same host, and flag a commented-out local URL sitting beside a live production one — the shape of a temporary change that stayed. Every debug run and every UI-test launch then talks to production, which is a data-safety problem before it is a configuration one. An empty `deploymentURLs` is not a hit: see Reviewer Guidance.

## Check: client-hosted-vms-need-resource-bundles
**Severity:** blocker
**What:** An app with client-hosted ViewModels wires their localization bundles into `resourceBundles`.
**Anti-pattern:** A `@ViewModel(options: [.clientHostedFactory])` in the app, and `resourceBundles: []` — or a list missing that module's accessor.
**Detection:** Find ViewModels declared with `clientHostedFactory`, resolve which module carries each one's YAML, and check that module's `localizationBundle` accessor appears in `resourceBundles`. Flag a missing one. The symptoms are `missingLocalizationStore` or `noResourcePaths` at runtime, neither of which names the absent bundle — which is why this is worth catching in review.

## Check: resource-directory-name-matches-hosting
**Severity:** blocker
**What:** `resourceDirectoryName` matches how the bundle was built, and there are three correct answers.
**Anti-pattern:** `resourceDirectoryName: "ViewModels"` for an Xcode framework bundle — the on-disk subfolder that Xcode flattened away, so the search walks a path the built bundle does not contain.
**Detection:** Two places carry a `resourceDirectoryName`, and **both are in scope from the start** — the call sites that pass one, and the bundle accessor's documentation that tells callers which to pass. An app whose every call site is correct can still ship an accessor whose DocC instructs the next caller into `.noResourcePaths`; check the documentation as a first-class site, not as an afterthought once the call sites come back clean.

For each localization load — `MVVMEnvironment`, `loadLocalizationStore`, `initYamlLocalization` — **and for each `localizationBundle` accessor's DocC** — establish the bundle's build system first. That step is the whole cost of this check, so do it deliberately:

- A target listed in `Package.swift` is an **SPM** target; check its `resources:` declaration for the folder it copies.
- A target present in the `.pbxproj` and absent from `Package.swift` is an **Xcode** target.
- For a test target, the platform comes from the **test plan's** membership, not from wherever `swift test` happens to run.

Then check the value:

- **Xcode framework target → `""`, or the argument omitted.** Xcode flattens grouped resources into the bundle's resource root, so any subfolder name finds nothing. `nil` coalesces to `""` and recurses from the root; passing `""` explicitly and omitting it are equivalent, and neither is a hit.
- **SPM target using `.copy("Resources")` → `"Resources"`.** SPM preserves the folder.
- **SPM library with `Resources/Localizations` → `"Localizations"`.**

One project legitimately carries more than one of these at once — a client-server app loads `""` for its Xcode client framework and `"Resources"` for its SPM server target. Do not flag inconsistency between them; flag a value that contradicts *its own* bundle.

When the hit is in documentation rather than a call site, grade it at the severity of what it will cause, and say plainly that no live load is currently broken.

**The test-default trap is conditional.** `loadLocalizationStore`'s `resourceDirectoryName` **defaults to `"Resources"`**, which resolves on macOS and throws `.noResourcePaths` on iOS's flat bundles. A test that omits the argument is a hit only if that test target actually builds for iOS — check the test plan before flagging. A pure-SPM, macOS-only test target omitting it is correct.
