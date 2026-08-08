---
area: cross-cutting
generator-skill: none
where:
  - "Sources/**/*.swift"
  - "Tests/**/*.swift"
  - "**/*.yml"
  - "**/*.yaml"
---

# Cross-Cutting Checks

Concerns that span multiple FOSMVVM areas. This check file always triggers when scope is non-empty (regardless of which areas the diff touches).

## Reviewer Guidance

- Silent failure is never acceptable. Every error path must either propagate, log structurally, or surface to the user. "We'll handle it later" is the path to production bugs.
- **Encapsulation is the precondition SOLID assumes — review it separately.** SOLID governs structure/dependency direction; encapsulation governs state visibility, and SOLID's benefits degrade silently without it. A change can look "SOLID-clean" while a broken encapsulation wall quietly cascades. The three checks below (`stringly-typed-identity`, `published-representation`, `representation-test`) catch the common breaks. See the repo `CLAUDE.md` → *Encapsulation Is the Precondition SOLID Assumes* and [Architecture Patterns → Encapsulation Is the Precondition](../../shared/architecture-patterns.md).
- Honor inline suppression directives (`// fosmvvm-review:disable:next <check> — <reason>` and the `:this` / block forms documented in `SKILL.md`). When a candidate finding's line is covered by a suppression for that check WITH a justification, omit the finding. When the directive is present but missing a justification, emit `suppression-without-justification` instead.

## Check: suppression-without-justification
**Severity:** warning
**What:** Every `fosmvvm-review:disable*` directive must include a justification — text after the check name explaining why the rule is silenced.
**Anti-pattern:** `// fosmvvm-review:disable:next no-silent-failure` (no reason given). Suppressions without reasons are invisible tech debt; the reader cannot tell if the silenced rule was a deliberate exception or a forgotten cleanup.
**Detection:** Find every `fosmvvm-review:disable:next`, `fosmvvm-review:disable:this`, and `fosmvvm-review:disable` directive in scoped files. For each, confirm the line includes text after the check name (typically separated by `—`, `-`, `:`, or whitespace). Flag any directive whose only content is the keyword + check name.

## Check: no-silent-failure
**Severity:** blocker
**What:** Error paths must not silently swallow errors. No empty catches, no `try?` near async device/network calls without explicit handling, no `defer { repaint() }` as the only response to a thrown error.
**Anti-pattern:**
```swift
Task {
    defer { toggleRepaint() }
    try await onPatientSideToggleChanged(viewModel.laterality)
}
```
The `try await` can throw; the `defer` runs but the error vanishes.
**Detection:** Find `try?` adjacent to `await`, empty `catch { }` blocks, and `Task { ... try await ... }` blocks where the only error response is a `defer`. For each hit, verify whether the error is propagated, logged, or surfaced. Flag if not.

## Check: stringly-typed-identity
**Severity:** blocker
**What:** A `String` (or raw `UUID`) used as an identity, route, key, or token — or a public accessor that hands a sealed value's underlying string back out. A `String` has no encapsulation wall: anyone can mint, parse, or route on it. Identities must be minted from *types* (`ModelNamespace(for:)`), kept opaque, and derived on their owner (a computed that vends the finished typed value), never exposed as a raw string.
**Anti-pattern:**
```swift
struct ModelIdentity { var renderingToken: String { "\(namespace)|\(id)" } }  // vends the guts as a parseable string
func route(for key: String) { ... }                                            // stringly route/key
static var modelNamespace: ModelNamespace { .init(stringLiteral: "User") }      // minting a namespace from a String
```
**Detection:** Flag: (a) a `public`/`internal` `var`/`func` on a sealed identity/namespace/token type that returns `String`/`UUID` of its private storage; (b) a raw `String`/`UUID` parameter or stored property used as an identity/route/key/token where a typed value exists; (c) constructing an identity/namespace from a string literal rather than a type. Exempt: the single owner-scoped computed that *consumes* the string to build a typed value and never returns it.

## Check: status-interpreted-as-result
**Severity:** blocker
**What:** Client code reading an HTTP status to interpret an operation's *result*. Statuses govern transport consequences only (logging, caching, retry/backoff); result semantics ride the typed error path — the server `throw`s a `ServerRequestError` and the client catches the typed case. Branching business behavior on a status number is the stringly-typed break applied to errors: any failure can wear a 401, so the client learns nothing typed. See [Architecture Patterns → Typed Errors Are the Operation's Throw](../../shared/architecture-patterns.md).
**Anti-pattern:**
```swift
catch DataFetchError.badStatus(401) {
    refreshSessionAndRetry()          // result semantics inferred from a transport number
}
```
**Detection:** In non-test source, find `catch` clauses or `if`/`switch` branches keyed on a specific HTTP status (`DataFetchError.badStatus(<code>)`, `response.status == .<case>`, raw `401`/`403`/`404` comparisons) where the branch drives business behavior (retry with new credential, navigation, user-facing state). Exempt: pure transport consequences (structured logging, cache invalidation, generic backoff without semantic branching) and test assertions of the server's transport contract.

