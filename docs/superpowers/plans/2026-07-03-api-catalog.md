# FOSUtilities API Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the curated, reach-for-indexed API catalog + discovery/update skills + symbol-graph audit script + CI check specified in `docs/superpowers/specs/2026-07-03-api-catalog-design.md`.

**Architecture:** Curated per-library markdown catalog under `.claude/skills/shared/api-catalog/` (plugin-shipped), fronted by a reach-for index in a new discovery skill and CLAUDE.md blocks; freshness enforced by a Swift audit script that diffs the catalog against `swift package dump-symbol-graph` output, run in CI and by a new update skill.

**Tech Stack:** Swift (Foundation-only script, run via `swift Scripts/...`), SwiftPM symbol graphs, Claude Code skills (markdown), GitHub Actions.

**Read first:** the spec (`docs/superpowers/specs/2026-07-03-api-catalog-design.md`) — it defines the entry format, granularity rules, and exit-code policy this plan implements. Then `.claude/CLAUDE.md` (encapsulation rules, documentation-audience rules).

## Decisions reconciled against reality (deviations from spec letter)

1. **CI job placement.** Spec said "the existing `macos-latest` job." Reality: that job uses xcodebuild *because `swift build` hangs on macOS runners* (comment in `ci.yml`), and `dump-symbol-graph` is a SwiftPM build. The audit therefore runs in the existing **ubuntu** `run_tests` job (reusing its `.build` from `swift test`). Consequence: FOSReporting (Apple-only) has no symbol graph on Linux — the script **skips stale-checking any catalog file whose covered modules aren't all present** and prints an info line. Full-surface auditing happens locally on macOS via the update skill.
2. **Plain `swift` instead of swift-sh.** The script needs only Foundation, so it runs via `swift scripts/api-catalog-audit.swift` with no swift-sh install requirement in CI (no shebang needed). If third-party deps ever become necessary, convert to swift-sh (with the `"\u{23}!"` shebang workaround).
3. **No unit-test target for the script.** Per spec Verification: deterministic script, fixture tests optional; the **planted round-trip check** (Task 1) is the required verification, repeated before CI enablement (Task 10).
4. **One format checkpoint, not one per file.** Spec Component 7 says "a checkpoint per catalog file"; this plan uses one hard review checkpoint after the first file (Task 2, where format/voice is settled) — Tasks 3–6 then follow the approved format, and David reviews the full catalog at the Task 11 verification. Rationale: the risk is format drift, and that is decided in file one.

## Working-tree warning

The working tree contains unrelated in-progress modifications (`.claude/skills/*`, `plugin.json`, etc.). **`git add` only the exact paths listed in each task's commit step — never `git add -A` / `git add .`**

## File structure

```
scripts/api-catalog-audit.swift                          create  (audit script)
scripts/api-catalog-ignore.txt                           create  (deliberate exclusions)
.claude/skills/shared/api-catalog/FOSFoundation.md       create  (Task 2)
.claude/skills/shared/api-catalog/FOSMVVM.md             create  (Task 3)
.claude/skills/shared/api-catalog/FOSTesting.md          create  (Task 4; covers FOSTesting, FOSTestingUI, FOSTestingVapor)
.claude/skills/shared/api-catalog/FOSMVVMVapor.md        create  (Task 5)
.claude/skills/shared/api-catalog/FOSReporting.md        create  (Task 6)
.claude/skills/fosutilities-api-catalog/SKILL.md         create  (discovery skill, reach-for index)
.claude/skills/fosutilities-api-catalog-update/SKILL.md  create  (update skill; owns the entry-format rules)
.claude/skills/fosmvvm-*/SKILL.md                        modify  (one-line catalog pointers)
.claude/CLAUDE.md                                        modify  (reach-for index block)
.claude/skills/fosmvvm-swiftui-app-setup/SKILL.md        modify  (consumer CLAUDE.md variant)
.github/workflows/ci.yml                                 modify  (audit step, ubuntu job)
.claude-plugin/plugin.json                               modify  (version 2.6.0 → 2.7.0; adjust if already bumped)
```

---

### Task 1: Audit script

**Files:**
- Create: `scripts/api-catalog-audit.swift`
- Create: `scripts/api-catalog-ignore.txt`

