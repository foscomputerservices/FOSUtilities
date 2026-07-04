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
- Encoding a ViewModel with its localizations resolved → `FOSMVVM.md § Extensions`
- Describing form fields — control type, keyboard, input constraints, value binding → `FOSMVVM.md § Forms`
- Validating user input, reporting and aggregating validation outcomes → `FOSMVVM.md § Validation`
- Binding a screen to server data — ViewModel requests, CRUD writes, factories → `FOSMVVM.md § Protocols`
- Rendering a ViewModel in SwiftUI — app setup, view binding, previews, form views → `FOSMVVM.md § SwiftUI Support`
- Versioning ViewModel properties, choosing deployment URLs, negotiating versions over HTTP → `FOSMVVM.md § Versioning`
- Booting a Vapor server for MVVM — YAML localization store, environment, locale, Leaf rendering → `FOSMVVMVapor.md § Extensions`
- Registering Vapor routes that serve ViewModels or host CRUD writes → `FOSMVVMVapor.md § Vapor Support`
- Projecting the database into ViewModels — Vapor factories, resolvable requests, Fluent `DataModel` → `FOSMVVMVapor.md § Protocols`
- Serving typed/localized errors, gating routes on client app version → `FOSMVVMVapor.md § Middleware`
- Testing ViewModels — Codable round-trip, version stability, translation coverage → `FOSTesting.md § FOSTesting`
- UI-testing SwiftUI ViewModel views (XCUITest hosting, operations, identifiers) → `FOSTesting.md § FOSTestingUI`, `FOSMVVM.md § SwiftUI Support`
- Testing Vapor ServerRequests end to end → `FOSTesting.md § FOSTestingVapor`
- Generating PDFs from SwiftUI views, choosing page size/orientation → `FOSReporting.md § PDF Rendering`
