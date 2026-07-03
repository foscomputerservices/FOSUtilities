# FOSFoundation API Catalog

Curated map of FOSFoundation's public API, organized by task. Before writing a
helper for JSON coding, networking, string manipulation, or versioning — check
here first; it almost certainly already exists.

## Async

Helpers for bridging synchronous and asynchronous worlds and for limiting how
much work runs at once.

### Limit concurrent async tasks — `AsyncSemaphore`
Reach for this when: at most N tasks may run a section of async code at once
(shared resources, connection pools, serializing access to a non-reentrant API).
Don't hand-roll counters or misuse `DispatchSemaphore` in async code — this actor
suspends waiters safely and honors task cancellation.

```swift
let semaphore = AsyncSemaphore(maxConcurrentTasks: 1)
try await semaphore.wait()
defer { Task { await semaphore.signal() } }
```

### Call async code from a synchronous context — `synchronous()`
Reach for this when: a function that isn't `async` must invoke `async` code and
wait for its result. Blocks the current thread until the operation finishes —
never call it from a thread the operation itself needs.

```swift
let value = try Task.synchronous {
    try await fetchValue()
}
```

## Coding

JSON coding with one shared strategy, so clients and servers always agree on
dates and formats. All of FOSMVVM's wire traffic flows through these helpers.

### Codable JSON round-trip — `fromJSON()` / `toJSON()` / `toJSONData()`
Reach for this when: converting any Codable to/from JSON strings or Data.
Don't hand-roll `JSONDecoder` configuration — these apply the library's standard
coding strategy (dates, keys) consistently with the server.

```swift
let user: User = try jsonString.fromJSON()
let json = try user.toJSON()
let data = try user.toJSONData()
```

### Standard JSON coders — `defaultDecoder` / `defaultEncoder`
Reach for this when: an API demands a JSONDecoder/JSONEncoder instance but you
still want the library's standard date handling.
Don't instantiate a bare JSONDecoder()/JSONEncoder() — dates will not round-trip
consistently with the rest of the system.

```swift
let decoder = JSONDecoder.defaultDecoder
let encoder = JSONEncoder.defaultEncoder
```

### Wire-format date formatting — `dateFormatter` / `dateTimeFormatter` / `JSONDateTimeFormatter` / `ISO8601Formatter`
Reach for this when: formatting or parsing dates in fixed formats (JSON
timestamps, ISO 8601, date-only strings). All four are GMT-0, en_US_POSIX
singletons — do not mutate them.
Don't create ad-hoc DateFormatters — device locale and timezone silently corrupt
wire formats.

```swift
let stamp = DateFormatter.JSONDateTimeFormatter.string(from: .now) // JSON timestamp
let day = DateFormatter.dateFormatter.string(from: .now) // date only
```

### Typed JSON coding failures — `JSONError`
Reach for this when: catching errors from `fromJSON()` / `toJSON()` and you need
to distinguish empty input, unknown date formats, or decode failures — its
`debugDescription` includes the offending data.

```swift
do { let user: User = try jsonString.fromJSON() }
catch let error as JSONError { logger.error("\(error.debugDescription)") }
```

### Readable decode diagnostics — `localizedDescription`
Reach for this when: logging a DecodingError — this renders the coding path,
the failing key/type, and the reason in one line instead of the opaque default.

```swift
catch let error as DecodingError {
    logger.error("\(error.localizedDescription)")
}
```

### Canonical test/preview instances — `Stubbable`
Reach for this when: a type needs a fully-initialized sample instance for tests,
previews, or placeholder UI. FOSMVVM ViewModels, requests, and fields all build
on this protocol.
Don't scatter ad-hoc sample factories across test targets — declare `stub()` once
next to the type.

```swift
extension User: Stubbable {
    static func stub() -> Self { .init(name: "Test User") }
}
let user = User.stub()
```

## Collections

Extensions on Collection for grouping and rate-limited iteration.

### Group elements into a dictionary — `grouped()`
Reach for this when: bucketing a sequence by a computed key. Element order
within each group is preserved.

```swift
let byParity = [1, 2, 3, 4].grouped { $0 % 2 == 0 }
// [false: [1, 3], true: [2, 4]]
```

### Rate-limited iteration — `throttleExecute()`
Reach for this when: applying an async operation to every element without
exceeding a rate limit (API quotas, server throttling).
Don't hand-roll sleep loops around `TaskGroup` — this batches and paces the
calls for you.

```swift
let results = try await urls.throttleExecute(rate: (quantity: 20, per: 2)) { url in
    try await url.fetch() as MyData
}
```

### Thread-safe global key/value strings — `GlobalStringStore`
Reach for this when: a few global string values must be shared across
concurrency domains (feature flags, tokens) without inventing a singleton.

