# Changelog

All notable changes to **FOSUtilities** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **WebAssembly (WASM) platform support**, including a WASI `URLSession`
  implementation (with JavaScript wrapper functions that preserve `this`
  context) so `FOSFoundation` networking works in the browser.
- **Custom `URLSession` injection** — an application can now supply its own
  `URLSession` through `MVVMEnvironment`.
- **`@LocalizedDouble`** — a localized, locale-formatted `Double` property
  wrapper (`LocalizableDouble`), alongside the existing `@LocalizedInt`.
- **Localizable array access** — localized array properties (`@LocalizedStrings`)
  for binding collections of localized values.
- **`OperationBus`** — a mechanism for dispatching ViewModel operations.
- **`Localizable` support for SwiftUI `Label` and `LabeledContent`.**
- **`ViewModelDisplayTestCase`** (FOSTestingUI) — a display-only ViewModel UI
  test base class that does not require a `ViewModelOperations` type.
- **FOSMVVM React runtime resources** are served from `FOSMVVMVapor` at
  `/fosmvvm/react/` under a global namespace.
- **`ReplaceRequest` protocol** — the PUT verb of the write-request family
  (`Create` / `Update` / `Delete` / `Destroy` / **`Replace`**). It mirrors
  `UpdateRequest` (`RequestBody: ValidatableModel`, `action == .replace`) and
  adds the `ReplaceResponseBody` marker. The generic `ServerRequestController`
  already routes `.replace` to `PUT`, so no server-side change is required to
  serve one.
- **`@ViewModel` synthesizes the `Stubbable` witness.** When a type provides a
  fully-defaulted parameterized `stub(...)` but no zero-argument `stub()`, the
  macro now generates `static func stub() -> Self`, forwarding each parameter's
  default explicitly (so the call binds to the parameterized overload rather than
  recursing into the witness). Types no longer need to hand-write the boilerplate
  witness alongside a parameterized stub.

### Changed

- **Yams dependency now points at the official `jpsim/Yams`** (the WASM support
  is kept dormant).

### Fixed

- **`FormFieldView`** now preserves typed whitespace and uses the current
  `onNewValue` closure, and resolves a debounce race and a `FocusState`
  field-clear bug observed on iOS 18.
- **FOSMVVM React resources** are served from the correct bundle root.
- A missing Linux `import` was added.
- **Versioned ViewModel baselines are persisted beside the calling test**, not
  inside FOSTesting's own source. `expectFullViewModelTests` now forwards
  `#filePath` / `#line` to `expectVersionedViewModel`, so the baseline directory
  is resolved at the developer's test file. Previously the convenience wrapper
  resolved `#filePath` to FOSTesting's source and wrote baselines to an
  ephemeral, ignored location, defeating cross-version drift detection.
- **Version-baseline directories anchor on the SwiftPM test-target root**
  (`Tests/<Target>/.VersionedTestJSON`), independent of how deeply the calling
  test file is nested. This keeps equally-named types in sibling test targets
  from colliding on a shared baseline file. Non–SwiftPM layouts fall back to the
  previous behavior.

## Prior releases

Releases up to and including **0.3.7** are recorded as
[Git tags](https://github.com/foscomputerservices/FOSUtilities/tags) and GitHub
Releases. This changelog begins tracking notable changes from the next release
onward.

[Unreleased]: https://github.com/foscomputerservices/FOSUtilities/compare/0.3.7...HEAD
