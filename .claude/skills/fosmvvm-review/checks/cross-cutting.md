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

## Check: no-string-backed-enums
**Severity:** blocker
**What:** An enum never takes a `String` raw value. A raw value opens a public string door — `Reason(rawValue: "invalid")` — that anyone can mint or parse, and it makes the case's spelling the user-facing text, which cannot localize. Cases localize through the YAML tree keyed by type and case; the wire carries the case, not a string the type published.
**Anti-pattern:**
```swift
enum ErrorCode: String, Codable, Sendable {          // a public string door + an unlocalizable spelling
    case serverFailed

    var message: LocalizableString {
        .localized(for: Self.self, parentType: SimpleError.self, propertyName: rawValue)   // the raw value IS the key
    }
}
```
**Detection:** Flag every `enum … : String` (and `: Int` when the raw value is anything but an ordinal the type itself consumes) — public or internal, wire-crossing or not. The remedy is the plain enum with synthesized `Codable`; a case's localized text comes from `LocalizableString.localized(case:parentType:)`, which derives the YAML key from the case with no string in user code. Exempt: `CodingKeys` (Swift's own coding contract); a `String`-backed enum whose raw value is consumed only by a system API that demands `RawRepresentable<String>` — name the API in the finding when this exemption is claimed, and treat a `rawValue` read anywhere else as the hole; and **tools, not libraries** (ruled 2026-09-02) — a CLI's argument and config-file tokens (`--shape clientServer`, a bootstrap config's `"shape"`) are typed by a human at a prompt, not carried on a wire or shown to a user, so the rule does not reach them. When the framework pin predates `localized(case:parentType:)` (shipped 0.16.0), report as correct at time of writing, now fixable.

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

## Check: server-calls-use-the-request-door
**Severity:** blocker for a hand-built call to the app's own server; warning for hand-rolled plumbing to external services
**What:** Client code never hand-builds an HTTP call to the app's own FOSMVVM server — every such communication is a typed `ServerRequest` through `processRequest` (**either overload**: `processRequest(mvvmEnv:)` in apps, `processRequest(baseURL:headers:session:)` in CLIs and jobs that have no `MVVMEnvironment` — both are the door). The type derives the path, the protocol the method; version headers and typed errors ride along. Calls to genuinely external services (third-party APIs) go through FOSFoundation's networking front door — `url.fetch()` / `url.send(data:)` / `url.delete(data:)` — never a hand-rolled `URLSession` dataTask plus `JSONDecoder`. Use the `errorType:` overloads when the service's error body is a type you own; a third-party service throwing arbitrary HTML/JSON is legitimately handled with the plain overload.
**Anti-pattern:**
```swift
// To the app's own server — the request door exists for exactly this
let url = URL(string: "http://localhost:8080/api/users/\(id)")!
let (data, _) = try await URLSession.shared.data(from: url)
let user = try JSONDecoder().decode(User.self, from: data)

// To an external service — hand-rolled where url.fetch() exists
var request = URLRequest(url: weatherURL)
request.httpMethod = "GET"
let (data, _) = try await URLSession.shared.data(for: request)
```
**Detection:** Key on the **transport, not on URL construction** — building or rewriting a URL (cache-busting, pagination) that is then handed to the front door is not a hit. Find raw transport use in client-role code: `URLSession` dataTask/data calls, hand-assembled `URLRequest`s, and app-owned socket connects (WebSocketKit/NIO dialers, `URLSessionWebSocketTask` outside the framework's own plumbing). Then resolve whose host each call targets — the tier depends on it:

- **The app's own server** — the URL matches a `deploymentURLs` host, is derived from `MVVMEnvironment` configuration, mirrors a ServerRequest-derived route, **or comes from an injected base (a CLI flag, a channel endpoint, a config file) whose documented target is the app's server**. CLIs rarely have an `MVVMEnvironment`, so the injected-base prong is the one that decides them — read the base's documentation and derivation, not just the literal URL. **Blocker.**
- **Client role wins over target membership.** Code inside the server target that calls the server over HTTP — an installer's health poll, a self-check — is client code for this rule. (The architecture doc names health checks as `ShowRequest`'s own example, so "there is no request type for it" is the finding, not the excuse.)
- **The acknowledged-gap path.** Where the door genuinely cannot express the operation — raw byte streaming, ranged reads, an octet-stream object transfer, a socket channel — that is a framework gap. The disposition is the standard suppression directive whose justification **names the gap and the upstream report** (`// fosmvvm-review:disable:next server-calls-use-the-request-door — raw streaming; FOSUtilities issue #N`). A hand-built call with an in-file rationale but no suppression-plus-report is still the blocker — fire it once more with "report the gap upstream and suppress with the issue number" as the remedy, so the finding converges instead of re-firing forever. Never recommend widening the hand-built surface while the gap stands.
- **A genuinely external service.** Hand-rolled `URLSession`/`dataTask`/`JSONDecoder` plumbing is a **warning**: `url.fetch()`, `url.send(data:)`, `url.delete(data:)` (FOSFoundation, `URL+DataFetch.swift`) already apply the standard headers, status checking, and the library's **JSON** coding — the front door is JSON-shaped, so a raw-bytes external fetch has no front door and takes the acknowledged-gap path instead. `DataFetch.urlSessionConfiguration(forUserToken:)` covers bearer-token sessions.
- **CLI tools and background jobs are clients too** — no exception on either tier.
- **Leaf/JS templates: TBD** (ruled 2026-08-25). A template-side `fetch('/api/…')` is this rule's violation in JavaScript, and template review belongs to the view-area work — there is no detection here yet. When one is encountered anyway, report it at **warning** under this check's name and note the TBD standing.

