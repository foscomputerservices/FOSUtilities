# Model Identity Foundation (Layer 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a sealed, opaque, value-comparable `ModelIdentity` rooted in a data `Model`'s stable id — surfaced through an opt-in ViewModel protocol, bound to `ViewModelId`, and paired with an orthogonal `ViewModelId.Freshness` version clock — as the primitive every later invalidation layer keys on.

**Architecture:** Five small, sealed value/protocol types added to FOSMVVM alongside the existing identity types (`Sources/FOSMVVM/Protocols/`). Each new opaque type shares one deliberate shape: private storage, no public getter, conforms to exactly `Hashable`/`Codable`/`Sendable` (+ `Comparable` where ordering is the contract), and is constructed only from its two real sources — *minted/declared* or *from the wire*. The common-case ViewModel author writes **nothing new** (the reflection default and existing `vmId` patterns keep working); the opt-in surface is three touchpoints (`ModelIdentifiedViewModel`, `modelIdentity.viewModelId`, and an optional marker-type namespace override).

**Tech Stack:** Swift 6 (`swiftLanguageModes: [.v6]`), Swift Testing (not XCTest), FOSFoundation (`ModelIdType == UUID`, canonical GMT `JSONDateTimeFormatter`), SwiftPM. Format with `swiftformat .`, lint with `swiftlint`.

---

## Guardrails (read before writing any code)

This layer is foundational; a slip here surfaces far away (runtime identity mismatch, leaked persistence type). Hold these while implementing — if a step tempts you past them, **stop and raise it**, don't "simplify".

**Encapsulation is a *precondition* these principles assume — not one of them, and not something a "SOLID-clean" verdict certifies.** The SOLID bullets below govern *structure and dependency direction*; encapsulation governs *state visibility*. The relationship is one-directional: SOLID's benefits **degrade silently** without encapsulation, but SOLID neither defines nor enforces it. You can satisfy every bullet with a type whose internals are wide open (SRP has nothing to say about a `public var`; OCP is "followed" the moment you modify nothing, even while an extension reaches around an abstraction into hidden state). So the danger is precisely that the design still *looks* SOLID while the guarantee leaks — exactly what a `String` accessor on an opaque identity does. **Review encapsulation separately from SOLID; a SOLID pass never implies the internals are safe.**

SOLID bullets (structure/dependencies):

- **SRP** — each new type has one responsibility and lives in its own file. `ModelIdentity` is a *projection of* a Model's identity, never a place to stash extra data.
- **OCP** — extend via protocol requirement + default (`Model.modelIdentityNamespace`), not by patching call sites. No new options/sentinels without a named source or consumer.
- **LSP / ISP** — `ModelIdentifiedViewModel` is **opt-in**; singleton/ephemeral ViewModels keep only `vmId`. Don't widen `ViewModel`.
- **DIP** — nothing here imports a domain/wire/persistence module. `ModelIdentity` stores `ModelIdType` (`UUID`), never a Fluent type.

Encapsulation + surface (the separate axis):

- **No API bloat** — the whole point is that it "just works." If you find yourself adding a public getter, a String initializer, an `init(id:timestamp:)` seam, a `Comparable` conformance on `ViewModelId`, or any accessor onto the opaque value, that is the red flag the spec forbids — **stop and discuss.**

