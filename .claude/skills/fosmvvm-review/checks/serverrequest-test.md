---
area: serverrequest-test
generator-skill: fosmvvm-serverrequest-test-generator
where:
  - "Tests/**/*Request*Tests.swift"
  - "Tests/**/Requests/**/*.swift"
  - "Tests/**/*Controller*Tests.swift"
  - "Tests/**/*TestSupport*.swift"
  - "Tests/**/*E2E*.swift"
  - "Tests/**/*ServerTests.swift"
---

# ServerRequest Test Checks

The positive pattern lives in the `fosmvvm-serverrequest-test-generator` skill. A request test's job is to prove the wire contract — that the request the client would send reaches the route the server serves, and that what comes back decodes typed. These checks are about tests that hand-assemble the wire and stop proving it.

## Reviewer Guidance

- **Find request tests by content, not by filename.** The wire-driving code routinely lives in shared `TestSupport` helpers rather than in `*Tests.swift` files — grep the test tree for `.testing().test(` and `processRequest` before concluding anything about coverage.
- **The typed door and what it derives.** `app.testing().test(request, locale:) { response in }` (FOSTestingVapor) takes the *request instance*: the path comes from `R.path`, the query rides as `toJSON()`, the version/locale/content headers are added, and the response decodes into `TestingServerRequestResponse<R>` with typed `body` and `error`. Client-side E2E tests reach the same guarantee through `processRequest`. Every piece a test hand-assembles instead is a place the test can agree with the server while both disagree with the client.
- **Deliberately-malformed requests legitimately use the raw door.** A test asserting the server rejects a bad body *must* be able to send wrongness the typed door cannot express. Do NOT flag raw-door use whose purpose is sending a deliberately invalid request — the tell is an assertion on the rejection.
- **Raw Vapor routes are tested raw.** A bare route with no ServerRequest (a health endpoint, an ingest hook) has no typed door to use; testing it raw is correct — though the route itself may be another check's finding.
- **Know this area's outer boundary, and say it in reports.** These checks count coverage per request *type*; they cannot verify that a specific production call site is ever exercised. When you notice a production client path nothing drives (a `gateway.stop` no test calls), report it as the coverage note it is — never imply the suite's greenness says anything about that path. Closing that gap is E2E testing's job, not review's.
- **The async-boot trap in hand-rolled harnesses.** Vapor's `app.test()` runs only the synchronous boot path, so async lifecycle handlers (middleware registered via async startup) silently never run under a hand-rolled harness. FOSTestingVapor's shipped harnesses (`withFluentTestApp`, `withServedFluentTestApp`) handle boot correctly — at pins that have them. A hand-rolled `withTestApp` at an older pin is *correct at time of writing, now fixable*; name the version that lifts it, per the dispatch prompt's version-floor rule.

## Check: request-test-uses-the-typed-door

**Severity:** blocker
**What:** Request tests drive the wire through the typed door — `app.testing().test(request, locale:)` server-side, `processRequest` for E2E — never a hand-assembled method + path + query against the raw `test(.POST, "…", …)`. This is `controller-derives-its-own-route`'s test-side twin, and it fails the same way: a hand-built path that matches a hand-built route goes green while the real client fetches something else, and the 404 ships.
**Anti-pattern:**
```swift
// Type-derived components do NOT make the door — method, headers, and
// encoding are still hand-assembled, and the suffix is glued on:
try await app.testing().test(.POST, "\(StopRunController.baseURL)/destroy?\(encoded)") { … }
```
**Detection:** In the test tree, find every drive of a ServerRequest-served route. Sort by **who derived the wire pieces**, not by how the string looks — and sort *drives*, naming a dual-purpose helper once:

