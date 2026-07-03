// api-catalog-audit.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
    "FOSReporting": "FOSReporting.md"
]

/// Top-level declarations that require a catalog entry (or a catalogued parent).
let topLevelKinds: Set<String> = [
    "swift.struct", "swift.class", "swift.enum", "swift.protocol",
    "swift.typealias", "swift.func", "swift.var"
]

/// Members added by extensions to external types (String, URL, Encodable, ...) —
/// the most invisible API. Inits, operators, and enum cases are excluded: their
/// base names are meaningless for matching.
let extensionMemberKinds: Set<String> = [
    "swift.method", "swift.property", "swift.type.method",
    "swift.type.property", "swift.func", "swift.typealias"
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

    var isPublic: Bool {
        accessLevel == "public" || accessLevel == "open"
    }

    var baseName: String {
        baseIdentifier(pathComponents.last ?? "")
    }

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
    init(_ d: String) {
        self.description = d
    }
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
    let name: String // base identifier
    let parent: String? // extended/enclosing type's base identifier, if any
    let hasDoc: Bool
    let sourceFile: String
}

struct ModuleSurface {
    var auditItems: [AuditItem] = []
    var allNames: Set<String> = [] // every identifier at any depth (stale-match universe)
}

func loadSurfaces(from dir: URL) throws -> [String: ModuleSurface] {
    var surfaces: [String: ModuleSurface] = [:]
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasSuffix(".symbols.json") }

    for file in files {
        // "FOSFoundation.symbols.json" or "FOSFoundation@Swift.symbols.json"
        let stem = file.lastPathComponent.replacingOccurrences(of: ".symbols.json", with: "")
        let parts = stem.split(separator: "@", maxSplits: 1)
        guard let first = parts.first else { continue }
        let module = String(first)
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
                    sourceFile: symbol.sourceFile
                ))
            } else if symbol.pathComponents.count == 1,
                      topLevelKinds.contains(symbol.kind.identifier) {
                surface.auditItems.append(AuditItem(
                    module: module,
                    name: symbol.baseName,
                    parent: nil,
                    hasDoc: symbol.docComment != nil,
                    sourceFile: symbol.sourceFile
                ))
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
                if let first = name.first, first.isLetter || first == "_" {
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
        try byFile[file.lastPathComponent] =
            catalogTitleNames(in: String(contentsOf: file, encoding: .utf8))
    }
    return byFile
}

func loadIgnoreList() -> Set<String> {
    guard let text = try? String(contentsOfFile: ignoreFile, encoding: .utf8) else {
        print("info: no ignore file at \(ignoreFile)")
        return []
    }
    return Set(text.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") })
}

// MARK: - Main

do {
    let surfaces = try loadSurfaces(from: symbolGraphDir())
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

    // Stale entries: title symbols not found in the API surface of the file's
    // OWN mapped modules — a title symbol that lives in a different module's
    // catalog file still reports stale (remediation: move the entry to the
    // right file, or add the name to the ignore list). Only checked for
    // catalog files whose covered modules are ALL present (on Linux,
    // FOSReporting has no symbol graph — its file is skipped).
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
    for g in gaps {
        print("  \(g.module): \(g.name)  [\(g.sourceFile)]")
    }
    if gaps.isEmpty { print("  (none)") }
    print("\n== Stale catalog entries (ERROR): title symbols not in the API ==")
    for s in stale {
        print("  \(s.file): `\(s.name)`")
    }
    if stale.isEmpty { print("  (none)") }
    print("\n== DocC worklist (warning): audit-surface symbols with no doc comment ==")
    for d in docWorklist {
        print("  \(d.module): \(d.name)  [\(d.sourceFile)]")
    }
    if docWorklist.isEmpty { print("  (none)") }
    print("\nSummary: \(gaps.count) gap(s), \(stale.count) stale, \(docWorklist.count) undocumented; " +
        "modules audited: \(presentModules.sorted().joined(separator: ", "))")

    if !stale.isEmpty {
        print("\nFix: update the entry's title symbols in \(catalogDir)/<file> " +
            "(see the fosutilities-api-catalog-update skill), or add the symbol to " +
            "\(ignoreFile) with a reason comment.")
    }

    exit(stale.isEmpty ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(2)
}