**Opacity is compiler-guaranteed, not tested at runtime.** `private let` fields + a single `internal rawValue` on `ModelNamespace` (its only cross-type accessor) are the guarantee; the vmId derivation is an owner-scoped computed that vends a `ViewModelId`, never a raw string. Do **not** add a public accessor to make a test easier. There is a deferred debug/log channel — until it lands, **never string-interpolate** `ModelNamespace`/`ModelIdentity`/`Freshness` (Swift's default `Mirror` would dump the private field).

**Test the contract, not the representation (hard rule).** The vmId rendering token's *only* contract is: **deterministic and stable within a version** — equal identities → equal vmId, distinct identities → distinct vmId. The exact bytes (`"ns|uuid"`) are **not** contractual. So assert equality/distinctness/stability — **never** assert the literal token string. Exposing the token as a `String` just to `#expect(token == "Foo|<uuid>")` is exactly the slop this design forbids: it invents a "contract" that doesn't exist, freezes an implementation detail, and sets precedent for the next shortcut. `ModelIdentity`'s encoded shape *is* frozen (L1 persists it in DB columns), but that is a **library-internal** invariant: guard it with a **forward-compat** test (a committed golden blob still decodes and round-trips) — the contract is "stored data keeps loading," not "encode emits these exact keys."

**Contract tests use the public API only — `@testable` is for coverage, never for contract (hard rule).** Construct values the way real callers do (mint via `model.modelIdentity`; build a `ViewModelId` via its public inits) and assert through public conformances (`==`, `hashValue`, `Comparable`, `Codable` round-trip). Do **not** `@testable import` to reach an internal init/getter to make a contract test constructible — if the contract can't reach it, neither should the test. `@testable`/private access is legitimate *only* for block/arc **coverage**. Use the repo's `try value.toJSON().fromJSON()` round-trip helpers (encoder-agnostic, canonical dates) rather than hand-rolled `JSONEncoder`/`JSONSerialization`, and never inspect the raw encoded JSON in an assertion.

**Encapsulation is broken by *publishing* the representation, too — not only by accessors (hard rule).** Do **not** state a sealed type's internal encoded shape (`{"namespace":"…","id":"…"}`, `"ns|uuid"`, field names, byte layout) on any **public** surface — DocC comments, the CHANGELOG, README. A public doc that shows the shape is a de-facto schema: readers will parse it or hand-forge the value, and now you can never change it. State the **contract** (opaque; `Codable` round-trips; stable within a major version; do not parse or hand-construct), never the shape. The shape, where it must be pinned, lives in an **internal `//` maintainer comment** beside the `CodingKeys` + an internal test — invisible to consumers.

## Placement decision (resolving the spec's open placement note)

`ModelNamespace` **stays in FOSMVVM** (`Sources/FOSMVVM/Protocols/`), not FOSFoundation. Rationale: it exists to serve `Model` (also FOSMVVM), and its only consumer in this layer is `ModelIdentity` (FOSMVVM). Promote to FOSFoundation later only if a concrete reuse appears — do not pre-optimize.

## File Structure

**New files (all in `Sources/FOSMVVM/Protocols/`):**
- `ModelNamespace.swift` — opaque namespace token; `init(for: Any.Type)` only, single-value `Codable`, module-internal `rawValue`.
- `ModelIdentity.swift` — opaque, non-generic identity `(namespace, id)`; internal init, pinned `CodingKeys`, `== some Model` sugar, and the owner-scoped `viewModelId` computed (the rendering-identity bridge).
- `ModelIdentifiedViewModel.swift` — opt-in `protocol ModelIdentifiedViewModel: ViewModel { var modelIdentity: ModelIdentity { get } }`.

**Modified files:**
- `Sources/FOSMVVM/Protocols/Model.swift` — add `modelIdentityNamespace` (requirement + default) and `modelIdentity` (computed, `get throws`, **not** `@inlinable`); **remove** the dormant `modelType` requirement + defaults.
- `Sources/FOSMVVM/Protocols/ViewModelId.swift` — add nested `Freshness` + `let freshness`, assign per-init, always-encode / lenient-decode under key `fsh` (rename the dormant `case timestamp = "ts"`). **No `ModelIdentity` awareness** — the bridge lives on `ModelIdentity`.

**New test files (in `Tests/FOSMVVMTests/Identity/`):**
- `IdentityTestFixtures.swift` — shared test `Model`s + stable marker enums (introduced when first needed, Task 3).
- `ModelNamespaceTests.swift`, `ModelIdentityCodableTests.swift`, `ModelIdentityModelTests.swift`, `ViewModelIdFreshnessTests.swift`, `ModelIdentityViewModelIdTests.swift`, `ModelIdentifiedViewModelTests.swift`.

**Docs:** `CHANGELOG.md` (Added + breaking Removed). DocC lives in the source files' doc comments (the repo treats undocumented shipped API as debt).

**Task order & dependencies (execute top-to-bottom):**
1. `ModelNamespace` — standalone.
2. `ModelIdentity` core type — needs 1.
3. `Model` additions + `modelType` removal — needs 1, 2.
4. `ModelIdentity == some Model` — needs 3 (minting).
5. `ViewModelId.Freshness` — touches only `ViewModelId.swift`.
6. `ModelIdentity.viewModelId` (rendering-identity bridge) — needs 2, 3 (fixtures); modifies `ModelIdentity.swift`, not `ViewModelId.swift`.
7. `ModelIdentifiedViewModel` — needs 3, 4, 6 (its idiomatic conformance uses `modelIdentity.viewModelId` and `== some Model`).
8. Full-suite verification + CHANGELOG.

---

## Task 1: `ModelNamespace` — opaque namespace token

**Files:**
- Create: `Sources/FOSMVVM/Protocols/ModelNamespace.swift`
- Test: `Tests/FOSMVVMTests/Identity/ModelNamespaceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ModelNamespaceTests.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

private enum AlphaMarker {}
private enum BetaMarker {}

struct ModelNamespaceTests {
    @Test func equalForSameType() {
        #expect(ModelNamespace(for: AlphaMarker.self) == ModelNamespace(for: AlphaMarker.self))
    }

    @Test func unequalForDifferentType() {
        #expect(ModelNamespace(for: AlphaMarker.self) != ModelNamespace(for: BetaMarker.self))
    }

    @Test func codableRoundTripIsIdentityPreserving() throws {
        // Contract: encode→decode preserves the value. We assert the round-trip identity, NOT the
        // encoded shape (the "bare string" wire form is a representation detail, not a public contract).
        // `toJSON()`/`fromJSON()` are the repo's encoder-agnostic round-trip helpers (FOSFoundation).
        let ns = ModelNamespace(for: AlphaMarker.self)
        let back: ModelNamespace = try ns.toJSON().fromJSON()
        #expect(back == ns)
    }
}
```

> The single-value `Codable` (bare string, not `{"value":…}`) is a production design choice so the
> persisted `ModelIdentity` shape stays clean — but it is a **library-internal representation**, so
> there is **no** test asserting that shape (that would be a representation test), and the doc comment
> does not advertise it. The invariant is guarded downstream by `ModelIdentity`'s forward-compat
> golden-blob decode (Task 3), whose committed fixture carries a bare-string namespace.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelNamespaceTests`
Expected: FAIL — `cannot find 'ModelNamespace' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ModelNamespace.swift  (Apache 2.0 header added by swiftformat)
import Foundation

/// Identifies the *kind* of a ``Model`` (its type) as an opaque token.
///
/// You rarely build one yourself — every ``Model`` supplies a default via
/// ``Model/modelIdentityNamespace``. Reach for it only to **override** that default: when you persist
/// a model's identity and need the stored value to survive a future rename of the model type. Anchor
/// the namespace to a dedicated marker type instead of the model, so renaming `User` can't shift it:
///
/// ```swift
/// enum UserIdentity {}   // a stable name you'll never rename; it exists only to anchor the token
///
/// extension User {
///     static var modelIdentityNamespace: ModelNamespace { .init(for: UserIdentity.self) }
/// }
/// ```
///
/// A namespace can be made only from a *type*, never a raw string, and its contents can't be read
/// back out — so it can't be forged or parsed. It is `Hashable` and `Codable`.
public struct ModelNamespace: Hashable, Sendable {
    private let value: String
    internal var rawValue: String { value }   // read by ModelIdentity to build the vmId token

    /// Creates the namespace identifying `type`.
    public init(for type: Any.Type) {
        // Reflecting, NOT describing: the module-qualified name avoids cross-module collisions.
        value = String(reflecting: type)
    }
}

extension ModelNamespace: Codable {
    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelNamespaceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/ModelNamespace.swift Tests/FOSMVVMTests/Identity/ModelNamespaceTests.swift
swiftlint --path Sources/FOSMVVM/Protocols/ModelNamespace.swift
git add Sources/FOSMVVM/Protocols/ModelNamespace.swift Tests/FOSMVVMTests/Identity/ModelNamespaceTests.swift
git commit -m "feat(FOSMVVM): add opaque ModelNamespace identity token"
```

---

## Task 2: `ModelIdentity` — opaque, non-generic identity

Depends on: Task 1. (Semantic equality/hash and the `== some Model` operator are tested in Tasks 3–4 through the public `model.modelIdentity` mint path — **not** here via `@testable`. This task's only contract-boundary test is the persistence forward-compat one, driven through public `Codable`.)

**Files:**
- Create: `Sources/FOSMVVM/Protocols/ModelIdentity.swift`
- Test: `Tests/FOSMVVMTests/Identity/ModelIdentityCodableTests.swift`

> **Testing discipline (why there's only one test, and no `@testable`).** `ModelIdentity` has no public constructor by design — it is minted via `Model.modelIdentity` (Task 3) or obtained by `Codable` decode. Its value semantics (equal for equal `(namespace, id)`, unequal across namespaces, hash) are therefore tested in Task 3 through the **real public mint path**, not by reaching the internal init with `@testable`. `@testable` is for block/arc *coverage*, never for *contract* coverage. The one thing genuinely testable at the contract boundary now is the **persistence forward-compat contract** ("previously-stored data keeps loading"), via the public `Codable` decode.

- [ ] **Step 1: Write the failing test**

```swift
// ModelIdentityCodableTests.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

struct ModelIdentityCodableTests {
    // Persistence forward-compat CONTRACT: a previously-stored identity must keep decoding. If a
    // CodingKey is ever renamed/removed (which silently breaks stored DB data), decoding this committed
    // blob throws — the failure is caught here. Public `Codable` only (no `@testable`), and we assert
    // *behavior* (decodes + round-trips idempotently), NOT the current encode byte/key shape. The blob
    // is the persistence contract made concrete — the single internal home for the stored form; the
    // public API never advertises it. (`ModelNamespace.init(from:)` accepts any string, so the fixture
    // is decoupled from any marker type's reflected name — no churn on a rename/move.)
    @Test func storedIdentityStillDecodesAndRoundTrips() throws {
        let golden = #"{"namespace":"App.WidgetIdentity","id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301"}"#
        let decoded: ModelIdentity = try golden.fromJSON()          // throws if a key was renamed/removed
        let roundTripped: ModelIdentity = try decoded.toJSON().fromJSON()  // encode→decode reproduces value
        #expect(roundTripped == decoded)                            // behavior, not a byte-shape assertion
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelIdentityCodableTests`
Expected: FAIL — `cannot find 'ModelIdentity' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ModelIdentity.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import Foundation

/// Answers "which entity is this?" for a ``Model`` — an opaque, value-comparable identity that stays
/// stable across the wire, persistence, and authorization.
///
/// Get one from a model, then compare, route on, or store it — without ever touching the underlying
/// id or type:
///
/// ```swift
/// let identity = try user.modelIdentity
///
/// if identity == changedModel { refresh() }     // compare to a live model of any type, safely
/// grantedContainers.contains(identity)          // Hashable — use it as a Set member or dictionary key
/// ```
///
/// You can't build one from raw values (only ``Model/modelIdentity`` or decoding mints one), and you
/// can't read its contents back out.
///
/// - Important: Treat it as opaque. Encode/decode it *as a whole* to persist or transmit it; never
///   parse or hand-build its encoded form. The encoding is stable — it changes only on a library major
///   version — so a stored identity always round-trips.
public struct ModelIdentity: Hashable, Codable, Sendable {
    private let namespace: ModelNamespace
    private let id: ModelIdType

    internal init(namespace: ModelNamespace, id: ModelIdType) {   // internal ⇒ only Model.modelIdentity mints one
        self.namespace = namespace
        self.id = id
    }

    // Frozen: L1 persists these in DB columns — never rename/reorder/remove a key (breaks stored
    // data; a change here is a library major-version bump).
    private enum CodingKeys: String, CodingKey {
        case namespace
        case id
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelIdentityCodableTests`
Expected: PASS (1 test). Value semantics are covered in Task 3 via the public mint path.

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/ModelIdentity.swift Tests/FOSMVVMTests/Identity/ModelIdentityCodableTests.swift
swiftlint --path Sources/FOSMVVM/Protocols/ModelIdentity.swift
git add Sources/FOSMVVM/Protocols/ModelIdentity.swift Tests/FOSMVVMTests/Identity/ModelIdentityCodableTests.swift
git commit -m "feat(FOSMVVM): add sealed non-generic ModelIdentity value"
```

---

## Task 3: `Model` — add namespace + identity, remove dormant `modelType`

Depends on: Tasks 1–2.

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/Model.swift`
- Create: `Tests/FOSMVVMTests/Identity/IdentityTestFixtures.swift`
- Create: `Tests/FOSMVVMTests/Identity/ModelIdentityModelTests.swift`

- [ ] **Step 1: Write the shared fixtures + failing test**

```swift
// IdentityTestFixtures.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation

/// Stable marker — its reflection token must not churn; used for persisted/golden namespace tests.
enum TestWidgetIdentity {}

/// A Model that takes the zero-config reflection default for its namespace.
struct TestGadget: Model {
    var id: ModelIdType?
    init(id: ModelIdType? = UUID()) { self.id = id }
}

/// A Model that overrides its namespace by anchoring to a stable marker type.
struct TestWidget: Model {
    var id: ModelIdType?
    init(id: ModelIdType? = UUID()) { self.id = id }
    static var modelIdentityNamespace: ModelNamespace { .init(for: TestWidgetIdentity.self) }
}
```

```swift
// ModelIdentityModelTests.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

struct ModelIdentityModelTests {
    // Group 1: namespace default vs override (dispatch through Model.self, not the concrete type).
    @Test func defaultNamespaceIsReflectionOfType() {
        func namespace<M: Model>(of _: M.Type) -> ModelNamespace { M.modelIdentityNamespace }
        #expect(namespace(of: TestGadget.self) == ModelNamespace(for: TestGadget.self))
    }

    @Test func overriddenNamespaceAnchorsToMarker() {
        func namespace<M: Model>(of _: M.Type) -> ModelNamespace { M.modelIdentityNamespace }
        #expect(namespace(of: TestWidget.self) == ModelNamespace(for: TestWidgetIdentity.self))
        #expect(namespace(of: TestWidget.self) != ModelNamespace(for: TestWidget.self))
    }

    // Group 2: minted-identity equality/hash — all constructed through the PUBLIC mint path
    // (`model.modelIdentity`), never the internal init. No `@testable`.
    @Test func mintedIdentityEqualityFollowsNamespaceAndId() throws {
        let uuid = UUID()
        let a = try TestWidget(id: uuid).modelIdentity
        let b = try TestWidget(id: uuid).modelIdentity
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        // Same UUID, different namespace ⇒ unequal (proves namespace participates; a collision can't alias).
        let c = try TestGadget(id: uuid).modelIdentity
        #expect(a != c)
    }

    // Group 4 (value contract): Codable round-trip preserves the identity — minted publicly, then
    // encode→decode == original. Asserts the value contract, not the encoded shape.
    @Test func mintedIdentityCodableRoundTrips() throws {
        let original = try TestWidget(id: UUID()).modelIdentity
        let back: ModelIdentity = try original.toJSON().fromJSON()
        #expect(back == original)
    }

    // Group 7: throwing path — unpersisted model throws, does not crash.
    @Test func modelIdentityThrowsForNilId() {
        #expect(throws: (any Error).self) {
            _ = try TestWidget(id: nil).modelIdentity
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelIdentityModelTests`
Expected: FAIL — `value of type 'TestWidget' has no member 'modelIdentity'` / no `modelIdentityNamespace`.

- [ ] **Step 3: Edit `Model.swift` — add the identity members**

In the `public protocol Model` body, **replace** the `modelType` requirement with the namespace requirement:

```swift
// REMOVE:
//     static var modelType: String { get }
// ADD:
    /// The namespace identifying this model's *kind*. Defaults to the model's own type — override it
    /// (anchored to a stable marker type) to keep a *persisted* identity stable across a type rename.
    /// See ``ModelNamespace``.
    static var modelIdentityNamespace: ModelNamespace { get }
```

In `public extension Model`, **remove** both `modelType` defaults and **add** the namespace default + identity:

```swift
// REMOVE:
//     @inlinable static var modelType: String { String(describing: Self.self) }
//     @inlinable var modelType: String { Self.modelType }
// ADD:
    static var modelIdentityNamespace: ModelNamespace { .init(for: Self.self) }

    /// This model's opaque ``ModelIdentity`` — use it to compare, route on, or store *which entity
    /// this is*:
    ///
    /// ```swift
    /// let identity = try user.modelIdentity
    /// ```
    ///
    /// - Throws: ``ModelError/missingId(modelType:)`` when ``id`` is `nil` (the model isn't persisted
    ///   yet). For a non-throwing path, guard on `id != nil` first.
    var modelIdentity: ModelIdentity {
        // Not @inlinable — it calls ModelIdentity's internal init, which @inlinable can't reach.
        get throws { try .init(namespace: Self.modelIdentityNamespace, id: requireId()) }
    }
```

Leave `requireId()` and `ModelError` untouched — `ModelError.missingId` uses `String(describing: Self.self)` **directly**, not the removed property, so it is unaffected. (The `ModelError` case keeps its `modelType:` **label** and its `debugDescription`'s local binding — those are fine and unrelated to the removed protocol member.)

- [ ] **Step 4: Run test to verify it passes, then confirm nothing referenced the removed `modelType` member**

```bash
swift test --filter ModelIdentityModelTests           # Expected: PASS (5 tests)
# The removed member appeared as `Self.modelType` / `.modelType` / `var modelType`.
# Expected: no output (matches inside ModelError — the `missingId(modelType:)` label and its
# debugDescription local binding — are intentional and do NOT use these forms).
grep -rnE "\.modelType\b|\bSelf\.modelType\b|var modelType" Sources/ Tests/
```

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/Model.swift Tests/FOSMVVMTests/Identity/
swiftlint --path Sources/FOSMVVM/Protocols/Model.swift
git add Sources/FOSMVVM/Protocols/Model.swift Tests/FOSMVVMTests/Identity/IdentityTestFixtures.swift Tests/FOSMVVMTests/Identity/ModelIdentityModelTests.swift
git commit -m "feat(FOSMVVM)!: add Model.modelIdentity; remove dormant modelType

BREAKING: removes the unused, stringly-typed Model.modelType in favor of
the opaque ModelNamespace / modelIdentity. Downstream references migrate to
modelIdentityNamespace."
```

---

## Task 4: `ModelIdentity == some Model` — comparability sugar

Depends on: Task 3 (needs `Model.modelIdentity`).

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ModelIdentity.swift`
- Modify: `Tests/FOSMVVMTests/Identity/ModelIdentityModelTests.swift`

- [ ] **Step 1: Add the failing test** (append to `ModelIdentityModelTests`)

```swift
    // Group 3: `identity == model` — heterogeneous filtering sugar (NOT Equatable conformance).
    @Test func identityEqualsModel() throws {
        let uuid = UUID()
        let widget = TestWidget(id: uuid)
        let identity = try widget.modelIdentity
        #expect(identity == widget)                       // rooted in that model's id
        #expect(!(identity == TestWidget(id: UUID())))    // different id
        #expect(!(identity == TestWidget(id: nil)))       // unpersisted ⇒ false, no throw escapes
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelIdentityModelTests/identityEqualsModel`
Expected: FAIL — no `==` operator for `(ModelIdentity, some Model)`.

- [ ] **Step 3: Add the operator to `ModelIdentity.swift`**

```swift
public extension ModelIdentity {
    /// Whether this identity is the one rooted in `model` — sugar for `models.filter { changed == $0 }`.
    ///
    /// An unpersisted `model` (`id == nil`) compares `false`; it never throws.
    static func == (lhs: ModelIdentity, rhs: some Model) -> Bool {
        (try? lhs == rhs.modelIdentity) ?? false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelIdentityModelTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/ModelIdentity.swift Tests/FOSMVVMTests/Identity/ModelIdentityModelTests.swift
swiftlint --path Sources/FOSMVVM/Protocols/ModelIdentity.swift
git add Sources/FOSMVVM/Protocols/ModelIdentity.swift Tests/FOSMVVMTests/Identity/ModelIdentityModelTests.swift
git commit -m "feat(FOSMVVM): add ModelIdentity == some Model comparability sugar"
```

---

## Task 5: `ViewModelId.Freshness` — orthogonal version clock

Depends on: nothing new (touches only `ViewModelId.swift`). Keep identity behavior (`==`/`hash`/`.id()`) **exactly** `id`-only.

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ViewModelId.swift`
- Create: `Tests/FOSMVVMTests/Identity/ViewModelIdFreshnessTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ViewModelIdFreshnessTests.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

struct ViewModelIdFreshnessTests {
    // Public contract only (no @testable, no raw-JSON inspection). The 2020 canonical payload stands
    // in for "an old wire moment"; comparing by ordering avoids the sub-millisecond precision caveat.

    // Ordering — a later birth sorts after an earlier one.
    // async because of Task.sleep — Swift Testing supports async @Test functions.
    @Test func freshnessOrdersByBirthMoment() async throws {
        let a = ViewModelId(id: "x").freshness
        try await Task.sleep(nanoseconds: 2_000_000)   // ~2ms so the canonical (ms-precision) clock advances
        let b = ViewModelId(id: "y").freshness
        #expect(a < b)
    }

    // Identity ignores freshness — same logical id, different freshness ⇒ still ==, equal hash.
    @Test func identityIgnoresFreshness() throws {
        let born = ViewModelId(id: "same")
        let decoded: ViewModelId = try #"{"id":"same","fsh":"2020-01-01T00:00:00.000Z"}"#.fromJSON()
        #expect(born == decoded)                        // identity is id-only …
        #expect(born.hashValue == decoded.hashValue)
        #expect(decoded.freshness < born.freshness)     // … yet freshness differs and orders correctly
    }

    // Wire preserves the moment — decode does NOT re-stamp to the client's now.
    @Test func decodePreservesWireMomentNotNow() throws {
        let decoded: ViewModelId = try #"{"id":"x","fsh":"2020-01-01T00:00:00.000Z"}"#.fromJSON()
        #expect(decoded.freshness < ViewModelId(id: "z").freshness)
    }

    // Freshness survives the wire (proves it IS encoded AND preserved): a round-trip of an old
    // moment stays equivalent — if freshness weren't encoded, decode would re-stamp to now and the
    // two would differ. Ordering-equivalence, never a byte/key-shape assertion.
    @Test func freshnessSurvivesRoundTrip() throws {
        let original: ViewModelId = try #"{"id":"x","fsh":"2020-01-01T00:00:00.000Z"}"#.fromJSON()
        let roundTripped: ViewModelId = try original.toJSON().fromJSON()
        #expect(!(original.freshness < roundTripped.freshness))
        #expect(!(roundTripped.freshness < original.freshness))   // equivalent ⇒ preserved
    }

    // Lenient decode — a payload lacking `fsh` still decodes (no throw) and yields a usable vmId.
    @Test func decodeToleratesMissingFreshness() throws {
        let decoded: ViewModelId = try #"{"id":"legacy"}"#.fromJSON()
        #expect(decoded == ViewModelId(id: "legacy"))    // decoded correctly, asserted via public ==
    }
}
```

> **Not-Comparable is a review invariant, not a runtime test** (spec test group 8): confirm by review that `ViewModelId` declares **no** `Comparable` conformance and no `<`. (A runtime test cannot assert the *absence* of an operator.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ViewModelIdFreshnessTests`
Expected: FAIL — no `freshness` member / no `Freshness` type.

- [ ] **Step 3: Edit `ViewModelId.swift`**

Add the stored property to the struct (after `isRandom`):

```swift
    /// This vmId's birth moment — a version clock. You rarely read it directly; the framework uses it
    /// to tell a newer copy of a ViewModel from an older one (and drop stale refreshes). `==` and
    /// `hash` ignore it, so two versions of the same entity stay equal. To compare versions yourself:
    ///
    /// ```swift
    /// if incoming.freshness > current.freshness { current = incoming }   // keep the newer copy
    /// ```
    public let freshness: Freshness
```

Assign it in the two **root** inits (all others delegate and inherit):

```swift
    public init(id: String? = nil) {
        self.id = id ?? String.unique()
        self.isRandom = id == nil
        self.freshness = Freshness()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
        self.isRandom = id == nil
        self.id = id ?? String.unique()
        // Missing fsh (legacy payload) ⇒ now; present ⇒ preserved (decode never re-stamps).
        self.freshness = try container.decodeIfPresent(Freshness.self, forKey: .freshness) ?? Freshness()
    }
```

Always-encode `fsh` in `encode(to:)` (leave the `id` branch as-is):

```swift
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !isRandom {
            try container.encode(id, forKey: .id)
        }
        try container.encode(freshness, forKey: .freshness)   // always encoded, unlike id
    }
```

Rename the dormant `CodingKey` (the `timestamp`/`ts` holdover is gone):

```swift
private extension ViewModelId {
    enum CodingKeys: String, CodingKey {
        case id
        case freshness = "fsh"   // short key: ViewModelId is embedded in every streamed VM
    }
}
```

Add the nested `Freshness` type + its single-value `Codable` (place after the main struct):

```swift
public extension ViewModelId {
    /// A version clock for a ``ViewModelId``. It only compares (`<`, `==`) — no `Date` arithmetic,
    /// calendar, or formatting — which is exactly what you want to tell a newer version from an older
    /// one: `a.freshness < b.freshness`.
    struct Freshness: Comparable, Sendable {
        private let timestamp: Date

        init() { self.timestamp = .now }   // internal ⇒ a Freshness can't be forged with an arbitrary moment

        public static func < (lhs: Freshness, rhs: Freshness) -> Bool {
            lhs.timestamp < rhs.timestamp
        }
    }
}

extension ViewModelId.Freshness: Codable {
    public init(from decoder: Decoder) throws {
        self.timestamp = try decoder.singleValueContainer().decode(Date.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(timestamp)
    }
}
```

> Canonical-GMT comes for free from the repo's coders: `toJSON()`/`fromJSON()` default to `JSONEncoder.defaultEncoder`/`JSONDecoder.defaultDecoder`, whose date strategy is `.formatted(DateFormatter.JSONDateTimeFormatter)` = `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` (ms precision), exactly as every other `Date` in the system. `Freshness` adds no per-type strategy. **Precision caveat for tests:** because the canonical form is millisecond-precision, a *freshly created* `Freshness` (sub-ms `.now`) is **not** exactly equal to itself after a round-trip. So the tests start from a **canonical 2020 payload** (already ms) and compare by **ordering equivalence** (`!(a < b) && !(b < a)`), never by an in-memory `Date` equality across a round-trip and never by inspecting the encoded string.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ViewModelIdFreshnessTests`
Expected: PASS. Also re-run the versioned suite to confirm lenient decode keeps existing baselines green **without regeneration**:

Run: `swift test --filter VersionedViewModelTests`
Expected: PASS (no baseline files changed).

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/ViewModelId.swift Tests/FOSMVVMTests/Identity/ViewModelIdFreshnessTests.swift
swiftlint --path Sources/FOSMVVM/Protocols/ViewModelId.swift
git add Sources/FOSMVVM/Protocols/ViewModelId.swift Tests/FOSMVVMTests/Identity/ViewModelIdFreshnessTests.swift
git commit -m "feat(FOSMVVM): add orthogonal ViewModelId.Freshness version clock"
```

---

## Task 6: `ModelIdentity.viewModelId` — the rendering-identity bridge

Depends on: Tasks 2 and 3 (`ModelIdentity` + the `TestWidget`/`TestGadget` fixtures). **Does not** touch `ViewModelId.swift` — the derivation lives on the *owner* of the sealed data, so `ViewModelId` never needs to know `ModelIdentity` exists, and there is exactly **one** spelling of "give me the vmId": `modelIdentity.viewModelId`.

**Files:**
- Modify: `Sources/FOSMVVM/Protocols/ModelIdentity.swift`
- Create: `Tests/FOSMVVMTests/Identity/ModelIdentityViewModelIdTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ModelIdentityViewModelIdTests.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

struct ModelIdentityViewModelIdTests {
    // Group 5: vmId derivation — stable & equal for equal identities, distinct for distinct.
    @Test func vmIdIsStableForEqualIdentities() throws {
        let uuid = UUID()
        let a = try TestWidget(id: uuid).modelIdentity.viewModelId
        let b = try TestWidget(id: uuid).modelIdentity.viewModelId
        #expect(a == b)
    }

    @Test func vmIdDiffersForDistinctIdentities() throws {
        let a = try TestWidget(id: UUID()).modelIdentity.viewModelId
        let b = try TestWidget(id: UUID()).modelIdentity.viewModelId
        #expect(a != b)
        // Namespace participates: same UUID under a different namespace ⇒ different vmId.
        let uuid = UUID()
        let w = try TestWidget(id: uuid).modelIdentity.viewModelId
        let g = try TestGadget(id: uuid).modelIdentity.viewModelId
        #expect(w != g)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelIdentityViewModelIdTests`
Expected: FAIL — `value of type 'ModelIdentity' has no member 'viewModelId'`.

- [ ] **Step 3: Add the owner-scoped computed to `ModelIdentity.swift`**

```swift
public extension ModelIdentity {
    /// A stable ``ViewModelId`` derived from this identity. Bind your ViewModel's `vmId` to it so
    /// SwiftUI keeps the view stable as the model's data changes:
    ///
    /// ```swift
    /// self.vmId = try user.modelIdentity.viewModelId
    /// ```
    var viewModelId: ViewModelId {
        .init(id: "\(namespace.rawValue)|\(id.uuidString)")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelIdentityViewModelIdTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/ModelIdentity.swift Tests/FOSMVVMTests/Identity/ModelIdentityViewModelIdTests.swift
swiftlint --path Sources/FOSMVVM/Protocols/ModelIdentity.swift
git add Sources/FOSMVVM/Protocols/ModelIdentity.swift Tests/FOSMVVMTests/Identity/ModelIdentityViewModelIdTests.swift
git commit -m "feat(FOSMVVM): add ModelIdentity.viewModelId rendering-identity bridge"
```

---

## Task 7: `ModelIdentifiedViewModel` — opt-in protocol

Depends on: Tasks 3, 4, 6 (its idiomatic conformance uses `Model.modelIdentity`, `modelIdentity.viewModelId`, and `== some Model`).

**Files:**
- Create: `Sources/FOSMVVM/Protocols/ModelIdentifiedViewModel.swift`
- Test: `Tests/FOSMVVMTests/Identity/ModelIdentifiedViewModelTests.swift`

- [ ] **Step 1: Write the failing test** (hand-written conformance — the `.live` macro synthesizes this in L2)

```swift
// ModelIdentifiedViewModelTests.swift  (Apache 2.0 header added by swiftformat)
import FOSFoundation
import FOSMVVM
import Foundation
import Testing

@ViewModel
private struct WidgetViewModel: RequestableViewModel, ModelIdentifiedViewModel, Hashable {
    typealias Request = WidgetViewModelRequest
    @LocalizedString var title
    let vmId: ViewModelId
    let modelIdentity: ModelIdentity

    init(widget: TestWidget) throws {
        let identity = try widget.modelIdentity
        self.modelIdentity = identity
        self.vmId = identity.viewModelId
    }
    static func stub() -> Self { try! .init(widget: TestWidget()) }
}

private final class WidgetViewModelRequest: ViewModelRequest, @unchecked Sendable {
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    let query: EmptyQuery?
    var responseBody: WidgetViewModel?
    init(query: EmptyQuery? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: WidgetViewModel? = nil) {
        self.query = query
        self.responseBody = responseBody
    }
}

struct ModelIdentifiedViewModelTests {
    @Test func exposesModelIdentityRootedInTheModel() throws {
        let widget = TestWidget()
        let vm = try WidgetViewModel(widget: widget)
        #expect(vm.modelIdentity == widget)
        #expect(try vm.vmId == widget.modelIdentity.viewModelId)
    }
}
```

> Note: if `EmptyQuery` is not the correct empty-query witness in this repo, mirror the request scaffolding in `Tests/FOSMVVMTests/TestViewModel.swift` (which uses a concrete `TestQuery`); the exact request plumbing is incidental to what this test asserts. `EmptyQuery`/`EmptyBody`/`EmptyFragment` are expected to exist.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelIdentifiedViewModelTests`
Expected: FAIL — `cannot find type 'ModelIdentifiedViewModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ModelIdentifiedViewModel.swift  (Apache 2.0 header added by swiftformat)
import Foundation

/// A ``ViewModel`` that knows *which* ``Model`` instance it projects.
///
/// Conform when a ViewModel represents a specific entity — a user, a document, a list row — so the
/// framework can key identity-based behavior (e.g. live refresh) to it. Singleton or ephemeral
/// ViewModels don't conform and keep only ``ViewModel/vmId``.
///
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
public protocol ModelIdentifiedViewModel: ViewModel {
    var modelIdentity: ModelIdentity { get }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelIdentifiedViewModelTests`
Expected: PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
swiftformat Sources/FOSMVVM/Protocols/ModelIdentifiedViewModel.swift Tests/FOSMVVMTests/Identity/ModelIdentifiedViewModelTests.swift
swiftlint --path Sources/FOSMVVM/Protocols/ModelIdentifiedViewModel.swift
git add Sources/FOSMVVM/Protocols/ModelIdentifiedViewModel.swift Tests/FOSMVVMTests/Identity/ModelIdentifiedViewModelTests.swift
git commit -m "feat(FOSMVVM): add opt-in ModelIdentifiedViewModel protocol"
```

---

## Task 8: Full-suite verification, CHANGELOG, and opacity review invariant

Depends on: Tasks 1–7. No new behavior — this is the gate. Follow @superpowers:verification-before-completion (evidence before claims).

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Green build + full test across all targets**

```bash
swift build
swift test
```
Expected: build succeeds; all tests pass (including the pre-existing `VersionedViewModelTests` with **no** baseline changes). If any dependent target (FOSMVVMVapor, FOSTesting, FOSTestingVapor, FOSReporting, FOSTestingUI) fails to compile against the `Model`/`ViewModelId` changes, fix the call site — but a *new symbol* break there is unexpected (the `Model` change is additive; only a stray `modelType` reference would break, and the grep in Task 3 proved there are none).

- [ ] **Step 2: Format + lint the whole tree**

```bash
swiftformat .
swiftlint
```
Expected: clean (no diagnostics). Re-stage and amend the last commit if swiftformat touches anything.

- [ ] **Step 3: Opacity review invariant (manual, not a runtime test — spec test group 6)**

Confirm by reading the three new source files:
- No **public** API returns the underlying `String`/`UUID`/namespace of `ModelNamespace`, `ModelIdentity`, or `ViewModelId.Freshness`. `ModelNamespace.rawValue` is `internal` (its one cross-type accessor); `ModelIdentity.viewModelId` vends an opaque `ViewModelId`, not a raw token string; `timestamp` is `private` and `Freshness.init()` is non-`public`.
- **No public surface publishes the internal representation.** No DocC comment, CHANGELOG line, or README states an opaque type's encoded shape (`{"namespace":…}`, `"ns|uuid"`, field names/order). The encoded shape appears **only** in internal `//` maintainer comments and internal test fixtures. Public docs state the contract (opaque, round-trips, stable within a major version), never the shape.
- **No test uses `@testable` or reads private/internal components.** Every identity test exercises only the public contract (mint via `model.modelIdentity`; assert via `==`/`hashValue`/`Comparable`/`Codable` round-trip). `@testable` is reserved for block/arc *coverage*, never contract coverage — and L0's contract tests need none.
- `ViewModelId` declares **no** `Comparable`/`<`.
- No `CustomStringConvertible`/`CustomDebugStringConvertible` was added to any opaque type (deferred), and nothing string-interpolates them.

Record the check in the commit message.

- [ ] **Step 4: Write the CHANGELOG entry**

Under `## [Unreleased]`, add:

```markdown
### Added

- **`ModelIdentity`** — a sealed, opaque, non-generic identity rooted in a `Model`'s stable id
  (`Hashable`/`Codable`/`Sendable`), with `ModelNamespace` (minted only from a type, never a raw
  string), `Model.modelIdentity` / `Model.modelIdentityNamespace`, the opt-in
  `ModelIdentifiedViewModel` protocol, `ModelIdentity.viewModelId`, and `ModelIdentity == some Model`
  filtering sugar. Treat the value as opaque — its encoded form is version-stable and round-trips, and
  changes only on a library major version; do not parse or hand-construct it.
- **`ViewModelId.Freshness`** — an opaque, order-only version clock (a canonical-GMT birth moment)
  carried on every `ViewModelId` under the short wire key `fsh`. Orthogonal to identity: `==`/`hash`
  stay `id`-only and `ViewModelId` is deliberately not `Comparable`.

### Removed

- **BREAKING: `Model.modelType`** — the dormant, unused, stringly-typed namespace is removed in favor
  of the opaque `ModelNamespace`. Downstream code referencing `modelType` migrates to
  `modelIdentityNamespace`.
```

- [ ] **Step 5: Final verification + commit**

```bash
swift build && swift test
git add CHANGELOG.md
git commit -m "docs(CHANGELOG): record Layer 0 model-identity foundation

Verified: swift build + swift test green across targets; swiftformat/swiftlint
clean; opacity review invariant holds (no public getters, ViewModelId not Comparable)."
```

---

## Definition of Done (from the spec)

- All **7 runnable test groups** pass (namespace default/override; identity equality/hash; `== some Model`; Codable round-trip + golden-blob forward-compat; vmId derivation; throwing path; freshness) **and** the opacity review invariant holds (including: no public surface publishes the encoded shape).
- `swift build` + `swift test` green across FOSMVVM and dependent targets; `swiftformat`/`swiftlint` clean.
- Adding `ViewModelId.freshness` did **not** change `==`/`hash`/`.id()` (identity stays `id`-only); existing versioned baselines stay green **without regeneration** (lenient decode; client-hosted VMs are skipped by the harness).
- No public API exposes the underlying namespace/id/timestamp (review invariant).
- CHANGELOG entry written; DocC lives in the new types' doc comments.

## Deferred (do NOT build in Layer 0)

`Container`/load engine/registry (L1); SSE/dispatcher/`.live` macro/emit (L2); the debug/log accessor + `CustomStringConvertible` for the opaque types (tracked follow-up); the freshness **producer** (server stamping) and **consumer** (drop-stale gate) — L2 adds behavior only, no format change. No macro work here (`ModelIdentifiedViewModel` conformance is hand-written).
