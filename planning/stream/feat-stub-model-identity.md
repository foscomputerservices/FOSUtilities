---
status: open
last_updated: 2026-10-05
origin: fosline (cross-session message, at David's word of 2026-10-05)
---

A ViewModel that carries a `ModelIdentity` cannot write its `stub()`: the type has no public initializer and is not `Stubbable`, so no stub, preview, or test of such a ViewModel can be written. And nowhere do the DocC, the examples, or the skills teach how a ViewModel carries an identity: opaque, transported, rooting `vmId`, and how a test proves the identity travels the whole chain.

Minted 2026-10-05 from fosline's request (its ViewModels document, OQ-VM13). About fifty of its ViewModels carry an identity; every one of them is blocked. First in the ruled order (OQ2).

## Goal

A ViewModel carries a data-layer identity as an opaque value it only transports and roots its view with; a stub supplies one without the ViewModel layer making up an entity; and a test can hold an identity, pass it in, and prove the Operation received the same one.

Done means:

- `ModelIdentity: Stubbable` in FOSMVVM: `stub()` returns a new identity on each call, equal to itself across a `Codable` round trip, never equal to any real model's identity, and different from every other `stub()`; a test for each.
- The transport rule and the testing pattern taught in the DocC, the catalog, and the skills listed under Input, with the contradicting examples corrected.

## Input

**The rulings** — `planning/notes/fosline-request-rulings-2026-10-05.md`, OQ3: the stub is a stub value, not an entity; David's transport rule and testing pattern are quoted there verbatim.

**The type today** — `Sources/FOSMVVM/Protocols/ModelIdentity.swift:39-44`, verbatim:

```swift
public struct ModelIdentity: Hashable, Codable, Sendable {
    // `package`, NOT public — server-side targets read these to drive the ModelTypeRegistry lookup +
    // Fluent find; clients still cannot read identity contents (opacity is a public-surface guarantee, L0).
    package let namespace: ModelNamespace
    package let id: ModelIdType
```

Only `Model.modelIdentity` or decoding mints one. The ViewModel module imports no model, and a hand-built encoding is forbidden by the type's own DocC.

**David's `Stubbable` pattern, 2026-10-05**, verbatim: "Somehow, my instructions for how to implement Stubble seem to keep getting lost.  My recommendation is to implement a static func stub(<defaulted init parameters>) -> Self { .init(<parameters>) } and then the Stubbable protocol static func stub() { .stub(<pick one to avoid infinte recursion>) }" Written nowhere today: `Stubbable`'s DocC (`Sources/FOSFoundation/Coding/Stubbable.swift:18-35`) shows only a bare `stub()` calling `.init`, and no skill or architecture doc states it; the `@ViewModel` macro already relies on it (`Sources/FOSMacros/ViewModelMacro.swift`, `stubWitnessSource`).

**The motivation and the chaining rule, 2026-10-05**, David verbatim: "It might be good to add the motifcation to the DocC.  The motifcation is that this gives the test/preview caller the ability to specify just the tiniest amount of information that's important to that test/preview, while still receving a fully valid (often multi-level, highly structured) ViewModel.  So, if a value passed in at the top needs to chain down to sub .stub() calls it should so that the entire hirarchy is valid (e.g. static func stub(number: Int = 0) { .init(sub: .stub(number: number)) }"

**Why distinct** (fosline's answer FQ5): a row derives its `vmId` from `identity.viewModelId`, so rows sharing one stub identity collide in a `ForEach` preview. FQ5 also said a stub must be the same on every run because `expectVersionedViewModel` compares against a stored baseline; that is wrong. It writes the stub once and afterwards only checks that stored files decode (`Sources/FOSTesting/Expectations.swift:81-104`), so a new identity per call is fine (OQ18, withdrawn).

**The documentation survey, 2026-10-05: the concept is not established, and one shipped example contradicts it.**

- `Sources/FOSMVVM/Protocols/ModelIdentifiedViewModel.swift:25-36`, the protocol's DocC example, verbatim; the same example is in `.claude/skills/shared/api-catalog/FOSMVVM.md:666-674`:

```swift
/// ```swift
/// @ViewModel
/// struct UserViewModel: RequestableViewModel, ModelIdentifiedViewModel {
///     let modelIdentity: ModelIdentity
///     let vmId: ViewModelId
///
///     init(user: User) throws {
///         self.modelIdentity = try user.modelIdentity
///         self.vmId = modelIdentity.viewModelId
///     }
/// }
/// ```
```

The ViewModel's init takes the `User` model: the data layer inside the ViewModel module, against the transport rule and DIP (the ViewModel module never imports the domain; the factory adapts). It also leaves the ViewModel no way to write `stub()`.

- `.claude/skills/fosmvvm-viewmodel-generator/SKILL.md:278-296` and `reference.md` (lines 101-135, 218-329, 888-912, 1008, 1091-1092) teach a row as `public let id: ModelIdType` with `vmId = .init(id: id)` and stubs defaulting `id: ModelIdType = .init()`: a raw id, not the opaque `ModelIdentity`.
- `.claude/skills/fosmvvm-ui-tests-generator/reference.md:828-844` gives a server-backed stub Operations a `{action}CalledWith` accessor, but its test template (`reference.md:936-946`) asserts only `{action}Called`; no example holds an identity, passes it into the ViewModel, and asserts the Operation received it.
- `fosmvvm-viewmodel-test-generator`, `fosmvvm-swiftui-view-generator`, `.claude/skills/shared/architecture-patterns.md`, and the FOSMVVM and FOSTesting DocC catalogs do not state the transport rule.

## Suggested actions

- Rulings this item waits on are numbered in `planning/notes/fosline-request-rulings-2026-10-05.md`; OQ3, OQ13–OQ17 are ruled.
- `ModelIdentity` has no public init parameters, so under David's `Stubbable` pattern it has only `stub()`, returning a new identity on each call (OQ18).
- Document the pattern where it stops getting lost: `Stubbable`'s DocC (its example becomes the pattern), `fosmvvm-viewmodel-generator`, and `.claude/skills/shared/architecture-patterns.md`. Each states the motivation (a test or preview passes only the little that matters to it and still gets a fully valid, often multi-level ViewModel) and the chaining rule (a value passed at the top flows into the children's `stub(...)` calls, so the whole hierarchy is valid), with David's example `static func stub(number: Int = 0) -> Self { .init(sub: .stub(number: number)) }`.
- Mint the stub from a reserved namespace no `Model` type can produce. How a stub identity behaves if it reaches the server (a typed miss from the `ModelTypeRegistry` lookup, never a crash) is FOSMVVMVapor's, tested there, and never mentioned in the ViewModel-facing DocC.
- The stub's DocC states only the contract: opaque, identifies no entity, a new one per call, round-trips; never its encoded form.
- The stub's DocC example is the testing pattern: hold an identity in a local `let`, pass it into the ViewModel's stub, drive the action, assert the Operation received an equal identity. A preview row stub is the second example.
- Done separately ahead of this item (OQ13, OQ14, OQ16): `ModelIdentifiedViewModel`'s DocC example and its catalog copy take `init(modelIdentity:)`, and the live-refresh sentence is gone. Left for this item (OQ17): the protocol's own test, `Tests/FOSMVVMTests/Identity/ModelIdentifiedViewModelTests.swift`, whose `init(widget:)` and model-built `stub()` move to the same shape once the stub identity exists.
- State the transport rule where a ViewModel author meets it: `ModelIdentity`'s and `ModelIdentifiedViewModel`'s DocC, `architecture-patterns.md`, and `fosmvvm-viewmodel-generator`.
- Reconcile `fosmvvm-viewmodel-generator`'s raw `id: ModelIdType` rows with the opaque identity, and make its stubs take the identity as a defaulted parameter (`modelIdentity: ModelIdentity = .stub()`), per David's `Stubbable` pattern.
- `fosmvvm-ui-tests-generator`: a template that asserts the Operation's `{action}CalledWith` identity equals the one the test passed into the ViewModel.
- `fosmvvm-viewmodel-test-generator`: a round-trip assertion that the identity a test passed in comes back out equal.
- Names are David's (OQ8, ruled): before building, bring him a naming table with just enough context per name; the stub identity has no name beyond `stub()` (OQ18).
- DocC first, then tests, then the catalog (`FOSMVVM.md § Protocols`), the skills, and the plugin bump.

## History

- 2026-10-05 — minted from fosline's request; fosline's answer FQ5 recorded above.
- 2026-10-05 — OQ3 ruled: the stub is a stub value, opaque to the ViewModel, in FOSMVVM; David's transport rule and testing pattern recorded in the rulings file. Documentation survey added: the concept is not established, and the `ModelIdentifiedViewModel` example puts a model in a ViewModel's init. Documentation and skills work added to this item at David's word.
- 2026-10-05 — OQ15 ruled: `ModelIdentifiedViewModel` stays as it is, refining `ViewModel`; David's open thought on client-side identities (a device the app connects to, such as Bluetooth or USB) recorded in the rulings file. OQ13 (the example's `userId`) and OQ14 (when the example changes) opened.
- 2026-10-05 — OQ13, OQ14, OQ16, OQ17 ruled: the example keeps `modelIdentity`, changes now on its own branch with the live-refresh sentence removed; the protocol's test waits for this item.
- 2026-10-05 — OQ9 ruled: ships in 0.20.0 with the rest of fosline's request.
- 2026-10-05 — build order ruled by need: 1 of 5 (rulings file, OQ2).
- 2026-10-05 — David's `Stubbable` pattern recorded; documenting it added to this item. OQ18 (the numbered stub's label) opened.
- 2026-10-05 — the pattern's motivation and chaining rule added; the documentation step states both.
- 2026-10-05 — OQ18 withdrawn at David's word: no numbered stub; `stub()` returns a new identity per call. FQ5's determinism premise found wrong in the code and struck.
- 2026-10-05 — BUILT on feat/stub-model-identity: `ModelIdentity: Stubbable` (new identity per call, private anchor namespace); identity tests in FOSMVVMTests and a FOSMVVMVapor test that a stub is a typed miss (`ContainmentError.unregisteredNamespace`) on load and create; `ModelIdentifiedViewModel` DocC states the transport rule with a compiling example; `Stubbable` DocC, architecture-patterns, catalog, and the viewmodel, swiftui-view, ui-tests and viewmodel-test generator skills teach the pattern and the rule. Open from the build: OQ19 (Leaf skill identity in HTML, skill left unchanged) and OQ20 (form and request ViewModels' `ModelIdType`). Not done: FOSTesting DocC does not restate the transport rule.
