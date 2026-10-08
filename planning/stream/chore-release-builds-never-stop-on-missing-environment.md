---
status: open
last_updated: 2026-10-08
origin: feat-bind-error review (OQ19, David 2026-10-08: "we can't ship crashing code")
---

A missing `MVVMEnvironment`, `Validations`, or client localization store stops the app through `MissingEnvironmentDiagnostic.reportAndStop` (a `fatalError`) in release builds as well as debug. A shipped app with that mistake crashes on the screen that needed the value.

`feat-bind-error` already moved one stop behind `#if DEBUG`: the client-hosted ViewModel reaching the server `bind` path stops in debug and fails the load with the same message in release.

## Goal

No FOSMVVM diagnostic stops a release build. Each one still stops a debug build with its message, and a release build degrades to something the user can see.

## Input

- `MissingEnvironmentDiagnostic.reportAndStop` and `require(_:orStop:)`: `Sources/FOSMVVM/SwiftUI Support/MissingEnvironmentDiagnostic.swift`.
- Call sites (2026-10-08): `ViewModelView.swift` (the three resolvers' `mvvmEnv`), `LocalizableViews.swift:145`, `:154`, `:164`, `FormValidationsView.swift:31`, `FieldValidationsView.swift:34`.
- `TestHostDiagnostic.reportAndStop` (`TestHost.swift:150`, `:174`, `:367`) serves UI-test hosting; decide whether it is in scope.
- The bind precedent: `ServerBindDiagnostic` in `ViewModelView.swift` (debug stop on appear, release `ClientHostedBoundAsServerError` through the load).

## Suggested actions

1. For each call site, decide the release degradation: what the user sees when the value is missing (a failed load, an empty view, text without localization).
2. Gate each stop behind `#if DEBUG`; keep the messages and their tests.
3. Decide whether `TestHostDiagnostic` is in scope.

## History

- 2026-10-08 — Opened at David's ruling on feat-bind-error OQ19.
