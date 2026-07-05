# Layer 0 — Model Identity Foundation (Design Spec)

**Status:** Ready for plan.
**Date:** 2026-07-03
**Layer:** 0 of 3 (see `2026-07-03-live-viewmodel-invalidation-architecture.md`).
**Targets:** FOSMVVM (primary). No FOSMVVMVapor / FOSMacros changes in this layer.
**Depends on:** nothing new. **Blocks:** Layer 1 (container), Layer 2 (live).

## Purpose

Introduce a **sealed, opaque, value-comparable identity** rooted in a data `Model`'s stable id,
surfaced through an opt-in ViewModel protocol and bound to `ViewModelId`. This is the primitive
every later layer keys on (nudge routing, container membership, authorization). It is independently
valuable **without** any live/container machinery: it stabilizes SwiftUI identity and gives a
single, typed source of truth for "which entity is this ViewModel a projection of."

Non-negotiable property: **no Swift API on the client exposes the identity's contents.** It is
minted only from a typed `Model`, vends only `Hashable`/`Equatable`/`Codable`/`Sendable`, and is
consumed by comparison/hashing/coding alone. (This is a *Swift-surface* guarantee — the persisted /
wire `Codable` form is, necessarily, plaintext JSON the server and tests can read. Opacity means
"no accessor," not "obfuscated bytes"; no encryption of the wire form is implied.)

## Scope (what ships in Layer 0)

