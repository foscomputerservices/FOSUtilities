# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Run all tests
swift test

# Run a single test (Swift Testing)
swift test --filter TestClassName

# Format code (auto-adds Apache 2.0 license header)
swiftformat .

# Lint code
swiftlint
```

## Architecture Overview

FOSUtilities is a Swift Package providing MVVM infrastructure for binding SwiftUI apps to Vapor web services, plus foundation utilities and testing support.

### SOLID Is the Foundation

FOSUtilities and every `fosmvvm-*` generator skill are built on the SOLID principles.
**Deviations from SOLID cause catastrophic failures** — they surface far from their cause
(runtime type-identity mismatches, leaked persistence types, SwiftUI identity churn), so
treat a SOLID violation as a hard stop, not a style nit.

- **Source-of-truth ordering when guidance conflicts:** SOLID → the architecture docs
  (`.claude/docs/FOSMVVMArchitecture.md`) → code. If a request or an existing pattern
  conflicts with SOLID, SOLID wins.
- **Generator skills must remind their user of SOLID.** When authoring or editing a
  `fosmvvm-*` skill, don't just show the API — state *which SOLID principle the pattern
  protects and what breaks on deviation*, so a builder tempted to "simplify" sees the red
  flag inline.
- SOLID in FOSUtilities' terms: **SRP** (one file/type/responsibility; a ViewModel is a
  *projection of* data, never the data); **OCP** (extend via protocols + macros, don't
  patch the core); **LSP** (type identity must hold across target boundaries — the
  `SPMLibraries` umbrella); **ISP** (the module *is* the namespace; small composable
  protocols, not one fat contract); **DIP** (the ViewModel module never imports the
  domain/wire module — the Factory adapts).

### Library Hierarchy

```
FOSFoundation          - Base utilities (URL/JSON extensions, async helpers, string utils)
    ↓
FOSMVVM               - MVVM pattern implementation with localization support
    ↓                   (uses FOSMacros for @ViewModel, @LocalizedString, etc.)
    ├→ FOSMVVMVapor    - Vapor server integration (macOS/Linux only)
    ├→ FOSReporting    - PDF generation (Apple platforms only)
    └→ FOSTestingUI    - SwiftUI test utilities
         ↓
FOSTesting            - Test base classes and mocking
    ↓
