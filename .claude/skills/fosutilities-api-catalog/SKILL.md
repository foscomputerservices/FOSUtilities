---
name: fosutilities-api-catalog
description: Discover FOSUtilities APIs before writing helper code. Use when reaching for JSON/Codable encoding-decoding, wire-format date formatting, URLSession/HTTP fetching, WebSockets, network mocking in tests, collection grouping or throttled iteration, string casing/hashing/obfuscation/CSV parsing, hex or rounded-number formatting, semantic version comparison, semaphores or async-from-sync bridging, typed model identifiers, runtime environment/bundle-version checks (simulator/TestFlight detection), ViewModel declaration and localization, form fields and validation, ServerRequests/CRUD, SwiftUI ViewModel binding, Vapor boot wiring/routes/Fluent/Leaf/middleware, ViewModel or ServerRequest or UI testing, or PDF generation — in any project that imports FOSFoundation, FOSMVVM, FOSMVVMVapor, FOSTesting, or FOSReporting.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🗂️", "os": ["darwin", "linux"]}}
---

# FOSUtilities API Catalog

Before hand-writing a helper in a project that imports these libraries, check
whether it already exists. Fifteen-plus years of accumulated API lives here; the most
common failure is reinventing it.

## How to use this skill

1. Find your reach in the index below.
2. Read **only** the catalog file(s) it points to, from `../shared/api-catalog/`.
3. Prefer the catalogued API over hand-rolled code; use it as the entry shows
   (each entry's example is the idiomatic form).

If your reach isn't in the index, scan the catalog file for the library you're
importing — and if the capability exists but the index line was missing, add the
line via the `fosutilities-api-catalog-update` skill.

## Reach-for index

<!-- Keyed by what's in the implementor's hands — never by our library layout. -->
<!-- Pointer format: backticked FILE.md § Section — each must resolve to a real ## header. -->

- Reaching for `JSONEncoder`/`JSONDecoder`, writing Codable glue → `FOSFoundation.md § Coding`
- Reaching for `DateFormatter`/`ISO8601DateFormatter` for wire or JSON dates → `FOSFoundation.md § Coding`
- Building stub/test instances of Codable types → `FOSFoundation.md § Coding`, `FOSTesting.md § FOSTesting`
- Reaching for `URLSession`/`URLRequest`, fetching or posting Codable data → `FOSFoundation.md § Networking`
- Reaching for `URLSessionWebSocketTask` → `FOSFoundation.md § Networking`
- Mocking network calls in tests → `FOSFoundation.md § Networking`, `FOSTesting.md § FOSTesting`
- Backing off when a service says to wait (rate limits, `Retry-After`), or turning a REST service's own error responses into rich errors → `FOSFoundation.md § Networking`
- Grouping an array into a dictionary, or rate-limiting (throttling) iteration → `FOSFoundation.md § Collections`
- Converting string casing (camel/snake), trimming prefixes/suffixes, generating random strings → `FOSFoundation.md § String`
- Hashing (SHA-256/HMAC), obfuscating strings, parsing hex strings or CSV files → `FOSFoundation.md § String`
- Rounding doubles, or formatting integers as hex → `FOSFoundation.md § Numbers`
- Comparing or parsing app/API versions (semver) → `FOSFoundation.md § Versioning`
- Reaching for semaphores in async code, or calling async code from a sync context → `FOSFoundation.md § Async`
- Detecting simulator/TestFlight installs, reading the app bundle's version → `FOSFoundation.md § Extensions`
- Typing a model identifier (never a raw `UUID`/`String` field) → `FOSFoundation.md § Data`
- Declaring a ViewModel or versioning its factory (`@ViewModel`, `@VersionedFactory`) → `FOSMVVM.md § Macros`
- Localizing properties from YAML (`@LocalizedString`), substituting values into localized text → `FOSMVVM.md § Localization`
- Showing an enum case as a localized word, or a picker over an enum → `FOSMVVM.md § Localization` (`LocalizableCase`)
- Localizing a type of your own through the localizing encoder → `FOSMVVM.md § Localization` (`localized(in:store:)`)
- Encoding a ViewModel with its localizations resolved → `FOSMVVM.md § Extensions`
- Describing form fields — control type, keyboard, input constraints, value binding → `FOSMVVM.md § Forms`
- Minting a field identity from the property it names (`#fieldId`) → `FOSMVVM.md § Forms`
- Validating user input, reporting and aggregating validation outcomes → `FOSMVVM.md § Validation`
- A validation message about the whole form rather than one control — reporting it, and showing it above the form → `FOSMVVM.md § Validation`, `§ SwiftUI Support`
- Binding a screen to server data — ViewModel requests, CRUD writes, factories → `FOSMVVM.md § Protocols`
- Deleting an entity — archiving it (marked deleted, still there) versus destroying it (removed) → `FOSMVVM.md § Protocols`, `FOSMVVMVapor.md § Vapor Support`
- Identifying *which* entity a model is (opaque `ModelIdentity`) — keying refresh or authorization by it → `FOSMVVM.md § Protocols`
- Authorization — declaring containers, the grant that names a model and what it extends to its members, the model-level and container-level verbs → `FOSMVVM.md § Protocols`
- Loading what a subject's grants reach with no container to name (a top-level list, a write whose target may be granted directly or through its container) → `FOSMVVM.md § Protocols`
- Client-chosen sort or pagination on a request → `FOSMVVM.md § Protocols`
- Live-updating screens that refresh when server data changes (`@ViewModel(options: [.live])`), or replacing the invalidation transport → `FOSMVVM.md § Protocols`, `FOSMVVMVapor.md § Live Invalidation`
- Attaching auth headers (bearer token, API key) to every client request, rotation-safe — or recovering when the server refuses one (refresh the credential and retry the request once) → `FOSMVVM.md § Protocols`
- Declaring the data a server-rendered body needs — composable factory, loading plans, containment scopes → `FOSMVVM.md § Protocols`
- Rendering a ViewModel in SwiftUI — app setup, view binding, previews, form views → `FOSMVVM.md § SwiftUI Support`
- A Button whose action is `async throws` — error routing, re-entry refusal, running state, tap-to-cancel → `FOSMVVM.md § SwiftUI Support`
- A view-lifetime (or value-keyed) load that can throw — `.task`-style error routing into the screen binding → `FOSMVVM.md § SwiftUI Support`
- Showing errors to the user — localized error messages on error types, one alert fed by a shared error binding → `FOSMVVM.md § Protocols`, `§ SwiftUI Support`
- Versioning ViewModel properties, choosing deployment URLs, negotiating versions over HTTP → `FOSMVVM.md § Versioning`
- Booting a Vapor server for MVVM — YAML localization store, environment, locale, Leaf rendering → `FOSMVVMVapor.md § Extensions`
- Registering request routes (reads and CRUD writes) — including mounting one behind a credential/middleware group — or serving a request outside the guarded verbs → `FOSMVVMVapor.md § Vapor Support`
- Projecting loaded records into a response body, or reading them through the projection context → `FOSMVVMVapor.md § Containment`, `§ Protocols`
- Declaring Fluent containers and their relations, or mapping sort meanings to database columns → `FOSMVVMVapor.md § Containment`
- Registering the model authorization provider, the application scope, per-request app state, or a model's migration → `FOSMVVMVapor.md § Containment`, `§ Extensions`
- A model no other model owns — a top-level list, a system-wide row, creating a top-level container — without a synthetic parent → `FOSMVVMVapor.md § Containment`
- Rules that run whenever a model is saved — uniqueness against other models, deriving fields before the write, work in the same transaction, a side effect once it commits → `FOSMVVMVapor.md § Lifecycle`
- Turning a database constraint failure into a message the user can act on, or making a warning stop a save → `FOSMVVMVapor.md § Lifecycle`
- Filtering (narrowing) a large container load by the request's query → `FOSMVVMVapor.md § Containment`
- Enabling server-pushed refresh at boot, or transactional writes that notify live clients → `FOSMVVMVapor.md § Live Invalidation`
- Refreshing live screens whose data isn't Fluent-persisted — nudging from an `Application`-hosted actor or computed aggregate, or registering a dependency the load plan can't see → `FOSMVVMVapor.md § Live Invalidation`
- The server-side write path — candidate set, field application, authorization provider, the subject's identity for live grant refresh → `FOSMVVMVapor.md § Protocols`
- Projecting the database into ViewModels — resolvable requests, Fluent `DataModel` → `FOSMVVMVapor.md § Protocols`
- Sending Apple push notifications from the server (localized per device, badge-only for tvOS, retired-token cleanup) — behind the `APNs` trait → `FOSMVVMVapor.md § Push Notifications`
- Asking for notification permission and sending the app's device token to its server → `FOSMVVM.md § Push Notifications`
- Serving typed/localized errors, gating routes on client app version → `FOSMVVMVapor.md § Middleware`
- Verifying a caller's bearer token / protecting route groups with app-owned credential rules → `FOSMVVMVapor.md § Middleware`
- Testing ViewModels — Codable round-trip, version stability, translation coverage → `FOSTesting.md § FOSTesting`
- UI-testing SwiftUI ViewModel views (XCUITest hosting, operations, identifiers, keyboard dismissal) → `FOSTesting.md § FOSTestingUI`, `FOSMVVM.md § SwiftUI Support`
- Testing Vapor ServerRequests end to end, or Fluent-backed code against a fresh in-memory database → `FOSTesting.md § FOSTestingVapor`
- Testing a streaming / SSE endpoint over a real socket → `FOSTesting.md § FOSTestingVapor`
- Generating PDFs from SwiftUI views, choosing page size/orientation → `FOSReporting.md § PDF Rendering`