1. `ModelNamespace` — opaque namespace token.
2. `ModelIdentity` — opaque, non-generic, sealed identity (namespace + canonical id).
3. `Model` changes — add `modelIdentityNamespace` requirement + default and `modelIdentity` computed;
   **remove** the dormant `modelType` requirement/members (David's decision — see reconciliation).
4. `ModelIdentity.viewModelId` — an owner-scoped computed that derives the rendering identity from the
   identity (no redundant `ViewModelId.init(modelIdentity:)`).
5. `ModelIdentifiedViewModel` — opt-in ViewModel protocol exposing `modelIdentity`.
6. `ModelIdentity == some Model` — convenience comparability (filtering sugar).
7. Version-stable `Codable` for `ModelIdentity` (it is a **persistence** format, not only wire).
8. **Freshness dimension on `ViewModelId`** — add a **nested** `ViewModelId.Freshness` (opaque,
   `Comparable` + `Codable`, hiding `Date` semantics; scoped to `ViewModelId`, not top-level) and a
   total, immutable `let freshness: Freshness` on `ViewModelId`, set
   **per-init** (`Freshness()` = **`.now`**, the birth moment, in `init(id:)`; the decoded wire moment,
   *preserved* not re-stamped, in `init(from:)`) — not a declaration default (a `let` default can't be
   overridden by decode). No optional, no sentinel/baseline, no `init(id:timestamp:)` seam.
   `ViewModelId` does **not** become `Comparable`; `==`/`hash`/`.id()` stay `id`-only. Freshness is
   **always encoded** (canonical GMT); it is **excluded from version-baseline comparison** (birth moment
   isn't part of the data-version contract).
   **Encode freshness on the wire in L0** — canonical GMT Date, **always present** (every VM has a real
   birth moment; there is no "default" to omit against) — freezing the durable wire contract now
   (pre-1.0). The *producer* (server stamping) and *gate* (consumer) are Layer 2. (Rationale below.)
   **Wire-key nomenclature:** the field is `ViewModelId.freshness` of type `ViewModelId.Freshness`; the
   dead `timestamp`/`ts` naming is gone. Its JSON key is deliberately **short** (`fsh`) *only* because
   `ViewModelId` is embedded in every streamed ViewModel and byte-count matters at this level — this is
   a scoped exception, **not** a mandate to abbreviate ViewModel keys (those keep standard `Codable`).
9. Tests for all of the above.

## Non-goals (explicitly deferred)

- `Container`, `ContainerCardinality`, `ContainerOperation`, the load engine, filter/sort, the
  server `ModelNamespace → Model.Type` registry → **Layer 1**.
- SSE transport, `InvalidationChannel`, dispatcher, `ModelMiddleware` emit, `.bind()` wiring,
  `@ViewModel(options: [.live])` macro, hardening the existing invalidation seam → **Layer 2**.
- No macro work in this layer. `ModelIdentifiedViewModel` conformance is **hand-written** in L0;
  the `.live` macro synthesizes it in L2.
- **No logging/debug accessor** (David's call — defer). No `CustomStringConvertible`/
  `CustomDebugStringConvertible` and no swift-log/OTel extensions in L0; these are a tracked
  follow-up. Consequence to respect meanwhile: don't string-interpolate these opaque values (Swift's
  default `Mirror` would dump the private field). The redacted-description + logging channel lands
  with that follow-up.

## Types & placement

All new types live in FOSMVVM alongside the existing identity types
(`Sources/FOSMVVM/Protocols/`). `Model` is FOSMVVM (`Protocols/Model.swift`); `ViewModelId` is
FOSMVVM (`Protocols/ViewModelId.swift`); `ModelIdType = UUID` is FOSFoundation.
`ViewModelId.Freshness` is **nested in `ViewModelId`** (lives in `ViewModelId.swift`, not its own
file — it is a sub-contract of `ViewModelId`, not a standalone type).

> Placement note for the plan: `ModelNamespace` has no FOSMVVM dependency (only `Any.Type` +
> `String`) and *could* live in FOSFoundation. Default to FOSMVVM for cohesion with `Model`; only
> promote to FOSFoundation if a concrete reuse appears. Decide in the plan, don't pre-optimize.

**Family coherence (intentional).** The opaque value types here share one deliberate shape:
`ModelNamespace`, `ModelIdentity`, and `ViewModelId.Freshness` are each **sealed** (private storage,
no public getter — a debug/log channel is deferred), conform to exactly `Hashable`/`Codable`/`Sendable`
(+ `Comparable` where ordering is the contract), and are constructed **only from their two real
sources** — *minted/declared* (`.init(for:)` / `Model.modelIdentity` / `Freshness()`) and *from the
wire* (`Codable init(from:)`). No type carries a constructor, option, or sentinel without a named
source or consumer. Keep new identity types to this shape.

### `ModelNamespace` (`Protocols/ModelNamespace.swift`)

```swift
public struct ModelNamespace: Hashable, Sendable {
    private let value: String                     // sealed — NO public getter, NO public String init
    internal var rawValue: String { value }       // module-private — for derivation only
    public init(for type: Any.Type) { value = String(reflecting: type) }
}

// Explicit single-value Codable — persists/transmits as a bare string ("User"), NOT {"value":"User"}.
// The encoded shape is a FROZEN persistence format (see ModelIdentity); pin it here.
// init(from:) is the ONLY string→ModelNamespace path, and it is decode-internal, not a public API.
extension ModelNamespace: Codable {
    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(value)
    }
}
```

- **No public String surface.** The *only* public construction is `init(for: Any.Type)` — a `Type`
  in, never a `String`. `ExpressibleByStringLiteral` is deliberately **omitted**: it would add a
  public, runtime-callable `init(stringLiteral: String)` (`ModelNamespace(stringLiteral: someVar)`) —
  exactly the "mint a namespace from an arbitrary string" leak to prevent. The string only ever
  lives inside the box (computed by `init(for:)` or read by `init(from:)`); nothing lets a caller
  put one in or read one out.
- `String(reflecting:)` (module-qualified) — avoids cross-module collision; do **not** use
  `String(describing:)`.
- `rawValue` is **`internal`** — used solely by `ModelIdentity` token derivation within FOSMVVM;
  never public. (`private` alone is insufficient: `ModelIdentity` is a separate file, and `private`
  is file-scoped.)
- **Explicit single-value `Codable`** so the persisted `ModelIdentity` shape is
  `{"namespace":"User","id":"…"}`, not `{"namespace":{"value":"User"},"id":"…"}`. The synthesized
  form would freeze a `"value"` key as a persistence detail; the single-value container avoids it.

**Refactor-stability without a String.** A Model needing a rename-proof token overrides
`modelIdentityNamespace` by anchoring to a dedicated **stable marker type**, not a literal:

```swift
enum UserIdentity {}   // never renamed; its sole job is to anchor the namespace token
public extension User {
    static var modelIdentityNamespace: ModelNamespace { .init(for: UserIdentity.self) }
}
```

Renaming `User` no longer shifts the token (it is anchored to `UserIdentity`). Residual limit: the
token embeds `String(reflecting:)` = `"Module.UserIdentity"`, so a **module** rename/move still shifts
it — acceptable for a stable domain module; there is no String-literal escape hatch (by design).

**Deferred (follow-up, not Layer 0):** a controlled `CustomStringConvertible`/`CustomDebugStringConvertible`
and swift-log/OTel logging extensions. Until then, **do not string-interpolate `ModelNamespace`/`ModelIdentity`** —
Swift's default `Mirror` would dump the private `value`. The redacted/debug channel is intentionally
future work (tracked, not forgotten).

### `ModelIdentity` (`Protocols/ModelIdentity.swift`)

```swift
public struct ModelIdentity: Hashable, Codable, Sendable {
    private let namespace: ModelNamespace
    private let id: ModelIdType                   // the Model's id (UUID); sealed — stored as its real type

    // Mintable only within FOSMVVM (via Model.modelIdentity). No public raw-string init.
    internal init(namespace: ModelNamespace, id: ModelIdType) {
        self.namespace = namespace
        self.id = id
    }
}

public extension ModelIdentity {
    // Compare an identity to a live Model. NOT Equatable conformance — a heterogeneous operator
    // overload, sugar for `models.filter { changed == $0 }`. Intentionally shipped in L0 (David):
    // the foundational identity-comparison primitive; its first consumers are L1 (container
    // auth-by-identity-equality, dispatcher filtering) — kept in the foundation deliberately, not unused.
    static func == (lhs: ModelIdentity, rhs: some Model) -> Bool {
        (try? lhs == rhs.modelIdentity) ?? false
    }
}
```

- **Non-generic** (see north star §3), and stores the **real `ModelIdType` (`UUID`)** — not a
  pre-stringified `String`. `ModelIdType` *is* `UUID`, so there is no representation to keep "agnostic";
  it stringifies only at the two boundaries that need text: `Codable` (wire) and `viewModelId` (vmId).
- `internal init` ⇒ external modules (client apps, FOSMVVMVapor) cannot mint arbitrary identities;
  they obtain one via `Model.modelIdentity` (server) or `Codable` decode (client).
- **Codable is a frozen persistence format — but the shape is a *library-internal* invariant, not a
  published contract.** Pin `CodingKeys` (`namespace`, `id`) permanently; changing them breaks stored
  DB values (L1 persists identities in columns — e.g. an authorization record storing the container it
  authorizes). **No on-the-wire versioning** (OQ-1, resolved): a breaking change to this encoding is a
  **library major-version** bump (semver), nothing finer — do not add per-field or `SystemVersion`
  negotiation. Combined with `ModelNamespace`'s single-value `Codable`, the encoded shape is
  `{"namespace":"<token>","id":"<uuid>"}` — **but that shape must NOT appear on any public surface**
  (DocC, CHANGELOG, README). Publishing it would make it a de-facto schema consumers parse or forge,
  defeating the opacity. The **public** doc states only the *contract*: opaque; `Codable` round-trips;
  stable within a major version; do not parse or hand-construct. The shape lives in an **internal `//`
  maintainer comment** beside `CodingKeys` and is guarded by a **forward-compat** test (a committed
  golden blob still decodes and round-trips) — *that* is the real contract ("stored data keeps
  loading"), not "encode emits these exact keys."
- Rendering-identity bridge: a single **owner-scoped** `public var viewModelId: ViewModelId` (see its
  own section below), built from `ModelIdentity`'s **own** private fields
  (`.init(id: "\(namespace.rawValue)|\(id.uuidString)")`). It **vends a `ViewModelId`, never the raw
  token string** — so no caller can grab the token and parse the sealed contents back out; there is
  **no** `renderingToken` accessor. This is a *rendering* token (SwiftUI/`vmId`), **not** the persisted
  `Codable` form, so a compact string is fine here (unlike the frozen identity encoding). The one
  cross-type accessor it needs is `ModelNamespace.rawValue` (internal), because the namespace's string
  lives in a different type.

### `Model` additions (`Protocols/Model.swift`)

```swift
public protocol Model {
    // ...existing (var id: ModelIdType? { get }, requireId() throws -> ModelIdType, ...)...
    static var modelIdentityNamespace: ModelNamespace { get }   // requirement (overridable)
}

public extension Model {
    static var modelIdentityNamespace: ModelNamespace { .init(for: Self.self) }   // default
    var modelIdentity: ModelIdentity {
        get throws { try .init(namespace: Self.modelIdentityNamespace, id: requireId()) }
    }
}
```

- Requirement **+** default is deliberate: the default gives zero-config; a Model overrides by
  anchoring to a **stable marker type** (`.init(for: UserIdentity.self)`) to pin a **refactor-stable**
  token. Extension-only would only shadow (override wouldn't dispatch through `Model`).
- **`get throws`** because `requireId()` throws when `id == nil` (unpersisted). Callers that need a
  non-throwing path can guard on `id != nil` first.
- Adding a requirement with a default is source-compatible: existing conformers get the default and
  keep compiling.
- **Do NOT mark `modelIdentity` `@inlinable`.** Its body calls `ModelIdentity`'s `internal init`,
  reachable *only* because both are same-module and the property is not inlinable. `@inlinable`
  would break the build.

#### Reconciliation with the existing `Model.modelType` — REMOVE (David's decision)

`Model` **already** declares `static var modelType: String` + instance `modelType`, defaulting to
`String(describing: Self.self)` (`Model.swift:27,51,55`). It is **`@inlinable`, stringly-typed,
uses the unqualified `describing:` form (collision-prone), and has zero usages anywhere in
`Sources/`** — the exact stringly-typing this design replaces, sitting dormant.

**Decision (David): remove `modelType` entirely** — "this code isn't used broadly, so let's get it
right." Rationale: it is unused in-repo, and keeping a collision-prone stringly namespace alongside
the opaque `ModelNamespace` invites exactly the conflation we want to forbid.

Plan notes for the removal:
- Delete the `static var modelType`/instance `modelType` requirement + defaults from `Model.swift`.
- Verify no in-repo caller (`grep` confirmed zero in `Sources/`); `ModelError.missingId` uses
  `String(describing: Self.self)` **directly**, not the property, so it is unaffected.
- It is a **public-API removal** — note it in the CHANGELOG as a breaking change for any downstream
  that referenced `modelType` (they migrate to `modelIdentityNamespace`).
- `modelType` is a computed (not stored) member, so it is **not** part of `Model`'s `Codable`
  synthesis — removing it does not change any wire/persisted form.

**Spec guidance (carry into docs/skills):** *any Model whose `modelIdentity` is persisted or is a
long-lived wire contract SHOULD anchor its `modelIdentityNamespace` to a dedicated stable marker type*
(`.init(for: UserIdentity.self)`), so a future rename of the Model type cannot silently change the
stored/transmitted token.

### `ModelIdentity.viewModelId` (`Protocols/ModelIdentity.swift`)

The rendering-identity bridge is a computed on **`ModelIdentity`** (the owner of the sealed data), not
an initializer on `ViewModelId`. There is exactly **one** spelling — `modelIdentity.viewModelId` — and
`ViewModelId` stays unaware that `ModelIdentity` exists (correct dependency direction: rendering derives
*from* identity, not vice-versa).

```swift
public extension ModelIdentity {
    /// The stable SwiftUI rendering identity (`vmId`) for a ViewModel projected from this model.
    var viewModelId: ViewModelId {
        .init(id: "\(namespace.rawValue)|\(id.uuidString)")
    }
}
```

- Binds `vmId` to `modelIdentity` so the typed identity is authoritative and the opaque rendering
  identity falls out of it (replaces the pattern where a Factory unwrapped `user.id` and passed the
  bare `UUID` to `ViewModelId(id:)`, erasing both the entity type and any namespace).
- **No `ViewModelId.init(modelIdentity:)` initializer** — that would be a redundant second spelling of
  the same operation (the "no two ways to do one thing" rule). The single owner-scoped computed is it.
- Non-throwing: the derivation is pure string interpolation of already-in-hand values (no `Codable`),
  so binding a `vmId` doesn't add a `throws` to call sites beyond the `try` they already do for
  `model.modelIdentity`.

#### Freshness dimension — a `Freshness` value on `ViewModelId`, orthogonal to identity

`ViewModelId` today declares `case timestamp = "ts"` in its `CodingKeys` (`ViewModelId.swift:122`)
but **never reads or writes it** — a dormant freshness field, like `Model.modelType` was a dormant
namespace. L0 **replaces** that dormant case with a live `case freshness = "fsh"` (the `timestamp`/`ts`
name is a holdover from a previous impl and is gone; the JSON key stays short — `fsh` — only because
`ViewModelId` is embedded in every streamed ViewModel and byte-count matters here). Layer 2's live path
needs it: when a nudge triggers a re-fetch and refreshes race (a slow re-fetch landing after a newer
push; two nudges in flight), the client must **drop the stale copy** — a monotonic gate
(`if incoming.freshness <= existing.freshness → drop`).

`ViewModelId` carries **two orthogonal roles**:

| Role | Backed by | Exposed as |
|---|---|---|
| **Entity identity** (routing, SwiftUI `.id()` stability) | the stable `id` string (from `modelIdentity`) | `==`, `hash` (both `id`-only, unchanged) |
| **Freshness** (which copy wins) | an opaque `Freshness` | `let freshness: Freshness` (a separate `Comparable` value; `ViewModelId` itself is not `Comparable`) |

**`ViewModelId` does NOT conform to `Comparable`.** Making `<` order by `timestamp` while `==`
compares `id` would violate `Comparable`'s strict-total-order law (`a == b` yet `a < b`), a latent
footgun (`sort`/`min`/`max` misbehave) the prior art shipped. Instead the ordering lives on a
dedicated value:

```swift
public struct ViewModelId {           // existing type gains one field + its own nested sub-type:
    // ...existing id / isRandom...
    public let freshness: Freshness    // its birth moment — `.init()` (now) in init(id:), decoded in init(from:)

    // Scoped to ViewModelId (NOT a general-purpose contract). An opaque, ORDER-ONLY version clock:
    // hides Date's semantics (no arithmetic/calendar/formatting/"compare to now"); vends only
    // Comparable + its ViewModelId-specific single-value Codable. Same sealing discipline as ModelNamespace.
    public struct Freshness: Comparable, Sendable {
        private let timestamp: Date                 // internal; canonical GMT on the wire
        init() { timestamp = .now }                 // the only explicit init: birth moment
        public static func < (l: Freshness, r: Freshness) -> Bool { l.timestamp < r.timestamp }
        // No Date accessor. (Debug/log readout deferred, like ModelNamespace.)
    }
}

// Single-value Codable — a bare canonical GMT date on the wire (frozen contract);
// init(from:) IS the "preserve the wire moment" path — no separate Date initializer needed.
extension ViewModelId.Freshness: Codable {
    public init(from d: Decoder) throws { timestamp = try d.singleValueContainer().decode(Date.self) }
    public func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(timestamp) }
}
```

**`Freshness` is an opaque semantic contract, not a `Date`.** It is functionally a `Date` but
semantically not: a version clock vends *only* ordering, never `Date`'s arithmetic/calendar/formatting
surface (all meaningless-and-misusable for freshness). This is the same discipline as `ModelNamespace`
hiding `String`. `Date` (not an opaque `Int`) is the internal representation specifically so the
**deferred** debug/log channel can later render a human-readable instant via a controlled
`debugDescription` — never an exposed `Date`.

**The default is birth-time (`.now`), and it is *preserved*, not re-stamped.** Every `ViewModelId`
*always has* a real `freshness` — its creation moment. There is **no "unstamped" sentinel** (no
`distantPast`, no baseline): a locally-born VM's freshness is simply *now*; a decoded VM's freshness is
the moment the **producer** wrote it, carried on the wire and reconstructed via `Freshness`'s own
`Codable` `init(from:)` — decode **never** re-stamps to the client's `.now`. That preservation is what makes the drop-stale gate order
by *birth* time regardless of arrival order (a reordered older response still has the older freshness and
loses). `freshness` is a plain immutable `let` set **per-init**, not a declaration default (a `let`
default couldn't be overridden by `init(from:)`).

**Layer 0 scope — the freshness dimension, wire contract included:**

- Add the `Freshness` type + a total, immutable `let freshness: Freshness` on `ViewModelId`, assigned
  **per-init** (`.init()` = `.now` in `init(id:)`; the decoded wire moment in `init(from:)`; delegating
  inits inherit). `==`/`hash`/`.id()` stay **`id`-only and unchanged** — two versions of one entity
  remain equal (stable SwiftUI identity) while orderable via `freshness`. `ViewModelId` is **not**
  `Comparable`.
- **Encode freshness in L0 — always present** (every VM has a real birth moment; there is no default to
  omit against). `Freshness`'s own `Codable` encodes its `Date` through FOSMVVM's **canonical GMT**
  date encoding, under the short key `fsh` — the freshness field is now a **frozen wire contract**.
- **Consequence — freshness is not part of the data-*version* contract.** Because freshness = birth
  moment, it varies per instance. In practice this needs **no test-infra change**: `expectCodable`
  (encode→decode→encode round-trip) preserves the value and is unaffected, and `expectVersionedViewModel`
  is **decode-only** (it stores a baseline once, then only re-decodes stored baselines — it never
  encode-diffs, so there is nothing to "ignore"). It also **skips `ClientHostedViewModelFactory`**
  types, and every client to date is client-hosted. Lenient decode (below) keeps all existing baselines
  green **without regeneration**; a legacy baseline lacking `fsh` simply decodes to a birth moment of
  "now." No baseline churn, no comparison surgery.

**Deferred to Layer 2** (behavior, not format — the wire contract is frozen here in L0): the
**producer** (the server assigns `freshness` at resolve/encode-time — its birth moment for that
version), the **consumer** (the drop-stale gate, `incoming.freshness <= existing.freshness → drop`),
and the stamping *policy*. The clock is **GMT `Date`** (no timezone handling). L0 delivers the opaque
orderable type **and** the durable wire form; L2 makes it flow and gate.

### `ModelIdentifiedViewModel` (`Protocols/ModelIdentifiedViewModel.swift`)

```swift
public protocol ModelIdentifiedViewModel: ViewModel {
    var modelIdentity: ModelIdentity { get }
}
```

- Opt-in. Singleton/ephemeral ViewModels do not conform and keep only `vmId`.
- L0 conformance is hand-written (a Factory sets `modelIdentity` from a `Model`); L2's macro
  synthesizes it.

## Testing (Swift Testing; follow repo conventions)

**7 runnable test groups + 1 review invariant** (group #6 below is a static/review invariant, not an
executable assertion — the DoD counts it separately). Use the direct primitives / repo patterns. Cover:

1. **Namespace default vs override** — a Model with no declaration gets `String(reflecting:)`; a Model
   declaring a literal overrides it (dispatch through `Model.self`, not just the concrete type).
2. **Identity equality/hash** — same `(namespace, id)` ⇒ equal & equal hash; **same UUID + different
   namespace ⇒ unequal** (proves namespace participates and a type rename/collision can't alias).
3. **`== some Model`** — `identity == model` true when rooted in that model's id; false for a
   different id; false for an unpersisted model (`id == nil`, no throw escaping).
4. **Codable round-trip + forward-compat (contract, not representation)** — two internal tests:
   (a) encode→decode is identity-preserving (`back == original`); (b) a **committed golden blob** (an
   inline JSON fixture with a *fixed* namespace string — `ModelNamespace.init(from:)` accepts any
   string, so the fixture is decoupled from any marker type's reflected name and never churns) still
   **decodes and round-trips byte-for-byte**, so a `CodingKey` rename/removal (which silently breaks
   stored DB data) fails the test. This guards the frozen format as a *contract* ("stored data keeps
   loading") **without** asserting the current encode bytes and **without** publishing the shape — the
   golden blob is the single internal home for the encoded form. Do **not** write a test that asserts
   `encode(x)` equals a specific `{namespace,id}` shape on a public surface, and do **not** restate the
   shape in DocC (see the Codable bullet above).
5. **`vmId` derivation** — `modelIdentity.viewModelId` is stable and equal for equal identities;
   distinct for distinct identities.
6. **Opacity (review invariant, not a runtime test)** — `private let`/`internal rawValue` make this
   compiler-guaranteed; there is nothing to assert at runtime and no `@testable` check strengthens
   it. Verified by review: no *public* API returns the underlying `String`/namespace, and no test
   reads raw components. (Counted separately from the 6 runnable groups in the DoD.)
7. **Throwing path** — `model.modelIdentity` throws for `id == nil`; does not crash.
8. **Freshness (`ViewModelId`)** — cover, **through the public contract only** (the `freshness`
   property, `Freshness`'s `Comparable`, `ViewModelId`'s `==`/`hashValue`, and the repo
   `toJSON()`/`fromJSON()` helpers). **No `@testable`, no reaching into private `id`, and no inspecting
   the raw encoded JSON** — the `fsh` key name/format is representation, not contract, so it is never
   asserted. Use a canonical 2020 payload as the "old wire moment" fixture and compare by *ordering*
   (which sidesteps the millisecond-precision caveat of a freshly-created `Freshness`):
   - **Ordering** — `let a = ViewModelId(id: "x").freshness; <tiny sleep>; let b = ViewModelId(id: "y").freshness;
     #expect(a < b)`. Public `freshness` + `Comparable`; the drop-stale *gate* is L2.
   - **Identity excludes freshness** — a born-now vmId and one decoded from the same `id` with an old
     freshness are **`==` / equal-hash** (asserted via public `==`/`hashValue`), yet their `freshness`
     values order correctly.
   - **Not Comparable** — assert `ViewModelId` has no `<` (compile-level / review check).
   - **Wire preserves, doesn't re-stamp** — decode a canonical 2020 payload; its `freshness` orders
     **before** a fresh `ViewModelId(id:).freshness`, proving decode kept the wire moment.
   - **Freshness survives the wire** — round-trip a canonical payload (`try original.toJSON().fromJSON()`);
     the `freshness` is **ordering-equivalent** to the original (`!(a<b) && !(b<a)`). This proves it is
     both encoded and preserved — behavior, never a byte/key-shape assertion.
   - **Lenient decode** — a payload lacking `fsh` decodes without throwing and equals the same vmId
     minted locally (public `==`).
   - **Not part of the version contract** — needs **no** test-infra change (see the freshness section):
     `expectVersionedViewModel` is decode-only and `expectCodable` preserves the value.

## Risks & mitigations

- **Adding a `Model` requirement** could in theory break an exotic conformer that already declares a
  clashing `modelIdentityNamespace`. Mitigation: the name is new and specific; the default makes it
  additive. Verify a full `swift build`/`swift test` across targets in the plan.
- **Persistence-format lock-in.** Once `ModelIdentity.Codable` is used for a stored column (L1),
  its shape is frozen. Mitigation: pin `CodingKeys` now, add the golden fixture test, and document
  the explicit-namespace guidance before L1 persists anything.
- **`get throws` ergonomics** ripple to call sites. Mitigation: acceptable — mirrors existing
  `requireId()`; provide the `id != nil` guard pattern in docs.

## Definition of done

- All **7 runnable test groups** pass and the opacity review invariant holds; `swift build` +
  `swift test` green across FOSMVVM (+ dependent targets compile). `swiftformat` / `swiftlint` clean.
- Adding `ViewModelId.freshness` must not change existing `==`/`hash`/`.id()` behavior (identity
  stays `id`-only). Every vmId now **encodes** `fsh` (its birth moment), and `init(from:)` decodes it
  **leniently** (`decodeIfPresent ?? Freshness()`, mirroring the existing `id` idiom) so any payload
  lacking `fsh` still decodes (an un-stamped value has no recorded birth moment, so "now" is correct).
  **No baseline regeneration and no version-comparison surgery are required:** `expectVersionedViewModel`
  is decode-only (it never encode-diffs), it **skips `ClientHostedViewModelFactory` types**, and every
  client to date is client-hosted — so no versioned-VM contract rides on the committed baselines. The
  lenient decode keeps them green untouched; `expectCodable`'s round-trip is value-preserving and
  unaffected.
- No public API exposes the underlying namespace/id string (review invariant).
- CHANGELOG entry drafted; DocC for the new types written (the repo treats undocumented shipped API
  as debt — cf. the invalidation seam that shipped silently).