```swift
await GlobalStringStore.default.setValue(key: "authToken", value: token)
let token = await GlobalStringStore.default.getValue(key: "authToken")
```

## Data

The identity vocabulary shared by Models, ViewModels, and requests.

### Typed model identifier — `ModelIdType`
Reach for this when: declaring the identity of a *Model* — the `id` a ViewModel
projects and round-trips through requests.
Don't declare raw UUID fields: identity is always spelled `ModelIdType`, and this
project's governance restricts it to the `@ID` position — cross-entity references
belong in junction tables, not loose id fields.

```swift
public struct UserViewModel {
    public let id: ModelIdType
}
```

## Extensions

Runtime checks on the application bundle (Apple platforms).

### Detect simulator and TestFlight installs — `isSimulator` / `isTestFlightInstall`
Reach for this when: behavior should differ between simulator, TestFlight, and
App Store installs (diagnostics, feature gating, analytics opt-out).

```swift
if Bundle.main.isSimulator { enableDebugOverlay() }
if Bundle.main.isTestFlightInstall { showBetaFeedbackButton() }
```

### App-bundle version as a SystemVersion — `appleOSVersion`
Reach for this when: comparing the version Apple shows in the App Store (the
bundle's Version + Build) against `SystemVersion.current` to ensure the two are
configured consistently.

```swift
let bundleVersion = try Bundle.main.appleOSVersion
assert(bundleVersion.isSameVersion(as: .current))
```

## Networking

Typed, Codable-based REST and WebSocket communication. The URL extension methods
are the front door; `DataFetch` sits beneath them when you need more control.

### Typed REST calls on URL — `fetch()` / `send()` / `delete()`
Reach for this when: making a JSON GET/POST/DELETE and decoding the response
into a Codable type; pass `errorType:` to surface typed server errors.
Don't hand-roll URLSession dataTasks plus JSONDecoder — these apply the standard
headers, status/MIME checking, and the library's coding strategy in one call.

```swift
let user: User = try await url.fetch(errorType: MyServerError.self)
let created: User = try await url.send(data: newUser)
let removed: DeleteResult = try await url.delete(data: userRef)
```

### Configured REST client — `DataFetch` / `urlSessionConfiguration()`
Reach for this when: the URL extension methods aren't enough — you need a bearer
token on every request, a cellular-access policy, or an injected session.
Don't build URLSessionConfigurations by hand for auth — `urlSessionConfiguration(forUserToken:)`
sets the Authorization header once for the whole session.

```swift
let session = URLSession.session(config: DataFetch<URLSession>.urlSessionConfiguration(forUserToken: token))
let user: User = try await DataFetch(urlSession: session).fetch(url)
```

### Typed networking failures — `DataFetchError`
Reach for this when: handling errors from `fetch()` / `send()` / `delete()` —
distinguish bad status codes, empty responses, MIME mismatches, and decode
failures instead of string-matching error text.

```swift
catch let error as DataFetchError {
    if case .badStatus(let code) = error { handle(code) }
}
```

### Mockable network sessions — `URLSessionProtocol` / `session()`
Reach for this when: testing code that uses `DataFetch` without hitting the
network — inject any conforming session (FOSTesting provides `MockURLSession`).
Don't make real network calls in tests.

```swift
let dataFetch = DataFetch(urlSession: MockURLSession.session(config: .default))
```

### Find files by extension — `findFiles()`
Reach for this when: collecting every file below a directory URL with a given
extension (resource discovery, fixture loading).

```swift
let yamlFiles = resourceDir.findFiles(withExtension: "yml")
```

### Send Codable over a WebSocket — `send()` / `WebSocketError`
Reach for this when: pushing an Encodable value through a URLSessionWebSocketTask
— it's encoded with the library's standard JSON strategy and send-state errors
surface as `WebSocketError`.

```swift
try await webSocketTask.send(statusUpdate)
```

## Numbers

Numeric formatting and conversion helpers.

### Round to decimal places — `rounded()`
Reach for this when: rounding a Double to a fixed number of decimal places for
display or comparison.

```swift
(1.1234567).rounded(toPlaces: 2) // 1.12
```

### Integers as hex strings — `hexString()` / `HexadecimalPrefixStyle`
Reach for this when: rendering an integer in hexadecimal, with a `0x` or `#`
prefix. Available on Int, UInt, Int64, and UInt64. To parse the other direction,
see `intFromHex` (String).

```swift
255.hexString() // "0xFF"
255.hexString(prefixStyle: .sharp) // "#FF"
```

## String

Fifteen years of string helpers: casing, trimming, generation, parsing, hashing,
and obfuscation. Check here before writing any string manipulation.

### Case-style conversion — `snakeCased()` / `camelCased()`
Reach for this when: converting identifiers between snake_case and CamelCase
(wire keys, code generation, YAML/JSON key mapping).

```swift
"UserProfile".snakeCased() // "user_profile"
"user_profile".camelCased() // "UserProfile"
"user_profile".camelCased(firstUpper: false) // "userProfile"
```

### First-character casing — `firstUppercased()` / `firstLowercased()`
Reach for this when: only the first character's case must change — the rest of
the string is left exactly as-is (unlike `capitalized`, which lowercases the rest).

```swift
"upper".firstUppercased() // "Upper"
"LOWER".firstLowercased() // "lOWER"
```

### Conditional prefix/suffix removal — `trimmingPrefix()` / `trimmingSuffix()`
Reach for this when: stripping a known prefix or suffix if present, returning the
string unchanged otherwise.
Don't chain `hasPrefix` + `dropFirst(count)` by hand.

```swift
"v1.2.3".trimmingPrefix("v") // "1.2.3"
"config.yml".trimmingSuffix(".yml") // "config"
```

### Count substring occurrences — `count()`
Reach for this when: counting how many times a substring appears in a string.

```swift
"aabaacaadaa".count(of: "aa") // 4
```

### Random and unique string generation — `random()` / `unique()`
Reach for this when: generating throwaway or unique string values — test data,
temporary keys, disambiguating names. `unique(compact: true)` is shorter but only
locally unique.

```swift
String.random(length: 8) // e.g. "x7Rq2LmA"
String.unique() // globally unique
String.unique(compact: true) // shorter, locally unique
```

### Sanitize single-line user input — `singleLineInput()`
Reach for this when: cleaning free-text field input — trims surrounding
whitespace/newlines and converts empty results to nil so "blank" is one check.

```swift
guard let name = rawInput.singleLineInput() else { return promptForName() }
```

### Parse hex strings to integers — `intFromHex`
Reach for this when: converting "#FF" / "0xFF" style strings to an integer
(case-insensitive; nil when not valid hex). The inverse of `hexString()`.

```swift
"#FF".intFromHex // 255
"0xbadf00d".intFromHex // 195948557
```

### Quick CSV parsing — `loadCSVData()`
Reach for this when: splitting simple comma-separated text into trimmed rows and
columns (fixtures, quick imports). There is no delimiter escaping — use a real
CSV library for untrusted or quoted data.

```swift
let rows = csvString.loadCSVData() // [[String]]: rows of columns
```

### Reversible string obfuscation — `obfuscate` / `reveal` / `rot13()` / `rot47()`
Reach for this when: a string shouldn't be human-readable in transit or storage
(query strings, casual logs) but doesn't warrant real encryption; `obfuscate`
output is safe to embed in URL queries, and `reveal` restores the original.
Don't use these for secrets — obfuscation is trivially reversible; hash or
encrypt anything security-sensitive.

```swift
let hidden = "I am a string".obfuscate
let original = hidden.reveal // "I am a string"
```

### SHA-256 hashes and HMAC signatures — `sha256()` / `hmacSha256()` / `hmacSha256Data()`
Reach for this when: hashing a string or computing a keyed message signature,
portably across Apple platforms and Linux.
Don't import CryptoKit directly and hand-convert digests to hex strings — these
return ready-to-use string (or Data) results.

```swift
let digest = "payload".sha256()
let signature = "payload".hmacSha256(key: secretKey)
```

### Self-normalizing string properties — `CamelCased` / `SnakeCased` / `Lowercased` / `Uppercased`
Reach for this when: a property must always hold a canonical casing no matter
what is assigned to it. The wrappers are Codable-transparent — they encode and
decode as plain strings.
Don't normalize at every assignment site — declare the invariant once on the property.

```swift
struct Route: Codable {
    @SnakeCased var pathComponent: String
    @Lowercased var host: String
}
```

## Versioning

Semantic versioning shared by clients and servers to negotiate compatibility.

### Semantic system versioning — `SystemVersion` / `SystemVersionError`
Reach for this when: representing an application/server version, comparing
compatibility, or setting the process-wide version at startup. Codable (encodes
as a version string), Comparable, and `Stubbable`.
Don't pass versions around as raw strings — parse once into `SystemVersion` and
compare with `isCompatible(with:)` / `isSameVersion(as:)`.

```swift
SystemVersion.setCurrentVersion(.init(major: 2, minor: 1, patch: 0)) // once, at startup
guard clientVersion.isCompatible(with: .current) else { throw SystemVersionError
    .incompatibleVersion(requested: clientVersion, required: .current) }
```