- [ ] **Step 1: Write the script**

```swift
// api-catalog-audit.swift
//
// Compares the package's public API surface (via `swift package dump-symbol-graph`)
// against the curated catalog in .claude/skills/shared/api-catalog/.
//
// Usage (from the package root):
//   swift scripts/api-catalog-audit.swift [--symbolgraph-dir <dir>]
//
// Reports:
//   - Catalog gaps  (warning): public API not mentioned in any catalog entry title
//   - Stale entries (ERROR):   catalog title symbols no longer present in the API
//   - DocC worklist (warning): audit-surface symbols with no doc comment
//
// Exit code 1 only on stale entries — a catalog that lies is worse than one
// that's incomplete.
//
// The audit's input is ONLY the files under .claude/skills/shared/api-catalog/
// (never SKILL.md bodies or CLAUDE.md indexes), and within them ONLY backticked
// symbols on "### " entry-title lines. Matching is by base identifier,
// arity-insensitive.

import Foundation

// MARK: - Configuration

let catalogDir = ".claude/skills/shared/api-catalog"
let ignoreFile = "scripts/api-catalog-ignore.txt"

let moduleToCatalog: [String: String] = [
    "FOSFoundation": "FOSFoundation.md",
    "FOSMVVM": "FOSMVVM.md",
    "FOSMVVMVapor": "FOSMVVMVapor.md",
    "FOSTesting": "FOSTesting.md",
    "FOSTestingUI": "FOSTesting.md",
    "FOSTestingVapor": "FOSTesting.md",
    "FOSReporting": "FOSReporting.md",
]

// Top-level declarations that require a catalog entry (or a catalogued parent).
let topLevelKinds: Set<String> = [
    "swift.struct", "swift.class", "swift.enum", "swift.protocol",
    "swift.typealias", "swift.func", "swift.var",
]

// Members added by extensions to external types (String, URL, Encodable, ...) —
// the most invisible API. Inits, operators, and enum cases are excluded: their
// base names are meaningless for matching.
let extensionMemberKinds: Set<String> = [
    "swift.method", "swift.property", "swift.type.method",
    "swift.type.property", "swift.func", "swift.typealias",
]

// MARK: - Symbol graph model

struct SymbolGraph: Decodable { let symbols: [Symbol] }

struct Symbol: Decodable {
    struct Kind: Decodable { let identifier: String }
    struct DocComment: Decodable {}
    struct Location: Decodable { let uri: String? }

    let accessLevel: String
    let kind: Kind
    let pathComponents: [String]
    let docComment: DocComment?
    let location: Location?

    var isPublic: Bool { accessLevel == "public" || accessLevel == "open" }
    var baseName: String { baseIdentifier(pathComponents.last ?? "") }
    var sourceFile: String {
        guard let uri = location?.uri, let range = uri.range(of: "Sources/") else { return "?" }
        return String(uri[range.lowerBound...])
    }
}

/// `fromJSON(_:)` -> `fromJSON`; `Array<T>` -> `Array`
func baseIdentifier(_ raw: String) -> String {
    guard let cut = raw.firstIndex(where: { $0 == "(" || $0 == "<" }) else { return raw }
    return String(raw[..<cut])
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: - Symbol graph generation / loading

func symbolGraphDir() throws -> URL {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--symbolgraph-dir"), i + 1 < args.count {
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    print("Running `swift package dump-symbol-graph` (builds the package; may take a while)...")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["swift", "package", "dump-symbol-graph", "--skip-synthesized-members"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.standardError
    try proc.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { throw Failure("dump-symbol-graph failed") }

    let output = String(decoding: data, as: UTF8.self)
    guard let line = output.split(separator: "\n").last(where: { $0.contains("Files written to ") }),
          let range = line.range(of: "Files written to ") else {
        throw Failure("could not find 'Files written to' in dump-symbol-graph output")
    }
    return URL(fileURLWithPath: String(line[range.upperBound...])
        .trimmingCharacters(in: .whitespaces), isDirectory: true)
}

struct AuditItem {
    let module: String
    let name: String        // base identifier
    let parent: String?     // extended/enclosing type's base identifier, if any
    let hasDoc: Bool
    let sourceFile: String
}

struct ModuleSurface {
    var auditItems: [AuditItem] = []
    var allNames: Set<String> = []  // every identifier at any depth (stale-match universe)
}

func loadSurfaces(from dir: URL) throws -> [String: ModuleSurface] {
    var surfaces: [String: ModuleSurface] = [:]
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasSuffix(".symbols.json") }

    for file in files {
        // "FOSFoundation.symbols.json" or "FOSFoundation@Swift.symbols.json"
        let stem = file.lastPathComponent.replacingOccurrences(of: ".symbols.json", with: "")
        let parts = stem.split(separator: "@", maxSplits: 1)
        let module = String(parts[0])
        let isExtensionGraph = parts.count == 2
        guard moduleToCatalog[module] != nil else { continue }

        let graph = try JSONDecoder().decode(SymbolGraph.self, from: Data(contentsOf: file))
        var surface = surfaces[module] ?? ModuleSurface()

        for symbol in graph.symbols where symbol.isPublic {
            for component in symbol.pathComponents {
                surface.allNames.insert(baseIdentifier(component))
            }
            if isExtensionGraph {
                guard extensionMemberKinds.contains(symbol.kind.identifier) else { continue }
                surface.auditItems.append(AuditItem(
                    module: module,
                    name: symbol.baseName,
                    parent: baseIdentifier(symbol.pathComponents.first ?? ""),
                    hasDoc: symbol.docComment != nil,
                    sourceFile: symbol.sourceFile))
            } else if symbol.pathComponents.count == 1,
                      topLevelKinds.contains(symbol.kind.identifier) {
                surface.auditItems.append(AuditItem(
                    module: module,
                    name: symbol.baseName,
                    parent: nil,
                    hasDoc: symbol.docComment != nil,
                    sourceFile: symbol.sourceFile))
            }
        }
        surfaces[module] = surface
    }
    return surfaces
}

// MARK: - Catalog parsing

/// Backticked symbols on "### " entry-title lines only; each backtick span may
/// name several identifiers (`ViewModelId.Freshness`, `fromJSON()` / `toJSON()`).
func catalogTitleNames(in text: String) -> Set<String> {
    var names: Set<String> = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false)
        where line.hasPrefix("### ") {
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "`") {
            rest = rest[rest.index(after: open)...]
            guard let close = rest.firstIndex(of: "`") else { break }
            let span = rest[..<close]
            rest = rest[rest.index(after: close)...]
            for token in span.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }) {
                let name = baseIdentifier(String(token))
                if !name.isEmpty, name.first!.isLetter || name.first! == "_" {
                    names.insert(name)
                }
            }
        }
    }
    return names
}