Not hits: FOSFoundation's own Networking internals; the framework's SSE/live-invalidation plumbing; **`URLSession.session(config:mutualTLS:)` and FOSNetworkSecurity's session factories** — pinned-TLS session construction is the framework front door, not hand-rolling; test doubles exercising the network-mocking support. Test helpers that hand-assemble method + path + query around `app.testing().test(...)` are the request-test area's business, not this check's — note them, do not grade them here.

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

## Check: stub-records-its-arguments
**Severity:** warning
**What:** A recording stub exposes both assertion points a caller needs: that the operation fired, and what data it fired with.
**Anti-pattern:**
```swift
public func run(_ command: Command, on storage: any Storing) async throws {
    runCalled = true          // `command` is dropped
}
```
**Detection:** For each recording stub (a test double whose methods set `…Called` flags), find methods taking data-carrying parameters — anything beyond the output/storage target. Flag those recording only a `Bool` with no corresponding `…CalledWith`. The test that matters is usually "did the *right* verb fire", and a lone `Bool` makes three different calls indistinguishable. Methods whose only parameter is the write target are not hits.

## Check: stubs-record-they-dont-do
**Severity:** warning
**What:** A stub Operations implementation records the call — it never performs the operation's work (viewmodel generator, ratified 2026-08-25). A UI test proves the button is *wired* to the operation, not that the operation does something; a stub that does work turns that wiring test into a timing-dependent behavior test, and can reach real infrastructure from a test.
**Anti-pattern:** A `StubOps` method whose body awaits a `processRequest`, sleeps (`Task.sleep`), spawns a `Task`, or touches network, files, or a database — instead of assigning its recorder and returning.
**Detection:** For each stub Operations conformer (resolve the trio by conformance and role, not name), read every method body. Flag real work: awaited calls beyond a trivial actor hop, `processRequest`, timers and sleeps, spawned tasks, network or storage reach. **Not hits:** recorder assignments; writing the `output` storage/binding the method is handed — that is recording's client-hosted twin, and `stub-mutates-what-it-is-handed` *requires* it; an `async throws` signature with no `await`, which the protocol forces (the same shape `ops-not-async-unless-needed` already exempts). A stub whose work reaches production-shaped infrastructure escalates to `tests-never-touch-production`'s blocker — cite that name, count the cause once.

