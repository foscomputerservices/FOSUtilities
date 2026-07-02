# `VaporViewModelFactory` serving path is unexercised — missing localizing `encodeResponse`

- **Status:** ✅ done (2026-07-02). All acceptance criteria met; `swift test` green
  (331 tests / 46 suites, 2 pre-existing known issues).
- **Surfaced:** 2026-07-02, while investigating the "assert the server actually serves *localized* ViewModels" improvement item.
- **Area:** `FOSMVVMVapor` (server-hosted ViewModel serving), `FOSTestingVapor`.

## Resolution (2026-07-02)

**Open question answered — localization-on-serve lives in `encodeResponse`, not the
middleware.** `VaporServerRequestMiddleware` is request-binding only (parses the query
into the `ServerRequest` storage, no response post-processing). The route returns the
unlocalized ViewModel and Vapor's `AsyncResponseEncodable` builds the HTTP `Response`, so
that is the single point where localization must occur.

1. Added a default `encodeResponse(for:)` on `VaporViewModelFactory` that delegates to the
   existing `ServerRequestBody.buildResponse(_:)` (encodes via `req.localizingEncoder` +
   stamps the `SystemVersion` header). Conformers now supply only `model(context:)`.
   **SRP/OCP** rationale documented inline.
2. Modernized `TestViewModel` to `VaporViewModelFactory` (`Context == VaporModelFactoryContext<Request>`)
   and re-enabled `performBasicRequest()`.
3. Fixed `VaporServerRequestTest`: full lifecycle per call
   (`make → asyncBoot → dispatch → asyncShutdown`). This killed the `ServeCommand did not
   shutdown before deinit` crash **and** the `-NSTreatUnknownArgumentsAsOpen` ghost (the
   latter came from `startup()` invoking the console arg parser; `asyncBoot()` skips it).
   Also fixed a latent decode bug (response was decoded as `RequestBody`, now `ResponseBody`).
4. Completed `TestViewModel.yml` (added `aLocalizedMultiTypedSubstitution`) so the served
   ViewModel fully round-trips; fixed the docc example.

Original analysis retained below for reference.

## Summary

The server-hosted localized-serve path — `VaporViewModelFactory` → `VaporServerRequestHost` → `VaporServerRequestTest` — has quietly bit-rotted. **No type in the repo conforms to `VaporViewModelFactory`**, there is **no default `encodeResponse(for:)`**, the **docc example omits it** (so the documented pattern would not compile), and the **one end-to-end test is commented out**. The likely trigger is that **Vapor made `AsyncResponseEncodable` (async `encodeResponse`) the required conformance** at some point after this code was written, and nothing was updated to provide the async default.

## How it was found

Tried to re-enable the disabled dogfood test `Tests/FOSMVVMVaporTests/Protocols/VaporServerRequestHostTests.swift :: performBasicRequest()` (which asserts a served ViewModel's `@LocalizedString` resolves to a non-empty value). Peeling the failure revealed three layers:

1. **Not the original tooling bug.** The test was disabled long ago for a Swift 6.0-beta error (`Unknown command -NSTreatUnknownArgumentsAsOpen`); we never get far enough to hit it.
2. **Stale fixture.** `Tests/FOSMVVMVaporTests/TestViewModel.swift` conforms to the old `ViewModelFactory` with `Context = Self`; `VaporViewModelFactory` now requires `Context == VaporModelFactoryContext<Request>`.
3. **Library gap (the real issue).** Modernizing the fixture to `VaporViewModelFactory` fails with:
   `type 'TestViewModel' does not conform to protocol 'AsyncResponseEncodable'` — Vapor requires `func encodeResponse(for:) async throws -> Response`, and FOSMVVMVapor provides no default.

## Why this is the crux

`VaporServerRequestHost.boot` returns the ViewModel straight from the route:

```swift
// Sources/FOSMVVMVapor/Vapor Support/VaporServerRequestHost.swift
group.get { req in
    try await Request.ResponseBody.model(req, vmRequest: req.requireServerRequest())
}
```

So Vapor relies on the ViewModel's `AsyncResponseEncodable.encodeResponse(for:)` to build the HTTP `Response`. **That is exactly where localization-on-serve must occur** — encode the ViewModel through a localizing encoder built from the request's locale (`Accept-Language`) and the app's `LocalizationStore`. Because there is no shared default, every ViewModel would have to hand-roll identical localizing boilerplate — which defeats the purpose of the protocol — and today none do.

## Root-cause hypothesis

`AsyncResponseEncodable` (the `async` `encodeResponse`) is newer in Vapor than this code. The original `VaporViewModelFactory` likely satisfied the *synchronous* `ResponseEncodable` via a default that no longer applies, or Vapor tightened the requirement to the async form. Needs confirmation against the Vapor changelog / the pinned version.

Requirement (pinned Vapor): `.build/checkouts/vapor/Sources/Vapor/Concurrency/ResponseCodable+Concurrency.swift:15`
```swift
func encodeResponse(for request: Request) async throws -> Response
```

## Proposed fix (own task — NOT this change set)

1. **Determine where localization-on-serve belongs** — a default `encodeResponse` on `VaporViewModelFactory`, *or* the `VaporServerRequestMiddleware<Request>` the host also installs. (Open question below.)
2. **Add the localizing default** so a `VaporViewModelFactory` conformer needs to supply only `model(context:)`. It should encode `self` with `JSONEncoder.localizingEncoder(...)` using the request's locale + `Application.localizationStore`.
3. **Modernize `TestViewModel`** to conform to the current `VaporViewModelFactory` (`Context == VaporModelFactoryContext<Request>`) and re-enable `performBasicRequest()` — which finally establishes whether the `-NSTreatUnknownArgumentsAsOpen` ghost is gone on the current toolchain.
4. **Fix the docc example** (`Sources/FOSMVVM/FOSMVVM.docc/ViewModelandViewModelRequest.md`, ~L117) — it omits `encodeResponse` and has a syntax error (`VaporModelFactoryContext<VMRequest>))`).

## Open question

Is localization-on-serve intended to live in `encodeResponse` (the ViewModel encodes itself localized) or in `VaporServerRequestMiddleware<Request>` (post-process the outgoing `Response`)? The host installs both a middleware and relies on `AsyncResponseEncodable`; trace which one is meant to own localization before writing the default, so it lands in the right place.

## Acceptance criteria

- A `VaporViewModelFactory` conformer needs only `model(context:)` — no per-type `encodeResponse`.
- `performBasicRequest()` is enabled and green: a served ViewModel's `@LocalizedString` resolves to its YAML value (e.g. `aLocalizedString == "Some Text"` for `en`).
- The docc example compiles as written.

## References

- `Sources/FOSMVVMVapor/Protocols/ViewModelFactory.swift` — `VaporModelFactoryContext`, `VaporViewModelFactory` (L38: `& Vapor.AsyncResponseEncodable`).
- `Sources/FOSMVVMVapor/Vapor Support/VaporServerRequestHost.swift` — the route handler that returns the ViewModel.
- `Sources/FOSTestingVapor/VaporServerTestCase.swift` — `VaporServerRequestTest` (real-localization app boot; already exists).
- `Tests/FOSMVVMVaporTests/Protocols/VaporServerRequestHostTests.swift` — the disabled `performBasicRequest()` test.
- `Tests/FOSMVVMVaporTests/TestViewModel.swift` — the stale fixture (old `ViewModelFactory`, `Context = Self`).
- `Tests/FOSMVVMVaporTests/TestYAML/TestViewModel.yml` — has `aLocalizedString: "Some Text"` (en) / `"Algunos textos"` (es).