- **The typed door** — the overload taking the request *instance* (or `processRequest`): correct, not a hit.
- **Hand-assembled path, query, or verb suffix** — a glued `"/destroy?…"`, a hand-encoded query string, a string-interpolated route: **blocker**. But before framing the finding, check the server side: **when the glue faithfully mirrors a bespoke controller mount, the test is the honest witness, not the offender** — the primary finding is `controller-derives-its-own-route` (production side), the production client is the party likely broken against that mount, and converting this test to the typed door goes red until the server is remounted. Say all of that: the remedy spans both trees, and a test-only fix is not executable.
- **Framework-computed from the instance** (`request.requestURL()` and kin) — the framework derived it, a hand-rolled sliver of what the typed door already does: **warning**, not blocker; the pieces cannot drift from the framework, only from the door's header/decode behavior.
- **The raw door for something the typed door cannot express** — a deliberately malformed body, a request with a *required header omitted* (the typed door force-adds version/locale/content headers with no removal seam): legitimate, not a hit. This carve-out is scoped to inexpressibility, **not** to "asserts a rejection": a typed `ResponseError` rejection is asserted *better* through the typed door's `error` field, and a credential rejection through `credentialRejection` (0.7.0+) — a raw-door drive asserting `status == .unauthorized` is status-sniffing the field exists to eliminate, and is a **warning** (correct-at-time-of-writing below 0.7.0).
- **The raw door for an ordinary path the typed overload could express**: **warning**, with the typed door as the one-line remedy. Expect this to be voluminous with one mechanical cause — report it as one migration finding listing the sites, not as thirty findings.

Check the pin before grading: the typed door dates to 0.1.0 (almost nothing earns a pre-floor excuse on its existence), `credentialRejection` to 0.7.0, the shipped harnesses to 0.5.0/0.6.0.

## Check: request-test-covers-the-contract

**Severity:** warning
**What:** Each ServerRequest has a test exercising its contract through the typed door: the success path decodes into `ResponseBody`, and where the request declares a `ResponseError`, at least one test provokes it and catches it *typed*. An error vocabulary no test ever decodes is decoration — the same area-wide inversion `controller-throws-the-declared-error` catches in production code, seen from the test side.
**Anti-pattern:** A request declaring a three-case `ResponseError` whose entire test coverage is one happy-path fetch — the error cases compile, ship, and have never once crossed a wire.
**Detection:** Enumerate `ServerRequest` conformers yourself — across every module, not from memory or a prior list — and map the test tree's drives against them. Three dispositions, not two:

- **Absent** — a request no test drives at all, through any door. The clean hit; reserve the word for true zeros.
- **Present through the wrong door** — driven only raw. That finding belongs to `request-test-uses-the-typed-door`; here it is a *note*, never a second warning — substance-rich raw-door tests (decoded bodies, effect assertions) graded "absent" read as noise to the suite's author and double-count one mechanical cause.
- **Present** — typed-door or `processRequest` drives exist.

Then the error leg, with its escape hatch:

- A declared `ResponseError` (excluding `EmptyError`) that no test provokes and catches typed is the default finding. **Except decode-guard declarations:** an error declared solely so a permissive decode cannot swallow a middleware rejection is un-provokable by design — the server never throws it. For those, a *decode-contract* test (asserting the type refuses to decode from `{}` or a bare string) is the equivalent coverage. And note the pairing: at pins ≥ 0.7.0 the guard rationale itself is `no-defensive-error-for-credential-rejection`'s finding — `WireError` decodes the rejection first, so the declaration buys nothing; route the declaration question there and grade only the coverage here.
- **The invalid-body clause, for any validating write body** — Fields-adopting *or* plain `ValidatableModel`: at least one test sends an invalid body through the wire and asserts the typed rejection comes back. That one test proves the contract runs on the server, not merely compiles into it. A status-only assert (`== .badRequest`) half-proves it; say what the typed assert would add.

Writes deserve an **effect assertion**, not only a status. For container CRUD that naturally means the response carries the container's children and the entity appears in them; for command-style writes (a stop, a mint, a replace returning a token or outcome), asserting server-side state in-process is stronger still — the requirement is the effect, not the shape.