## Check: published-representation
**Severity:** warning
**What:** A sealed type's internal encoded shape (JSON keys, token format, byte/column layout) stated on a **public** surface — a DocC `///` comment, `CHANGELOG`, or `README`. Publishing the representation makes it a de-facto schema consumers parse or hand-forge, defeating the opacity and freezing an implementation detail. Public docs state the *contract* (opaque; `Codable` round-trips; stable within a major version), never the shape; pin the shape in an internal `//` comment + a forward-compat test.
**Anti-pattern:**
```swift
/// - Important: the Codable form is `{"namespace":"<token>","id":"<uuid>"}`.   // public DocC advertising the shape
```
**Detection:** In scoped source files and `CHANGELOG`/`README`, find `///` DocC comments (or changelog/readme lines) for a sealed/opaque type that show a literal encoded shape (`{"..."` JSON, a `"a|b"` token format, an explicit key list/order). Flag. A `//` (non-DocC) maintainer comment beside `CodingKeys` is allowed.

## Check: representation-test
**Severity:** warning
**What:** A test asserting an incidental encoded byte/key layout instead of the contract. Test what the contract guarantees — equality, determinism, round-trip identity preservation, "old data still decodes" (a committed golden-blob forward-compat fixture) — not `encode(x) == "<exact bytes>"`. A representation test freezes an implementation detail and invents a contract that doesn't exist; exposing internals to enable it is the encapsulation break from the test side.
**Anti-pattern:**
```swift
#expect(identity.renderingToken == "User|\(uuid)")          // pins a non-contractual token format
#expect(encoded == #"{"namespace":"User","id":"…"}"#)       // asserts exact encode bytes
```
**Detection:** Find `#expect`/`XCTAssert` comparing an encoded value or a derived token against an exact literal string/JSON shape. Flag unless it is a *decode* forward-compat fixture (decode a committed blob → round-trips) rather than an *encode*-shape assertion.

## Check: stub-vocabulary
**Severity:** blocker
**What:** `stub()` / `Stubbable` placeholder data must come from the reserved-fake vocabulary — Flintstones names and data ("Fred Flintstone", "Bedrock"), numbers at or near ±42, dates around 1914. Stub data must be SELF-MARKING: obviously fiction, implausible as production data. Plausible-real placeholders are the failure — once committed, a tester cannot discern them from real data, and they acquire de facto ratification by persistence.
**Anti-pattern:**
```swift
static func stub() -> Self {
    .init(userName: "Test User", memberSinceYear: 2020, projectCount: 3)
}
```
"Test User" and 2020 are plausible; nothing marks them as fiction.
**Correct:**
```swift
static func stub() -> Self {
    .init(userName: "Fred Flintstone", memberSinceYear: 1914, projectCount: 42)
}
```
**Detection:** In `stub()` implementations and `Stubbable` conformances, flag placeholder values that read as plausible-real: names outside the vocabulary, contemporary dates, realistic emails/phones/addresses, sample data copied from a ratified design (design sample data never becomes a value — anywhere).

## Check: stub-leakage
**Severity:** blocker
**What:** `stub()` call sites, or reserved-vocabulary values, appearing outside preview/test contexts — production code paths, localization YAML values, migration defaults, Factory fallbacks. Either a stub call leaked, or a fabricated value was hand-copied to where real or ratified data belongs. The most common source: a stub value silently answering a requirements gap — that situation requires an UNRATIFIED candidate to the owner, never a placeholder (a stub value at a missing argument is silent substitution wearing framework syntax).
**Anti-pattern:**
```swift
// Production Factory fallback
let name = user?.displayName ?? "Fred Flintstone"
```
**Detection:** Find `.stub()` call sites outside `#Preview` bodies, preview providers, and test targets. Grep scoped production sources, localization YAML values, and migrations for vocabulary markers — Flintstones names ("Flintstone", "Rubble", "Bedrock", "Slate") and 1914-era dates are strong signals anywhere; ±42 numbers are a signal only in defaults/fallbacks (42 alone is too common to flag bare). Flag each hit with which artifact it contaminates.