func loadCatalog() throws -> [String: Set<String>] {
    var byFile: [String: Set<String>] = [:]
    let dir = URL(fileURLWithPath: catalogDir, isDirectory: true)
    guard FileManager.default.fileExists(atPath: dir.path) else { return byFile }
    for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where file.pathExtension == "md" {
        byFile[file.lastPathComponent] =
            catalogTitleNames(in: try String(contentsOf: file, encoding: .utf8))
    }
    return byFile
}

func loadIgnoreList() -> Set<String> {
    guard let text = try? String(contentsOfFile: ignoreFile, encoding: .utf8) else { return [] }
    return Set(text.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") })
}

// MARK: - Main

do {
    let surfaces = try loadSurfaces(from: try symbolGraphDir())
    let catalog = try loadCatalog()
    let ignored = loadIgnoreList()
    let catalogNames = catalog.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    let presentModules = Set(surfaces.keys)

    var gaps: [AuditItem] = []
    var docWorklist: [AuditItem] = []
    for (_, surface) in surfaces.sorted(by: { $0.key < $1.key }) {
        for item in surface.auditItems where !ignored.contains(item.name) {
            let covered = catalogNames.contains(item.name)
                || item.parent.map { catalogNames.contains($0) } ?? false
            if !covered { gaps.append(item) }
            if !item.hasDoc { docWorklist.append(item) }
        }
    }

    // Stale entries: title symbols not found anywhere in the loaded API surface.
    // Only checked for catalog files whose covered modules are ALL present
    // (on Linux, FOSReporting has no symbol graph — its file is skipped).
    var stale: [(file: String, name: String)] = []
    for (file, names) in catalog.sorted(by: { $0.key < $1.key }) {
        let covered = moduleToCatalog.filter { $0.value == file }.map(\.key)
        guard !covered.isEmpty else {
            print("info: \(file) maps to no module — skipping stale check")
            continue
        }
        guard covered.allSatisfy(presentModules.contains) else {
            print("info: skipping stale check for \(file) — module(s) " +
                "\(covered.filter { !presentModules.contains($0) }.joined(separator: ", ")) " +
                "not built on this platform")
            continue
        }
        let universe = covered.reduce(into: Set<String>()) { $0.formUnion(surfaces[$1]?.allNames ?? []) }
        for name in names.sorted() where !universe.contains(name) && !ignored.contains(name) {
            stale.append((file, name))
        }
    }

    print("\n== Catalog gaps (warning): public API with no catalog entry ==")
    for g in gaps { print("  \(g.module): \(g.name)  [\(g.sourceFile)]") }
    print("\n== Stale catalog entries (ERROR): title symbols not in the API ==")
    for s in stale { print("  \(s.file): `\(s.name)`") }
    print("\n== DocC worklist (warning): audit-surface symbols with no doc comment ==")
    for d in docWorklist { print("  \(d.module): \(d.name)  [\(d.sourceFile)]") }
    print("\nSummary: \(gaps.count) gap(s), \(stale.count) stale, \(docWorklist.count) undocumented; " +
        "modules audited: \(presentModules.sorted().joined(separator: ", "))")

    exit(stale.isEmpty ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(2)
}
```

- [ ] **Step 2: Create the ignore file**

`scripts/api-catalog-ignore.txt`:

```
# api-catalog-audit ignore list — one base identifier per line.
# Symbols listed here are deliberately excluded from catalog-gap, stale-entry,
# and DocC-worklist reporting (e.g., deprecated API kept for compatibility).
```

- [ ] **Step 3: Run against the real package and verify behavior**

```bash
swift package dump-symbol-graph --skip-synthesized-members   # note the "Files written to <dir>" path
swift scripts/api-catalog-audit.swift --symbolgraph-dir <dir>
```

Expected: no crash; catalog dir doesn't exist yet, so **every** audit-surface symbol reports as a gap (spot-check that known symbols appear, e.g. `AsyncSemaphore`, `DataFetch`, `SystemVersion`, and extension members like `fromJSON`); 0 stale; DocC worklist populated; exit code 0 (`echo $?`).

- [ ] **Step 4: Planted round-trip check (required by spec)**

```bash
mkdir -p .claude/skills/shared/api-catalog
printf '## Coding\n\n### Frobnication — `frobnicate()`\nReach for this when: never.\n' \
  > .claude/skills/shared/api-catalog/FOSFoundation.md
swift scripts/api-catalog-audit.swift --symbolgraph-dir <dir>; echo "exit: $?"
```

Expected: `FOSFoundation.md: \`frobnicate\`` under stale entries; `exit: 1`. Also verify a real symbol used as a title (`### Semaphore — \`AsyncSemaphore\``) makes `AsyncSemaphore` disappear from gaps and does NOT report stale. Then delete the test file:

```bash
rm .claude/skills/shared/api-catalog/FOSFoundation.md
```

- [ ] **Step 5: Commit**

```bash
git add scripts/api-catalog-audit.swift scripts/api-catalog-ignore.txt
git commit -m "feat(scripts): add api-catalog-audit symbol-graph audit script"
```

---

### Task 2: Populate `FOSFoundation.md` (CHECKPOINT — review before Tasks 3–6)

**Files:**
- Create: `.claude/skills/shared/api-catalog/FOSFoundation.md`

This task establishes the format all other catalog files copy. **Entry-format rules (from the spec — binding):**

1. `##` category headers mirror the source folders: Async, Coding, Collections, Data, Extensions, Networking, Numbers, String, Versioning. Each opens with 1–2 orientation sentences.
2. `###` title is **task-framed** ("Codable JSON round-trip"), with the entry's own symbols in backticks **in the title line** — the only place the audit matches. Never backtick stdlib/Foundation types in titles (prose/examples are fine — the audit ignores them).
3. Mandatory "Reach for this when:" line; optional "Don't:" line naming the reinvention it replaces.
4. Example: 2–4 lines, idiomatic, copyable.
5. **Contracts, never representations** — no encoded shapes, token formats, byte layouts.
6. One entry may cover a small family reached for as one capability (put every family symbol in the title backticks so each is freshness-matched).

Canonical example (from the spec):

````markdown
### Codable JSON round-trip — `fromJSON()` / `toJSON()`
Reach for this when: converting any Codable to/from JSON strings or Data.
Don't hand-roll `JSONDecoder` configuration — these apply the library's standard
coding strategy (dates, keys) consistently with the server.

```swift
let user: User = try jsonString.fromJSON()
let json = try user.toJSON()
```
````

- [ ] **Step 1: Generate the checklist** — run the audit (Task 1 Step 3 command); collect the FOSFoundation gap list.
- [ ] **Step 2: Write the file, category by category.** For each gap symbol: read its source under `Sources/FOSFoundation/<Category>/`, understand intent (read the DocC if present, but expect it missing — write from the code's evident purpose and idiomatic call site), write the entry per the rules above. Group families. If a symbol shouldn't be catalogued (deprecated, internal-ish), add it to `scripts/api-catalog-ignore.txt` with a `#` reason comment instead.
- [ ] **Step 3: Re-run the audit.** Expected: FOSFoundation gaps → 0 (or every remainder deliberately in the ignore file); 0 stale; exit 0.
- [ ] **Step 4: Self-review** each entry against rules 2/3/5 (title task-framed? reach-for line present? no representation leaks?).
- [ ] **Step 5: Commit**

```bash
git add .claude/skills/shared/api-catalog/FOSFoundation.md scripts/api-catalog-ignore.txt
git commit -m "docs(api-catalog): populate FOSFoundation catalog"
```

**CHECKPOINT:** David reviews this file's format/voice before the remaining catalog files are written.

---

### Task 3: Populate `FOSMVVM.md`

**Files:** Create: `.claude/skills/shared/api-catalog/FOSMVVM.md`

Same steps as Task 2 (checklist → write → audit-clean → self-review → commit). Category headers mirror `Sources/FOSMVVM/` folders. Notes:
- Include the **macro-exposed surface** (`@ViewModel`, `@LocalizedString`, `@FieldValidationModel`, `@ViewModelFactory`, …) — that's how customers actually reach FOSMVVM; macros won't all appear in the gap report, so sweep `Sources/FOSMacros` exports for the user-facing attribute list. If a macro name backticked in a `###` title reports **stale** (macro declarations usually appear in symbol graphs, but verify), add it to the ignore file with a reason comment rather than un-titling it.
- Where an entry documents a pattern the generator skills scaffold, keep the entry to the API contract and reach-for framing; do not duplicate generator-skill content (DRY — one line "scaffolded by `fosmvvm-viewmodel-generator`" is enough).

```bash
git add .claude/skills/shared/api-catalog/FOSMVVM.md scripts/api-catalog-ignore.txt
git commit -m "docs(api-catalog): populate FOSMVVM catalog"
```

---

### Task 4: Populate `FOSTesting.md`

**Files:** Create: `.claude/skills/shared/api-catalog/FOSTesting.md`

Same steps. Covers three modules — use `##` top-level sections per module (FOSTesting, FOSTestingUI, FOSTestingVapor), categories nested as needed. Reach-for framing matters most here ("mocking URLSession", "testing a ServerRequest", "UI-test identifiers").

```bash
git add .claude/skills/shared/api-catalog/FOSTesting.md scripts/api-catalog-ignore.txt
git commit -m "docs(api-catalog): populate FOSTesting catalog"
```

---

### Task 5: Populate `FOSMVVMVapor.md`

**Files:** Create: `.claude/skills/shared/api-catalog/FOSMVVMVapor.md`

Same steps. Frame reaches from the Vapor implementor's POV ("registering ViewModel routes", "serving localized ViewModels", "Fluent model ↔ ViewModel factory").

```bash
git add .claude/skills/shared/api-catalog/FOSMVVMVapor.md scripts/api-catalog-ignore.txt
git commit -m "docs(api-catalog): populate FOSMVVMVapor catalog"
```

---

### Task 6: Populate `FOSReporting.md`

**Files:** Create: `.claude/skills/shared/api-catalog/FOSReporting.md`

Same steps (smallest surface). Note: on Linux this file is skipped by the stale check; audit it on macOS.

```bash
git add .claude/skills/shared/api-catalog/FOSReporting.md scripts/api-catalog-ignore.txt
git commit -m "docs(api-catalog): populate FOSReporting catalog"
```

---

### Task 7: Discovery skill (`fosutilities-api-catalog`)

**Files:** Create: `.claude/skills/fosutilities-api-catalog/SKILL.md`

- [ ] **Step 1: Write the skill.** Frontmatter follows the repo convention (cf. `fosmvvm-viewmodel-generator/SKILL.md`):

```markdown
---
name: fosutilities-api-catalog
description: Discover FOSUtilities APIs before writing helper code. Use when reaching for JSON/Codable encoding-decoding, URLSession/HTTP fetching, WebSockets, network mocking, collection utilities, string casing/crypto/obfuscation, hex/number formatting, version comparison, test stubbing, async coordination (semaphores, tasks), or FOSMVVM/Vapor/Testing surfaces — in any project that imports FOSFoundation, FOSMVVM, FOSMVVMVapor, FOSTesting, or FOSReporting.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🗂️", "os": ["darwin", "linux"]}}
---

# FOSUtilities API Catalog

Before hand-writing a helper in a project that imports these libraries, check
whether it already exists. Fifteen years of accumulated API lives here; the most
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

- Reaching for `JSONEncoder`/`JSONDecoder`, writing Codable glue → `FOSFoundation.md` § Coding
- Building stub/test instances of Codable types → `FOSFoundation.md` § Coding (Stubbable), `FOSTesting.md`
- Reaching for `URLSession`/`URLRequest`, fetching or posting data → `FOSFoundation.md` § Networking
- Reaching for `URLSessionWebSocketTask` → `FOSFoundation.md` § Networking
- Mocking network calls in tests → `FOSFoundation.md` § Networking, `FOSTesting.md`
- Deduplicating/transforming arrays and collections → `FOSFoundation.md` § Collections
- Reaching for string casing (camel/snake), hashing, obfuscation → `FOSFoundation.md` § String
- Formatting doubles/hex ints → `FOSFoundation.md` § Numbers
- Comparing/parsing app or API versions → `FOSFoundation.md` § Versioning
- Reaching for semaphores or task coordination in async code → `FOSFoundation.md` § Async
- Loading resources from bundles → `FOSFoundation.md` § Extensions
- Typed model identifiers (never raw UUID fields) → `FOSFoundation.md` § Data
- Building a ViewModel, localized properties, view models with requests → `FOSMVVM.md`
- Writing a Vapor route/controller that serves ViewModels → `FOSMVVMVapor.md`
- Testing ViewModels, ServerRequests, or SwiftUI views → `FOSTesting.md`
- Generating PDFs/reports on Apple platforms → `FOSReporting.md`
```

- [ ] **Step 2: Reconcile the index against the populated catalogs** (Tasks 2–6): every catalog category is reachable from at least one index line; every index line's `file § section` pointer resolves. Adjust lines to match the real section names.
- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosutilities-api-catalog/SKILL.md
git commit -m "feat(skills): add fosutilities-api-catalog discovery skill"
```

---

### Task 8: Update skill (`fosutilities-api-catalog-update`)

**Files:** Create: `.claude/skills/fosutilities-api-catalog-update/SKILL.md`

- [ ] **Step 1: Write the skill.** It owns the entry-format rules (moved verbatim from Task 2's list — single home, DRY; Task 2–6 authors worked from this plan, future authors work from this skill):

```markdown
---
name: fosutilities-api-catalog-update
description: Update the FOSUtilities API catalog after API changes. Runs the symbol-graph audit, fixes stale entries, writes curated entries for gaps, maintains the reach-for index, and bumps the plugin version. Use in the FOSUtilities repo when CI's catalog audit warns/fails, after adding or renaming public API, or when a reach-for index line is missing.
homepage: https://github.com/foscomputerservices/FOSUtilities
metadata: {"clawdbot": {"emoji": "🗃️", "os": ["darwin"]}}
---

# FOSUtilities API Catalog — Update

Keeps `.claude/skills/shared/api-catalog/` truthful and complete. Run on macOS
(full surface — Linux cannot build FOSReporting).

## Audit-driven workflow

1. Run: `swift scripts/api-catalog-audit.swift` (from the package root; builds
   the package, then reports gaps / stale entries / DocC worklist).
2. **Stale entries first** (these fail CI): the API changed — fix the entry's
   title symbols to the renamed API, or remove the entry if the API is gone.
3. **For each catalog gap**: read the source, then write a curated entry per the
   format rules below. If the symbol shouldn't be catalogued (deprecated,
   compatibility shim), add it to `scripts/api-catalog-ignore.txt` with a `#`
   reason comment instead — never leave a silent gap.
4. If a new entry serves a reach not yet in the discovery skill's reach-for
   index (`fosutilities-api-catalog/SKILL.md`), add the index line — keyed by
   what the implementor is reaching for, never by our layout.
5. Report the **DocC worklist** count (no DocC action in this workflow — it is
   the measurable backlog for the DocC effort).
6. Re-run the audit until: 0 stale, 0 non-ignored gaps, exit 0.
7. **Bump the plugin version** in `.claude-plugin/plugin.json` (consumers only
   receive catalog/skill updates on a version bump).

## Non-audit path: index and structure maintenance

- Adding/adjusting reach-for index lines for already-catalogued capabilities:
  edit the discovery skill directly, then do step 7.
- When renaming a `##` category section or splitting a catalog file, sweep the
  reach-for indexes (discovery skill + CLAUDE.md blocks) for dangling
  `file § section` pointers — pointers are not audited.

## Entry format rules (binding)

[rules 1–6 from Task 2, verbatim, plus the canonical example entry]

**Why these rules protect the architecture:** entries state *contracts, never
representations* — publishing an encoded shape on this (public, plugin-shipped)
surface would freeze internals forever (see CLAUDE.md, Encapsulation). Titles
are the audit's freshness anchor; prose backticks are ignored by design.
```

- [ ] **Step 2: Verify the referenced paths exist** (`scripts/api-catalog-audit.swift`, discovery skill, ignore file) and the rules block is the complete Task 2 list.
- [ ] **Step 3: Commit**

```bash
git add .claude/skills/fosutilities-api-catalog-update/SKILL.md
git commit -m "feat(skills): add fosutilities-api-catalog-update skill"
```

---

### Task 9: Wiring — generator-skill pointers, CLAUDE.md index, consumer variant

**Files:**
- Modify: `.claude/skills/fosmvvm-*/SKILL.md` (one line each; mapping below)
- Modify: `.claude/CLAUDE.md`
- Modify: `.claude/skills/fosmvvm-swiftui-app-setup/SKILL.md`

- [ ] **Step 1: Add one-line pointers** near the top of each generator skill (after the architecture-context blockquote, matching each file's existing link style):

> **API catalog:** check [`../shared/api-catalog/<file>.md`](../shared/api-catalog/<file>.md) § <sections> before hand-writing helpers.

Mapping (skill → catalog file(s) § relevant sections):
- viewmodel-generator, viewmodelrequest-generator, swiftui-view-generator, swiftui-app-setup, react-view-generator → `FOSMVVM.md`; viewmodel-generator also `FOSFoundation.md` § Coding (Stubbable)
- fields-generator → `FOSMVVM.md` (validation/fields sections)
- fluent-datamodel-generator, leaf-view-generator → `FOSMVVMVapor.md`; fluent also `FOSFoundation.md` § Data
- serverrequest-generator → `FOSMVVM.md` + `FOSFoundation.md` § Coding, § Networking
- serverrequest-test-generator, viewmodel-test-generator, ui-tests-generator → `FOSTesting.md`

- [ ] **Step 2: Add the reach-for index block to `.claude/CLAUDE.md`** (new `## API Catalog` section, ~10 lines): a condensed version of the discovery skill's index (one line per reach: JSON/Codable, URL/URLSession, WebSocket, collections, string utils, async, versioning, MVVM, Vapor serving, testing, reporting), each pointing at `.claude/skills/shared/api-catalog/<file>.md`, plus one line naming the two skills (`fosutilities-api-catalog` to discover, `fosutilities-api-catalog-update` to maintain).

- [ ] **Step 3: Add the consumer variant to `fosmvvm-swiftui-app-setup/SKILL.md`**: in its CLAUDE.md-seeding section, add an "API Discovery" block for the consumer's CLAUDE.md that references the discovery skill **by name only** ("before writing helpers for JSON/networking/strings/collections/testing, invoke the `fosutilities-api-catalog` skill") — **never a repo-relative path** (`shared/api-catalog/` lives inside the installed plugin, not the consumer's `.claude/skills/`).

- [ ] **Step 4: Verify** — every pointer path resolves (`ls` each referenced catalog file); consumer block contains no filesystem path.

- [ ] **Step 5: Commit** (exact files only — the working tree has unrelated skill edits; `git add` each file you touched by name, then `git diff --cached --stat` to confirm nothing unrelated slipped in):

```bash
git add .claude/CLAUDE.md .claude/skills/fosmvvm-swiftui-app-setup/SKILL.md <each generator SKILL.md you modified>
git diff --cached --stat   # verify: only your edits
git commit -m "docs(skills): wire API catalog into generator skills and CLAUDE.md indexes"
```

If a generator skill's file already has uncommitted unrelated edits, still commit the whole file only if those edits are yours from this task; otherwise surface to David before committing that file.

---

### Task 10: CI step

**Files:** Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Re-run the planted round-trip check** (Task 1 Step 4, against the now-populated catalog — plant the fake entry in a real file, expect exit 1, revert). Required before CI enablement.
- [ ] **Step 2: Add the audit step** to the `run_tests` job, after "Run Tests":

```yaml
      - name: API Catalog Audit
        if: matrix.os == 'ubuntu-latest'
        run: swift scripts/api-catalog-audit.swift
        shell: bash
```

(`dump-symbol-graph` reuses the job's `.build` from `swift test`. Stale entries → exit 1 → job fails; gaps/DocC worklist print as log warnings. FOSReporting is auto-skipped on Linux by the script.)

- [ ] **Step 3: Verify locally what CI will do**: `swift scripts/api-catalog-audit.swift; echo $?` → exit 0, 0 stale.
- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run api-catalog audit in ubuntu test job"
```

---

### Task 11: Plugin version bump + end-to-end verification

**Files:** Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version** `2.6.0` → `2.7.0` (if the working tree/main already moved past 2.6.0, bump minor from whatever is current).
- [ ] **Step 2: End-to-end verification**
  - `swift scripts/api-catalog-audit.swift; echo $?` → `0`, summary shows all 7 modules audited, 0 stale, 0 non-ignored gaps.
  - Every file under `.claude/skills/shared/api-catalog/` is reachable from the discovery skill's reach-for index; spot-check 3 index lines resolve to real `file § section`.
  - `scripts/api-catalog-ignore.txt`: every line has a reason comment.
  - Plugin packaging: `plugin.json` `skills` already points at `./.claude/skills/` — confirm the two new skill dirs and `shared/api-catalog/` sit under it.
- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore(plugin): bump to 2.7.0 for API catalog skills"
```

- [ ] **Step 4: Run the CI pipeline's exact command once more from a clean `.build`** (optional but cheap insurance): `rm -rf .build && swift test && swift scripts/api-catalog-audit.swift` — confirms the Ubuntu-job sequence works from scratch (run on macOS; expect FOSReporting present here, absent in CI — the script handles both).

---

## Execution notes

- **Order:** Tasks are sequential; Task 2 is a hard checkpoint (format review by David) before 3–6. Tasks 3–6 are independent of each other once Task 2's format is approved.
- **The catalog is customer documentation.** Entry authorship follows the DocC-is-for-the-customer discipline (CLAUDE.md): how they call it → example → why/when. Implementer rationale goes nowhere in catalog files.
- **When the audit and reality disagree** (symbol-graph noise, platform-conditional API), tune via the ignore file with a reason comment — never by loosening the script's rules ad hoc. If a rule change is genuinely needed, it's a spec change; surface it.