## Check: stub-mutates-what-it-is-handed
**Severity:** warning
**What:** A stub for a client-hosted ViewModel's Operations performs the same mutation the live implementation would, so the projection loop still runs under test.
**Anti-pattern:** A `*StubOps` method that ignores its storage parameter entirely and only sets a flag — the `@Observable` store never changes, so nothing re-projects and the View under test stays frozen.
**Detection:** Identify Operations stubs belonging to a ViewModel declared with `clientHostedFactory`. Flag methods that never touch the storage parameter they are handed. Server-hosted Operations stubs are exempt: their projection comes from a fetch, not from local mutation. Cite what a test can no longer assert — the frozen state is the cost, not the missing line.

## Check: no-hand-rolled-framework-products
**Severity:** warning
**What:** The project does not re-implement what the framework or a generator already provides (functional-discipline: hand-rolling what a generator or the framework produces; repo CLAUDE.md's API-catalog rule — check the catalog before hand-writing a helper). Detections resolve against the plugin's api-catalog (`shared/api-catalog/`, the reach-for index) — **never against memory**: a capability is "provided" only if the catalog lists it.
**Anti-pattern:** A hand-configured `JSONEncoder()`/`JSONDecoder()` coding the app's own wire or persisted data where `toJSON()`/`fromJSON()`/`defaultEncoder` carry the wire-format date contract; a hardcoded `DateFormatter` pattern building display text where the `Localizable` date machinery exists; a hand-written async button with an error binding after the framework shipped `Button(activity:error:action:)`; a bespoke network mock where `URLSessionProtocol`/`session()` exists; a re-implemented semantic-version comparison, CSV parse, or grouping helper.
**Detection:** For each project-authored helper, utility type, or extension in the reviewed files, ask the catalog's reach-for question — does an entry already provide this? Two forms, one name:

1. **The hand-rolled product.** A re-implementation of a catalog-listed capability. Grade by the **contract semantics the hand-roll loses**, and say so in the finding: wire-format dates on the app's own coding (drift the decoder will feel), locale correctness (a hardcoded format string is wrong in every locale but one), typed decode diagnostics, verified interaction semantics (re-entry refusal, cancellation) on async UI. A bare `JSONDecoder()` on a CLI tool's local config file is the shallow end — note the family once with its sites listed, not one finding per call.
2. **Duplicated dependency internals.** Framework internals reverse-engineered or copied downstream because the framework lacks something the project needs. The remedy is **always the upstream report, never the fork** — the finding names the gap and the report as the fix, and the acknowledged-gap suppression path applies (gap documented + upstream issue number, per `server-calls-use-the-request-door`'s precedent), so the finding converges instead of re-firing.

**The version floor is mandatory, checked before writing any finding.** Resolve the consumer's pinned FOSUtilities version (`Package.resolved`) against the release the API shipped in — the catalog and CHANGELOG carry the floors. A pin **below** the floor means the hand-roll predates the product: that is NOT a violation — report it as an **adoption candidate** ("the framework provides this since 0.13.0; adopt on upgrade"), a different finding with a different tone. Blaming code for not using an API its pin cannot see is this check's characteristic false positive.

**Not hits:**

- **An external service's wire contract** legitimately demands its own coder configuration — DTO coding for a third-party API, with that service's date formats and casing, is not a hand-roll of the framework's coders. (The *transport* to such services is `server-calls-use-the-request-door`'s warning clause.)
- **Own-server calls** are `server-calls-use-the-request-door`'s blocker — network plumbing belongs to that check entirely; this one covers everything else in the catalog.
- **UI-test element helpers** keep their specialized name: `no-hand-rolled-element-helpers` (`ui-tests`).
- A helper the catalog does not list is not a finding under this name — it may be a candidate *for* the framework, which is an observation for the owner, not a violation.

## Check: tests-never-touch-production
**Severity:** blocker
**What:** Tests never modify, delete, or corrupt production data — read-only by default (repo `CLAUDE.md`, firm governance principle). A test's isolation is **constructed, not inherited**: its server is in-process or localhost, its database is ephemeral and test-created, its stores are stubs.
**Anti-pattern:** A Fluent test binding a DSN read from the ambient environment (`DATABASE_URL`) and running migrations or writes; a test firing a write request at a real deployment URL; a cleanup sweep deleting by pattern (`test*`) against shared infrastructure; a live production store injected into a test host whose taps mutate it.
**Detection:** For each test file, resolve where its **execution edges** actually land — the server it calls, the database it binds, the stores it injects:

- **Blocker — a mutation path that can reach non-test infrastructure.** Write requests aimed at a deployment URL (anything not in-process or localhost); a database binding inherited from the ambient environment, with or without a production-shaped default — "it's staging today" does not clear it, because the target is whatever the shell says; pattern-keyed cleanup deletes against a shared target; a live store in a test host (that shape's home is `testhost-mirrors-vm-settings`, `ui-tests` — cite it there, count it once).
- **A production URL literal is never itself the violation.** Trace it to an execution edge: a real hostname handed to a pure function (URL manipulation, parsing) is inert fixture data and not a hit. Grep-and-flag on hostnames is this check's characteristic false positive.
- **Live reads are not this blocker.** A test that live-reads an external service mutates nothing — the principle is read-only by default. Note the network dependency once, as flakiness, not under this name.
- **The conformant shapes:** the in-process typed test door (`serverrequest-test`'s harnesses), `app.databases.use(.sqlite(.memory), as: .sqlite)` or an equally ephemeral test-constructed binding, mocked sessions (`URLSessionProtocol`), and localhost `.debug` deployment URLs.

Pairs with `deployment-urls-distinguish-environments` (`swiftui-app-setup`) — a debug/test build resolving to a production host — which stays that area's finding; this check owns the test-tree side of the same principle.

## Check: behavioral-suite-standing
**Severity:** warning
**Scope:** project (clause 1, standing); site (clause 2, isolation)
**What:** The behavioral-test channel's **standing and isolation** — and nothing else. Behavioral suites project from requirements + ratified design in a context that never saw the implementation (execution-model's dedicated second channel; the `fosmvvm-behavioral-test-generator` skill). Review verifies that the suite exists and that its isolation held; **review NEVER judges a behavioral suite's assertions against the implementation** (ruled 2026-08-25) — a reviewer proposing to "fix" a behavioral assertion to match the code is committing exactly the contamination the channel exists to prevent. When a behavioral assertion and the code disagree, that is channel disagreement, classified upward (code defect / payload defect / ambiguous requirement) — never a review finding against the test.
**Anti-pattern:** A `*BehavioralTests.swift` suite with `@testable import` of the module under test; a behavioral suite importing an app or server target; a project whose truth layer carries requirements while no behavioral suite exists.
**Detection:** Behavioral suites are identified by the generator's conventions — `{Name}BehavioralTests.swift`, suites named `"{Name} — {REQ} behavioral"`, per-test `// REQ-nn:` traceability comments. Two clauses:

1. **Standing.** When the project's repo carries a requirements register (specs/requirements documents in the truth layer) and no behavioral suite exists, note the standing gap once — the requirement-semantics channel is unverified. Grade it relative to what review can see: a repo with no visible requirements register gets no standing finding, because review cannot demand a projection of arguments it cannot see.
2. **Isolation, code-visible shadows only.** In each behavioral suite: `@testable import` of any module (the writer's payload carried public signatures only — internal access is a post-hoc reach the channel never had); imports of implementation modules (app targets, server targets, Factory-bearing modules) rather than the shared contract modules + testing frameworks; missing traceability markers or suite naming (form drift suggesting the suite was not projected through the channel — report as form, do not infer content judgments from it). Provenance and payload hygiene are process facts review cannot see; do not speculate about them.

## Check: existentials-answer-the-question
**Severity:** warning
**What:** Existential types are a code smell, not a ban (repo `CLAUDE.md`, firm principle; scope ruled 2026-08-25): every existential in the flagged shapes must be able to answer the principle's own question — **was there any other way?** Passing `any XxxOperations` as a parameter is fine and out of scope. In scope: **stored** `any P` properties, **collections** of existentials (`[any P]`), and **existential returns** on the project's own API — the shapes where the erasure persists and compounds, costing dynamic dispatch, boxing, lost type identity, and `Codable` friction.
**Anti-pattern:** A stored `any P` where `P` has one production conformer and a generic (or the concrete type) would serve; `[any P]` over a closed, known set of conformers that an enum would model with exhaustive switching; a public API returning `any P` when callers immediately need the concrete type back.
**Detection:** For each in-scope existential, ask the question and read whether the code answers it. **The finding states the cost and names the alternative** — a generic parameter, a primary associated type, an enum over the closed conformer set, or the concrete type — not just "existential found." Answers that count, found in the wild:

- **The injected-dependency seam.** A type storing several protocol-typed dependencies (`private let journal: any JournalStore`, five siblings beside it) where the generic alternative metastasizes N type parameters across every use site — that burden is exactly what the ruling exempts. Cold-path dispatch (called once per cycle) strengthens the answer.
- **Transitively, the seam's resources.** A seam protocol's method returning `any Handle`/`any Connection` inherits the seam's answer — the caller holds the seam erased, so its resources come back erased.
- **A third-party protocol's own idiom** (`(String) -> any LogHandler`, a service-lifecycle `any Service` collection) — the vendor's contract, not the project's choice.
- **A genuinely heterogeneous runtime mix** whose membership is open — the case erasure exists for.

**Not double-reported:** a stored existential on a `@ViewModel` whose conformers include an `@Observable` class is `vm-holds-scalars-only`'s **blocker** (`viewmodel`) — this check takes only the value-typed remainder there, as the snapshot-doctrine note that check delegates. The framework's computed `operations: any XxxViewModelOperations` idiom and the platform's untyped-error convention (`Binding<Error?>`, `any Error` in catch plumbing) are the framework's and platform's own answers — not hits.

## Check: docc-serves-the-customer
**Severity:** warning
**What:** Documentation has three audiences, three homes (repo `CLAUDE.md` → Documentation & Comments; ruled into review 2026-08-25). DocC (`///`) serves the code's **customer**: lead with how they call it — nearly always an example — then why and when they care; state the contract, never implementation details or design rationale. Design rationale belongs in plan/design prose; internal `//` serves the maintainer and only for genuinely non-obvious constraints. Undocumented **and** example-free public API is debt reviewed projects inherit from the framework's own standard.
**Anti-pattern:** `/// An opaque token that wraps a namespace-derived hash…` (implementer's frame — what it *is* inside) instead of `/// Create one from a type — ModelNamespace(for: User.self)…` (customer's frame — how to call it); a `///` block explaining why the author chose this design; a `//` comment restating what the next line plainly does.
**Detection:** Three clauses, all judgment-graded; report each as an aggregate finding with representative `path:line` sites, never one finding per symbol:

1. **Undocumented or example-free public API.** Grade by whether the symbol has *customers* — types consumed across module boundaries (ViewModels, Fields, Requests, shared utilities) carry the bar; a member that is `public` only because the target layout forces it is the shallow end. **Look above the attribute stack**: `@ViewModel`, property wrappers, and macros sit between the DocC and the declaration, so an adjacency-keyed detection reports the best-documented idiomatic types as undocumented — walk up past attributes before concluding a symbol has no `///`.
2. **Implementer's frame in DocC.** The test is the frame, not tell-words: does the sentence tell the *caller* how/when to use it, or tell a *maintainer* why it was built this way? A scope-of-contract note ("observed-only — the editor is a later arc") is customer information even when it sounds provisional; "we do X to avoid Y internally" is implementer rationale even when polished. The remedy is **relocate to the design/plan prose, not delete** — the content is valuable in its right home.
3. **Theatrical internal comments.** A `//` that proves a non-problem or restates the adjacent code is theatre — it reads as compensating for doubt and costs lifetime velocity. (A comment asserting a safety mechanism the code lacks is `comment-asserts-an-invariant-the-code-lacks`'s **blocker**; a sealed type's encoded shape stated in DocC/README is `published-representation`'s — cite those names, not this one.)

## Check: suites-serialize-shared-state
**Severity:** warning
**What:** Swift Testing runs suites — and the tests inside a suite — in parallel by default. A suite whose tests touch **shared mutable state** carries `.serialized` (repo `CLAUDE.md` lesson, confirmed as doctrine 2026-08-25). The classic symptom is a test recording a value and asserting `0`, because another test cleared the shared state between the write and the read.
**Anti-pattern:** `@Suite struct FooTests { … Store.shared.clearState() … }` with no `.serialized` trait, in a package where another suite also drives `Store.shared`.
**Detection:** For each `@Suite` (and each implicit suite — a type holding `@Test`s), find touches of shared mutable state, then check the trait:

- **Shared mutable state is more than `X.shared` singletons:** `static var`s, the process environment (`setenv`/`ProcessInfo` overrides), fixed-path filesystem fixtures, and process-global registries all count. A `.shared` accessor that is only *read* (a port off a running server, `URLSession.shared` as transport) is not a mutation — the mutation is the test's, not the accessor's.
- **`.serialized` protects within the suite only.** When the same state spans **multiple suites**, `.serialized` on each does not stop cross-suite interleaving. Two conformant remedies for that case, both found in the wild or the lessons: a **test-owned coordination gate** acquired around exactly the racing window (set → use → restore — finer-grained than the trait, and cross-suite safe), or **dependency injection** so the state stops being shared at all — the companion lesson names DI as the real fix and the singleton as the underlying liability. A finding on the cross-suite shape names one of these, not just the trait.

## Check: comment-asserts-an-invariant-the-code-lacks
**Severity:** blocker
**What:** A comment does not claim a safety property the code does not implement.
**Anti-pattern:**
```swift
/// Recorded state is guarded by an `OSAllocatedUnfairLock`, so the
/// `@unchecked Sendable` conformance is HONEST.
public final class SomeStubOps: SomeOperations, @unchecked Sendable {
    public private(set) var runCalled = false     // no lock anywhere in the file
}
```
**Detection:** Where a comment names a specific mechanism as the reason something is safe — a lock, a queue, an actor, a copy, a validation — verify the mechanism exists in the code it describes. Highest yield around `@unchecked Sendable`, whose whole contract is a human promise: check that the named guard is actually present and actually covers the mutable state. Flag the comment together with the state it fails to cover. This is worse than no comment: it tells the next reader, and the next reviewer, not to look.

## Check: directives-spell-their-tool
**Severity:** warning
**What:** A tooling directive comment uses its tool's exact token, or it silences nothing while reading as governance (ruled 2026-08-25; the ledger entry is the statement of record). SwiftLint's token is `swiftlint:`, this skill's is `fosmvvm-review:` — a variant spelling (`swift lint:disable`, a stray space, a hyphenated guess) is inert prose the next reader trusts and every tool ignores: the same harm class as `suppression-without-justification`.
**Anti-pattern:** `// swift lint:disable classes_should_be_final` — wrong token, and in the observed case a rule id no tool defines either.
**Detection:** Find directive-shaped comments — `disable`/`enable`/`ignore` verbs addressed to a tool — whose token matches no tool the repo actually runs (its lint config, this skill's directives). Flag each with the correct spelling, or with removal when the underlying rule does not exist. A correctly-spelled directive is the *other* checks' business (justification, validity); this one fires only on the spelling.

## Check: deferral-pointers-resolve
**Severity:** warning
**What:** A comment that defers work to a tracking document points at a document that exists in the repo (ruled 2026-08-25; the ledger entry is the statement of record). A dead pointer makes an untracked deferral look tracked — the reader trusts the ledger entry that was never written.
**Anti-pattern:** `// deferred follow-up (see docs/harbor-team/deferrals.md)` where no such file exists — beside a sibling comment correctly citing the real `docs/deferrals.md`.
**Detection:** Find comments that defer or reference work to an in-repo document — `see docs/…`, `→ <path>.md`, deferral/plan/ledger citations — and verify each cited path exists. Flag dead pointers with the nearest real document when one is evident (a path-drifted spelling of an existing ledger is the common case). External URLs and issue-tracker references are out of scope; so is prose *about* documents that cites none.
