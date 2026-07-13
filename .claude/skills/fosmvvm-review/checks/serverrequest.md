---
area: serverrequest
generator-skill: fosmvvm-serverrequest-generator
where:
  - "Sources/**/ServerRequests/**/*.swift"
  - "Sources/**/*Request.swift"
---

# ServerRequest Checks

The positive pattern lives in the `fosmvvm-serverrequest-generator` skill.

## Reviewer Guidance

- A `ResponseError` is the operation's *semantic* error — the well-defined Swift error the operation would `throw` if it were a local function call. `ServerRequestError` exists so that throw can happen across the wire (server throws → rides the response as `Codable` → the client's `processRequest` rethrows the same typed error). It is **not** an HTTP-status mapping; HTTP statuses are transport dressing and carry no result semantics. See [Architecture Patterns → Typed Errors Are the Operation's Throw](../../shared/architecture-patterns.md).

## Check: responseerror-models-the-throw
**Severity:** blocker
**What:** A `ResponseError` must declare the operation's failure vocabulary as typed data — what the operation would `throw` locally — not mirror the transport. Two smells: (a) error cases named after HTTP statuses or transport categories rather than operation outcomes; (b) a `ResponseError` whose only content is a free-text `reason`/`message` `String`. A reason-only shape mirrors a middleware abort body, so *any* rejection decodes into it and the client cannot distinguish cases by type.
**Anti-pattern:**
```swift
struct MyError: ServerRequestError {
    let reason: String                       // free-text only — string-puns with any abort body
}

enum ErrorCode: String, Codable, Sendable {
    case unauthorized401                     // status-named — transport leaked into semantics
    case badRequest
}
```
**Detection:** For each type conforming to `ServerRequestError` (excluding `EmptyError` and `ValidationError`): flag if (a) its only stored data is one or more free-text `String` fields (no `ErrorCode`-style enum, no typed associated data); or (b) its enum cases are named for HTTP statuses/transport categories (`unauthorized`, `forbidden`, `badRequest`, `notFound` with no operation noun, numeric-status suffixes) rather than operation outcomes (`duplicateContent`, `quotaExceeded`, `sessionExpired`).