FOSTestingVapor       - Vapor-specific test support (macOS/Linux only)
```

### Key Patterns

**ViewModel Declaration:**
```swift
@ViewModel
public struct MyViewModel: RequestableViewModel {
    public typealias Request = MyRequest
    @LocalizedString public var title
    public var vmId = ViewModelId()
    public init() {}
    public static func stub() -> Self { .init() }
}
```

**Localization:** YAML-based stores (see `Sources/FOSMVVM/Localization/`). Properties use `@LocalizedString`, `@LocalizedInt`, `@LocalizedDate` wrappers.

**Macros:** `FOSMacros` provides `@ViewModel`, `@FieldValidationModel`, `@ViewModelFactory` - only compile on macOS/Linux.

### Platform Constraints

- Swift 6.0+ required (`swiftLanguageModes: [.v6]`)
- `FOSMVVMVapor` / `FOSTestingVapor`: macOS/Linux only
- `FOSReporting`: Apple platforms only (iOS, macOS, visionOS, watchOS)
- `FOSMacros`: macOS/Linux/Windows only (macro compilation)

### Test Notes

- Uses Swift Testing framework (not XCTest), except macro tests which require XCTest
- Test YAML fixtures located in `Tests/FOSMVVMTests/TestYAML/` and `Tests/FOSMVVMVaporTests/TestYAML/`

## Governance Context

### Challenge Response Protocol
When a `<governance-challenge>` block appears in hook output, you MUST:
1. **Acknowledge it explicitly** before responding to the user
2. **Address the substance** of what the challenge raises
3. **State your decision** on how to proceed

Do not skip past challenges. They exist to create reflection at decision points.

### Principles
- **[Architecture] Production Systems Require Type Safety** (firm): Production software shall be developed using strongly-typed languages that enable compile-time verification. Dynamic or untyped scripting languages are strongly discouraged for production systems.
- **[Architecture] Existential Types Are a Code Smell** (firm): Swift existential types (`any Protocol`) should be treated as a code smell - a BIG RED FLAG that demands the question: "Is there any other way?" Existentials have legitimate uses, but they come with performance and type-safety costs.
- **[Architecture] Fields Protocols Define Form Contracts Only** (project): Fields protocols (e.g., DocumentFields, UserFields) define the user-editable form contract: validation rules, localized messages, and input handling. They must NOT contain ModelIdType fields.
- **[Architecture] ModelIdType Requires Junction Tables Except for @ID** (project): Using ModelIdType (UUID) in any field other than @ID() MUST be expressly approved and documented. Raw UUID fields bypass type safety and referential integrity.
- **[Architecture] Code is Artifact, Architecture is Truth** (firm): Code is an artifact - an output of the development process. Architecture and design documents are the source of truth. Never reverse-engineer design intent from code alone.
- **[Quality] Development Velocity is Lifetime Velocity** (firm): "Development velocity" means how fast can I make correct changes over the lifetime of the project, not how fast can I get something working initially.
- **[Quality] Tests Must Never Modify Production Data** (firm): Tests and validation scenarios SHALL NOT modify, delete, or corrupt production data. Read-only by default.

### Relevant Lessons
- **Swift Testing: Suites using shared singletons need .serialized** [swift-testing, concurrency] (gotcha): When test suites use a shared singleton, they MUST be marked with `.serialized` to prevent race conditions. Swift Testing runs suites in parallel by default.
- **Singletons make testing unreliable - use dependency injection** [singleton, testing] (gotcha): Shared singletons cause test flakiness: tests can't run in parallel safely, state leaks between tests, `clearState()` in one test affects another running concurrently.
- **Test failures showing 0 for recorded values often indicate shared state race** [testing, debugging] (gotcha): When tests record values but assertions see 0 or initial values, the likely cause is another test clearing shared state between recording and assertion.
- **ViewModel Children: Embedded vs Request-Based Relationships** [viewmodel, architecture] (pattern): Embedded children = single fetch, stale after mutation. Request-based = always fresh, extra requests. Choose based on freshness vs simplicity needs.
- **ViewModel Identity: id vs vmId separation** [viewmodel, identity] (pattern): `id: ModelIdType` = data identity (which database entity). `vmId: ViewModelId` = SwiftUI rendering identity. Only `id` round-trips through requests.
- **RequestBody composes ServerRequestBody + Fields** [request, fields] (pattern): For CRUD operations, RequestBody composes ServerRequestBody + Fields + ValidatableModel + Stubbable.
- **FOSMVVM Request hierarchy** [request, crud] (pattern): ServerRequest (HTTP-aligned) → CRUD protocols (CreateRequest, UpdateRequest, etc.) → Concrete requests. CRUD protocols are separate because not every entity supports all operations.
- **Web browser is not a separate client - it's the UI layer of WebApp** [architecture, web] (gotcha): With server-side rendering (Vapor/Leaf), the browser is the UI layer of the WebApp, not a separate client calling your API.
- **The shared module pattern must be explicitly documented** [architecture, fosmvvm] (pattern): FOSMVVM projects require a shared module (ServerRequests, ViewModels, Fields, SystemVersion) that all targets import.
- **CLI tools are invisible boundary violators** [cli, boundaries, fosmvvm] (gotcha): Architectural boundary rules focusing on JS/TS accidentally give CLI tools a pass. CLI tools must also go through ServerRequests.
- **Defer API Until Client Exists** [api-design, yagni] (decision): Ask "What client will consume this?" before building API layers. Don't build APIs without consumers.
- **Always write code as if it's production** [quality] (practice): "It's not production yet" is how technical debt accumulates. Prototypes become production code.
- **Skill documentation must show the complete DRY pattern, not just the API** [skills, documentation] (practice): Show the complete pattern developers should use, not raw API surfaces.
- **Bump plugin version when updating skill documentation** [plugins, versioning] (practice): Plugin version must be bumped when skill docs change so users receive updates.
