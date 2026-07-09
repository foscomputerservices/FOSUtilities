// localizable-overload-sweep.swift
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

// Generates SwiftUI `Localizable` overloads for FOSMVVM by sweeping the
// SwiftUI / SwiftUICore symbol graphs across every Apple platform SDK.
//
// Usage (from the package root):
//   swift scripts/localizable-overload-sweep.swift [flags]
//
// Flags:
//   --check           regenerate in memory and byte-compare against the
//                     checked-in output; exit 1 on drift (used by CI).
//   --filter <Type>   process only symbols whose extended type == <Type>.
//   --keep-graphs     leave the extracted symbol-graph JSON in the temp dir and
//                     print its path (otherwise the temp dir is removed on exit).
//
// The pipeline runs in six stages; this file grows one stage at a time:
//   Extract -> Select -> Union -> Transform -> Emit -> Verify.
//
// Extract resolves ALL five platform SDKs up front: any missing SDK is a hard
// error (exit 1) — a partial-platform sweep would silently drop overloads that
// exist only on the absent platform. Each SDK's own version string is the run's
// identity stamp; Xcode's version is deliberately never consulted.
//
// Extraction MUST pass -emit-extension-block-symbols (spec amendment
// 2026-07-09): without it, an extension of an external-module type (e.g.
// SwiftUI's `navigationTitle` on SwiftUICore's `View`) never appears as a
// member of that type — the tool instead synthesizes a copy onto every
// conformer (95 copies of `navigationTitle`, USRs suffixed
// `::SYNTHESIZED::<conformer>`). With the flag, extension-block members land
// canonically in the `@`-extension graphs with the correct extended type,
// once. Select additionally collapses any synthesized copies onto their base
// USR and verifies the canonical declaration was seen.

import Foundation

// MARK: - CLI

struct Options {
    var check = false
    var keepGraphs = false
    var filter: String?
}

func parseOptions() -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--check":
            options.check = true
        case "--keep-graphs":
            options.keepGraphs = true
        case "--filter":
            guard let value = iterator.next() else {
                fail("--filter requires a <Type> argument")
            }
            options.filter = value
        default:
            fail("unknown argument: \(arg)")
        }
    }
    return options
}

/// CLI-parse errors only — safe to exit directly because no temp dir exists yet.
/// Pipeline failures throw `Failure` instead, so main()'s cleanup defer runs.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) {
        self.description = d
    }
}

// MARK: - Process helper

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs `xcrun <arguments>` and captures its output.
@discardableResult
func runXcrun(_ arguments: [String]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
    } catch {
        throw Failure("failed to launch xcrun \(arguments.joined(separator: " ")): \(error)")
    }
    // Drain stderr concurrently: reading both pipes sequentially deadlocks if
    // the child fills one pipe's ~64KB buffer while we block on the other.
    var errData = Data()
    let stderrDrained = DispatchGroup()
    DispatchQueue.global().async(group: stderrDrained) {
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    }
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    stderrDrained.wait()
    process.waitUntilExit()
    return ProcessResult(
        status: process.terminationStatus,
        stdout: (String(bytes: outData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
        stderr: (String(bytes: errData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

// MARK: - Stage 1: Extract

/// A resolved platform SDK and the target triple its symbol graphs are extracted for.
struct PlatformSDK {
    let platform: String // xcrun SDK name, e.g. "macosx", "iphoneos", "xros"
    let target: String // target triple, e.g. "arm64-apple-macos26.5"
    let version: String // SDK version, e.g. "26.5" — the run's identity stamp
    let path: String // SDK path from `xcrun --show-sdk-path`
}

/// The extracted symbol graphs for one platform × module pairing.
struct ExtractedGraphs {
    let platform: String
    let module: String
    /// Main graph plus every `<module>@*.symbols.json` extension graph.
    let files: [URL]
}

let requiredSDKs = ["macosx", "iphoneos", "appletvos", "watchos", "xros"]
let modules = ["SwiftUI", "SwiftUICore"]

/// The target-triple OS token for each xcrun SDK name. The macOS triple uses
/// "macos" (not the SDK name "macosx"); the rest match empirically.
let tripleOS: [String: String] = [
    "macosx": "macos",
    "iphoneos": "ios",
    "appletvos": "tvos",
    "watchos": "watchos",
    "xros": "xros"
]

/// Resolves every required SDK. Any missing SDK is fatal (exit 1): a
/// partial-platform sweep would drop overloads that exist only on the absent
/// platform, so we refuse to generate at all.
///
/// `resolveSDKVersionsForCheck` is this function's `--check`-mode twin — the
/// two must stay in lockstep on the missing-SDK rule (non-zero xcrun status OR
/// empty stdout = missing); only the CONSEQUENCE differs (hard exit vs skip).
func resolveSDKs() throws -> [PlatformSDK] {
    var resolved: [PlatformSDK] = []
    var missing: [String] = []
    for platform in requiredSDKs {
        let versionResult = try runXcrun(["--sdk", platform, "--show-sdk-version"])
        let pathResult = try runXcrun(["--sdk", platform, "--show-sdk-path"])
        guard versionResult.status == 0, pathResult.status == 0,
              !versionResult.stdout.isEmpty, !pathResult.stdout.isEmpty else {
            missing.append(platform)
            continue
        }
        guard let os = tripleOS[platform] else {
            throw Failure("no target-triple mapping for SDK '\(platform)'")
        }
        // arm64-only by design: symbol graphs are architecture-independent for
        // this sweep's purposes (declarations, not ABI), and every supported
        // platform has an arm64 slice.
        resolved.append(PlatformSDK(
            platform: platform,
            target: "arm64-apple-\(os)\(versionResult.stdout)",
            version: versionResult.stdout,
            path: pathResult.stdout
        ))
    }
    if !missing.isEmpty {
        throw Failure("missing required SDK(s): \(missing.joined(separator: ", ")) — " +
            "no partial-platform generation")
    }
    return resolved
}

/// Extracts the symbol graphs for `module` on `sdk` into `<outputRoot>/<platform>/`,
/// returning the main graph and every `<module>@*.symbols.json` extension graph.
func extractGraphs(module: String, sdk: PlatformSDK, outputRoot: URL) throws -> ExtractedGraphs {
    let outputDir = outputRoot.appendingPathComponent(sdk.platform, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
        throw Failure("could not create output dir \(outputDir.path): \(error)")
    }

    let result = try runXcrun([
        "swift-symbolgraph-extract",
        "-module-name", module,
        "-target", sdk.target,
        "-sdk", sdk.path,
        "-emit-extension-block-symbols",
        "-output-dir", outputDir.path
    ])
    guard result.status == 0 else {
        throw Failure("swift-symbolgraph-extract failed for \(module) on \(sdk.platform) " +
            "(target \(sdk.target)):\n\(result.stderr)")
    }

    let prefix = "\(module)@"
    let files: [URL]
    do {
        files = try FileManager.default.contentsOfDirectory(
            at: outputDir, includingPropertiesForKeys: nil
        )
    } catch {
        throw Failure("could not list output dir \(outputDir.path): \(error)")
    }
    let graphFiles = files.filter {
        let name = $0.lastPathComponent
        return name == "\(module).symbols.json"
            || (name.hasPrefix(prefix) && name.hasSuffix(".symbols.json"))
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !graphFiles.isEmpty else {
        throw Failure("no symbol graphs produced for \(module) on \(sdk.platform)")
    }
    return ExtractedGraphs(platform: sdk.platform, module: module, files: graphFiles)
}

func byteSize(of file: URL) -> Int {
    let values = try? file.resourceValues(forKeys: [.fileSizeKey])
    return values?.fileSize ?? 0
}

/// Runs the Extract stage: resolve SDKs, extract every platform × module, and
/// print a one-line summary per graph. Returns the temp root and all graphs.
func runExtract(outputRoot: URL) throws -> (sdks: [PlatformSDK], graphs: [ExtractedGraphs]) {
    let sdks = try resolveSDKs()

    print("== SDK versions (run identity stamp) ==")
    for sdk in sdks {
        print("  \(sdk.platform): \(sdk.version)  (\(sdk.target))")
    }

    print("\n== Extracted symbol graphs ==")
    var allGraphs: [ExtractedGraphs] = []
    for sdk in sdks {
        for module in modules {
            let extracted = try extractGraphs(module: module, sdk: sdk, outputRoot: outputRoot)
            allGraphs.append(extracted)
            for file in extracted.files {
                let size = byteSize(of: file)
                print("  \(sdk.platform)  \(module)  \(file.lastPathComponent)  \(size) bytes")
            }
        }
    }
    return (sdks, allGraphs)
}

// MARK: - Symbol graph model

/// One decoded `*.symbols.json` file. `relationships`, `docComment`, `names`,
/// and `functionSignature` are intentionally not modelled: no planned stage
/// consumes them (extended types resolve via `pathComponents` +
/// `swiftExtension`), and skipping them keeps the biggest graphs (the macOS
/// SwiftUI graph is ~450 MB of JSON) far cheaper to decode and hold.
struct SymbolGraph: Decodable {
    let symbols: [Symbol]
}

struct Symbol: Decodable {
    struct Identifier: Decodable { let precise: String }
    struct Kind: Decodable { let identifier: String } // "swift.init" | "swift.method" | "swift.func" | ...
    struct Fragment: Decodable, Equatable {
        let kind: String // "typeIdentifier" | "externalParam" | "text" | ...
        let spelling: String
        let preciseIdentifier: String?
    }

    struct Availability: Decodable {
        struct Version: Decodable { let major: Int; let minor: Int?; let patch: Int? }
        let domain: String?
        let introduced: Version?
        let deprecated: Version?
        let obsoleted: Version?
        let isUnconditionallyDeprecated: Bool?
        let isUnconditionallyUnavailable: Bool?
    }

    struct SwiftExtension: Decodable, Equatable {
        struct Constraint: Decodable, Equatable { let kind: String; let lhs: String; let rhs: String }
        let extendedModule: String?
        let constraints: [Constraint]?
    }

    /// The declaration-level generic signature. Constraints here are NOT
    /// always spelled in `declarationFragments` (AccessibilityRotorEntry's
    /// `where ID == Never` inits) and never in `swiftExtension` — sibling
    /// qualification must consult this mixin or it proves delegates against
    /// siblings that are more constrained than the candidate.
    struct SwiftGenerics: Decodable {
        struct Parameter: Decodable { let name: String }
        let parameters: [Parameter]?
        let constraints: [SwiftExtension.Constraint]?
    }

    let identifier: Identifier
    let kind: Kind
    let pathComponents: [String] // ["Text", "init(_:tableName:bundle:comment:)"]
    let declarationFragments: [Fragment]?
    let availability: [Availability]?
    let swiftExtension: SwiftExtension?
    let swiftGenerics: SwiftGenerics?
    let accessLevel: String?
}

// MARK: - Stage 2: Select

/// The declaration kinds that can become `Localizable` overloads. Raw values
/// are the symbol-graph kind identifiers — the JSON string is lifted into this
/// type at the graph boundary and never travels as a raw `String` again.
/// Transform (Stage 4) switches on this to emit init-shaped vs method-shaped
/// bodies.
enum CandidateKind: String, CaseIterable {
    case initializer = "swift.init"
    case method = "swift.method"
    case function = "swift.func"
}

/// The single eligibility gate for declarations this sweep reasons about: a
/// public init/method/func with declaration fragments and no underscored path
/// component. Both `classify` (candidate side) and `SiblingIndex.add`
/// (delegate side) build on this one predicate — if the two sides derived it
/// independently and drifted, a candidate could be proven against a sibling
/// the gate would have excluded, or lose a legitimate delegate.
func eligibleDeclaration(_ symbol: Symbol) -> (kind: CandidateKind, fragments: [Symbol.Fragment])? {
    guard let kind = CandidateKind(rawValue: symbol.kind.identifier),
          symbol.accessLevel == "public",
          let fragments = symbol.declarationFragments,
          !symbol.pathComponents.contains(where: { $0.hasPrefix("_") })
    else { return nil }
    return (kind, fragments)
}

/// A public `init`/`method`/`func` that takes `LocalizedStringKey` and is a
/// candidate for a generated `Localizable` overload. Emitted once per
/// platform × module graph; Stage 3 (Union) groups these across platforms by
/// `usr`.
///
/// Carries the symbol payload later stages need (`availability`,
/// `declarationFragments`, `swiftExtension`) so the decoded graph can be
/// dropped: re-decoding graphs downstream is forbidden by the memory strategy.
/// Holding a few thousand of these small values is exactly what that strategy
/// permits; holding decoded GRAPHS is what it forbids.
struct Candidate {
    let platform: String
    let module: String
    let usr: String
    let kind: CandidateKind
    let pathComponents: [String]
    let declarationFragments: [Symbol.Fragment]
    let availability: [Symbol.Availability]
    let swiftExtension: Symbol.SwiftExtension?
    /// Declaration-level generic parameter names and constraints
    /// (`swiftGenerics`) — sibling qualification's other constraint source.
    let genericParameters: [String]
    let genericConstraints: [Symbol.SwiftExtension.Constraint]

    /// The extended type: `pathComponents` minus the member, dot-joined.
    /// `["Text", "init(_:)"]` -> `"Text"`. This is what `--filter` matches.
    var extendedType: String {
        pathComponents.dropLast().joined(separator: ".")
    }

    var member: String {
        pathComponents.last ?? ""
    }
}

/// The closed set of reasons a `LocalizedStringKey`-taking declaration can be
/// excluded. Stage 5's manifest text derives from `rawValue`.
enum RejectionReason: String {
    case deprecated
    case noDelegateTarget = "no-delegate-target"
    case unrecognizedShape = "unrecognized-shape"
}

/// A declaration that took `LocalizedStringKey` but was excluded by a
/// post-match clause. Retained for the manifest.
struct RejectedCandidate {
    /// Every platform whose graph contributed the rejected declaration:
    /// a single-graph reject (Select) carries one entry; a post-union reject
    /// (policy, transform) carries the unified API's full platform list.
    let contributingPlatforms: [String]
    let module: String
    let usr: String
    /// Declaration title (`Text.init(_:tableName:bundle:comment:)`) — the
    /// manifest's human-readable line; the USR alone is unreadable.
    let title: String
    let reason: RejectionReason
    /// Manifest context beyond the reason — Transform records the raw
    /// declaration of an unrecognized shape here. nil when the reason alone
    /// says it all.
    let note: String?
}

struct SelectResult {
    let candidates: [Candidate]
    let rejected: [RejectedCandidate]
    /// Synthesized (`::SYNTHESIZED::`) copies collapsed onto their canonical
    /// base USR — counted for the run summary; the canonical row carries the API.
    let synthesizedRowsCollapsed: Int
    /// Every canonical public init/method/func, for Stage 4's sibling matching.
    let siblingIndex: SiblingIndex
    /// Every public TYPE's availability (dotted name -> per-domain state),
    /// merged across platform graphs — the source for Emit's extension-header
    /// `@available` lines (the header references the TYPE, so the type's own
    /// introduction is its requirement).
    let typeAvailability: [String: [AvailabilityDomain: DomainAvailability]]
}

/// Type kinds under which the `LocalizedStringKey` / `Text` type symbols
/// could be published.
let typeSymbolKinds: Set<String> =
    ["swift.struct", "swift.class", "swift.enum", "swift.typealias"]

/// Type kinds an extension header can reference as its extended type — the
/// kinds Select's type-availability index records.
let extendedTypeSymbolKinds: Set<String> =
    ["swift.struct", "swift.protocol", "swift.class", "swift.enum"]

/// Reads and decodes one symbol-graph file. Any read/decode error is a thrown
/// `Failure` that names the file — a graph is never silently skipped.
func loadGraph(at file: URL) throws -> SymbolGraph {
    let data: Data
    do {
        data = try Data(contentsOf: file)
    } catch {
        throw Failure("could not read symbol graph \(file.path): \(error)")
    }
    do {
        return try JSONDecoder().decode(SymbolGraph.self, from: data)
    } catch {
        throw Failure("could not decode symbol graph \(file.path): \(error)")
    }
}

/// Pass 1: every USR that the `LocalizedStringKey` and `Text` TYPE symbols
/// are published under. Never hardcoded — both types moved to SwiftUICore but
/// kept their SwiftUI-mangled USRs, and a future SDK could expose a second
/// USR, so we collect sets. `LocalizedStringKey` drives Select's candidate
/// test; `Text` drives Stage 4's Text-sibling test. Throws if either type is
/// absent from every graph.
///
/// Scans graphs smallest-first and stops at the first file after which BOTH
/// sets are non-empty: both types live in the same small SwiftUICore graph
/// today, so the ~450 MB SwiftUI graphs are normally never decoded here, and
/// a relocation is still found — the tradeoff is that a hypothetical SECOND
/// USR published only in a later (larger) graph would be missed. Streams one
/// decoded graph at a time.
func discoverTypeUSRs(_ graphs: [ExtractedGraphs]) throws -> (lsk: Set<String>, text: Set<String>) {
    let filesSmallestFirst = graphs
        .flatMap(\.files)
        .sorted { byteSize(of: $0) < byteSize(of: $1) }
    var lsk: Set<String> = []
    var text: Set<String> = []
    for file in filesSmallestFirst {
        let graph = try loadGraph(at: file)
        for symbol in graph.symbols where typeSymbolKinds.contains(symbol.kind.identifier) {
            if symbol.pathComponents == ["LocalizedStringKey"] {
                lsk.insert(symbol.identifier.precise)
            } else if symbol.pathComponents == ["Text"] {
                text.insert(symbol.identifier.precise)
            }
        }
        if !lsk.isEmpty, !text.isEmpty {
            return (lsk, text)
        }
    }
    var missing: [String] = []
    if lsk.isEmpty { missing.append("LocalizedStringKey") }
    if text.isEmpty { missing.append("Text") }
    throw Failure("type symbol(s) not found in any symbol graph: " +
        "\(missing.joined(separator: ", ")) — cannot identify localizable " +
        "declarations and their delegate siblings")
}

/// True if any availability entry marks the symbol deprecated or obsoleted.
func isDeprecatedOrObsoleted(_ availability: [Symbol.Availability]?) -> Bool {
    guard let availability else { return false }
    return availability.contains { entry in
        entry.isUnconditionallyDeprecated == true
            || entry.deprecated != nil
            || entry.obsoleted != nil
    }
}

/// True when the availability list declares the macCatalyst domain AVAILABLE
/// (an `introduced` or a bare domain mention; not `unavailable`). macCatalyst
/// has no SDK or symbol graphs of its own and compiles as `os(iOS)`, so
/// graph-presence gating needs this declaration as its only Catalyst signal.
func declaresMacCatalystAvailable(_ availability: [Symbol.Availability]?) -> Bool {
    (availability ?? []).contains { entry in
        entry.domain == "macCatalyst" && entry.isUnconditionallyUnavailable != true
    }
}

/// The marker `swift-symbolgraph-extract` embeds in the USR of a symbol it
/// copied onto a conformer from a protocol extension (or onto a subclass from
/// a superclass). The prefix before the marker is the canonical base USR.
let synthesizedUSRMarker = "::SYNTHESIZED::"

enum Selection {
    case candidate(Candidate)
    case rejected(RejectedCandidate)
    /// A synthesized copy of a canonical declaration that would otherwise be a
    /// candidate. Collapsed — the canonical row (verified present) carries the
    /// API; emitting per-conformer copies would fan one overload out ~95×.
    case synthesized(baseUSR: String)
    case ignored
}

/// Applies the selection rule to one symbol.
///
/// Hard gates (public init/method/func, takes `LocalizedStringKey`, no
/// underscored path component) decide relevance: failing any means the symbol
/// is simply not our concern — `.ignored`, not rejected. A symbol that clears
/// the gates but trips an exclusion clause (currently: deprecation) is a
/// `.rejected` candidate, retained for the manifest. A synthesized copy that
/// clears every clause is `.synthesized` (collapsed onto its base USR);
/// deprecated synthesized copies are `.ignored` outright — the canonical
/// declaration, where Apple still publishes one, carries the rejection, and a
/// per-conformer flood of duplicate reject lines would drown the manifest.
func classify(_ symbol: Symbol, platform: String, module: String, lskUSRs: Set<String>) -> Selection {
    guard let (kind, frags) = eligibleDeclaration(symbol),
          frags.contains(where: { lskUSRs.contains($0.preciseIdentifier ?? "") })
    else { return .ignored }

    if let markerRange = symbol.identifier.precise.range(of: synthesizedUSRMarker) {
        guard !isDeprecatedOrObsoleted(symbol.availability) else { return .ignored }
        return .synthesized(baseUSR: String(symbol.identifier.precise[..<markerRange.lowerBound]))
    }

    if isDeprecatedOrObsoleted(symbol.availability) {
        return .rejected(RejectedCandidate(
            contributingPlatforms: [platform], module: module,
            usr: symbol.identifier.precise,
            title: symbol.pathComponents.joined(separator: "."),
            reason: .deprecated, note: nil
        ))
    }

    return .candidate(Candidate(
        platform: platform, module: module,
        usr: symbol.identifier.precise,
        kind: kind,
        pathComponents: symbol.pathComponents,
        declarationFragments: frags,
        availability: symbol.availability ?? [],
        swiftExtension: symbol.swiftExtension,
        genericParameters: (symbol.swiftGenerics?.parameters ?? []).map(\.name),
        genericConstraints: symbol.swiftGenerics?.constraints ?? []
    ))
}

/// Pass 2: classify every symbol in every graph, streaming one decoded graph at
/// a time. `filter`, when set, keeps only candidates whose extended type
/// matches (rejected candidates are always retained whole — the manifest is
/// global). Only the small `Candidate`/`RejectedCandidate` values survive each
/// graph; the decoded graph is dropped before the next loads.
///
/// Synthesized copies are collapsed onto their base USR, then verified: every
/// collapsed base must have been seen as a canonical candidate or reject
/// somewhere across the graphs. A miss would mean an API exists ONLY as
/// synthesized copies — collapsing would silently drop it — so it is a hard
/// error, not a warning.
func runSelect(graphs: [ExtractedGraphs], lskUSRs: Set<String>, filter: String?) throws -> SelectResult {
    var candidates: [Candidate] = []
    var rejected: [RejectedCandidate] = []
    var canonicalUSRs: Set<String> = [] // candidates pre-filter + rejects
    var synthesizedBases: Set<String> = []
    var synthesizedRows = 0
    var siblingIndex = SiblingIndex()
    var typeAvailability: [String: [AvailabilityDomain: DomainAvailability]] = [:]
    for group in graphs {
        for file in group.files {
            let graph = try loadGraph(at: file)
            for symbol in graph.symbols {
                siblingIndex.add(symbol, platform: group.platform)
                // Index every public type's availability for Emit's
                // extension-header annotations. Tiny (name -> domain states);
                // streams with the pass like everything else.
                if extendedTypeSymbolKinds.contains(symbol.kind.identifier),
                   symbol.accessLevel == "public",
                   !symbol.identifier.precise.contains(synthesizedUSRMarker),
                   !symbol.pathComponents.contains(where: { $0.hasPrefix("_") }) {
                    let typeName = symbol.pathComponents.joined(separator: ".")
                    var states = typeAvailability[typeName] ?? [:]
                    mergeAvailability(symbol.availability ?? [], into: &states)
                    typeAvailability[typeName] = states
                }
                switch classify(symbol, platform: group.platform, module: group.module, lskUSRs: lskUSRs) {
                case .candidate(let candidate):
                    canonicalUSRs.insert(candidate.usr)
                    if let filter, candidate.extendedType != filter { continue }
                    candidates.append(candidate)
                case .rejected(let reject):
                    canonicalUSRs.insert(reject.usr)
                    rejected.append(reject)
                case .synthesized(let baseUSR):
                    synthesizedBases.insert(baseUSR)
                    synthesizedRows += 1
                case .ignored:
                    break
                }
            }
        }
    }

    let unaccounted = synthesizedBases.subtracting(canonicalUSRs)
    guard unaccounted.isEmpty else {
        throw Failure("synthesized copies with no canonical declaration — collapsing " +
            "would drop these APIs:\n  " + unaccounted.sorted().joined(separator: "\n  "))
    }

    return SelectResult(
        candidates: candidates,
        rejected: rejected,
        synthesizedRowsCollapsed: synthesizedRows,
        siblingIndex: siblingIndex,
        typeAvailability: typeAvailability
    )
}

// MARK: - Stage 3: Union

/// A semantic version ordered for floor comparison. Displays as `major.minor`
/// (Apple annotates availability as `18.0`, never `18` or a patch level), so a
/// missing minor prints as `.0`.
/// Deliberate duplication: FOSFoundation ships SystemVersion, but this standalone script cannot import FOSFoundation.
struct SemVer: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(_ version: Symbol.Availability.Version) {
        self.init(version.major, version.minor ?? 0, version.patch ?? 0)
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var display: String {
        "\(major).\(minor)"
    }
}

/// Parses an SDK version string ("26.5") into a `SemVer`. Non-numeric segments
/// clamp to 0 — an SDK stamp is machine-generated, so this only guards oddities.
func parseSDKVersion(_ string: String) -> SemVer {
    let parts = string.split(separator: ".").map { Int($0) ?? 0 }
    return SemVer(
        parts.count > 0 ? parts[0] : 0,
        parts.count > 1 ? parts[1] : 0,
        parts.count > 2 ? parts[2] : 0
    )
}

/// The availability DOMAINS a generated overload can be annotated for. These are
/// deliberately NOT the same set as the extraction PLATFORMS: a single platform's
/// graph declares availability across every domain, iPadOS rides the `iOS` domain,
/// and `macCatalyst` is its own domain (no separate SDK — it rides the iOS SDK).
/// `CaseIterable` order is the deterministic emit order and matches Apple's
/// `@available` argument convention.
enum AvailabilityDomain: String, CaseIterable {
    case iOS
    case macOS
    case macCatalyst
    case tvOS
    case watchOS
    case visionOS

    /// Maps a symbol-graph `domain` string to a domain, folding `iPadOS` into
    /// `iOS`. Returns nil for strings this sweep does not annotate (`Swift`, the
    /// `*` wildcard, or any future domain) so the caller skips them.
    init?(graphDomain: String) {
        switch graphDomain {
        case "iOS", "iPadOS": self = .iOS
        case "macOS": self = .macOS
        case "macCatalyst": self = .macCatalyst
        case "tvOS": self = .tvOS
        case "watchOS": self = .watchOS
        case "visionOS": self = .visionOS
        default: return nil
        }
    }

    /// The deployment floor from `Package.swift`. This is the single source of
    /// the floors — an `introduced` at or below the floor is redundant (the
    /// package already requires it) and is dropped from the emitted annotation.
    var floor: SemVer {
        switch self {
        case .iOS: SemVer(17)
        case .macOS: SemVer(14)
        case .macCatalyst: SemVer(17)
        case .tvOS: SemVer(17)
        case .watchOS: SemVer(10)
        case .visionOS: SemVer(1)
        }
    }

    /// The extraction platforms (xcrun SDK names) whose SDK version stamps the
    /// beta tier for this domain. `macCatalyst` has no SDK of its own, so it
    /// rides the iOS SDK (`iphoneos`).
    static let sdkPlatforms: [String: [AvailabilityDomain]] = [
        "macosx": [.macOS],
        "iphoneos": [.iOS, .macCatalyst],
        "appletvos": [.tvOS],
        "watchos": [.watchOS],
        "xros": [.visionOS]
    ]
}

/// One domain's resolved availability for a unified API, before the floor clamp.
/// `sinceForever` (a domain mentioned without `introduced`) and any `introduced`
/// at/below the floor both drop from the emitted annotation; they are kept
/// distinct here only so beta-tier detection and conflict resolution can reason
/// about the raw version.
enum DomainAvailability: Equatable {
    case introduced(SemVer)
    case sinceForever
    case unavailable
}

/// One API merged across every platform graph that declared it, keyed by USR.
/// Carries a single representative of everything Transform needs
/// (`declarationFragments`, `swiftExtension`, `pathComponents`, `kind`) plus the
/// per-domain availability map. When the declaration fragments genuinely differ
/// across platform graphs for one USR, `fragmentVariantsByPlatform` is populated
/// and the representative is NOT silently trusted — the record is marked.
struct UnifiedAPI {
    let usr: String
    let module: String
    let kind: CandidateKind
    let pathComponents: [String]
    let declarationFragments: [Symbol.Fragment]
    /// Non-nil only when fragments (or structure) disagree across platforms.
    let fragmentVariantsByPlatform: [String: [Symbol.Fragment]]?
    let swiftExtension: Symbol.SwiftExtension?
    /// Declaration-level generic parameter names and constraints.
    let genericParameters: [String]
    let genericConstraints: [Symbol.SwiftExtension.Constraint]
    let availability: [AvailabilityDomain: DomainAvailability]
    let betaTierDomains: Set<AvailabilityDomain>
    let contributingPlatforms: [String]

    var hasFragmentDisagreement: Bool {
        fragmentVariantsByPlatform != nil
    }

    var extendedType: String {
        pathComponents.dropLast().joined(separator: ".")
    }

    var member: String {
        pathComponents.last ?? ""
    }

    /// Domains whose `introduced` survives the floor clamp, in emit order.
    var surviving: [(domain: AvailabilityDomain, version: SemVer)] {
        AvailabilityDomain.allCases.compactMap { domain -> (AvailabilityDomain, SemVer)? in
            guard case .introduced(let version) = availability[domain], version > domain.floor
            else { return nil }
            return (domain, version)
        }
    }

    /// Domains recorded unavailable, in emit order. Not subject to the floor.
    var unavailableDomains: [AvailabilityDomain] {
        AvailabilityDomain.allCases.filter { availability[$0] == .unavailable }
    }

    var hasAnnotation: Bool {
        !surviving.isEmpty || !unavailableDomains.isEmpty
    }
}

struct UnionStats {
    let uniqueAPIs: Int
    let annotated: Int
    let betaTier: Int
    let fragmentDisagreements: Int
    let availabilityConflicts: Int
    let platformContribution: [String: Int]
}

struct UnionResult {
    let apis: [UnifiedAPI]
    let stats: UnionStats
}

/// Higher-restriction wins when two platform graphs disagree on one domain:
/// `unavailable` is sticky, otherwise the later (higher) `introduced` is kept.
/// This is only reached on a genuine cross-platform conflict, which is counted
/// and reported — it is not expected to fire.
func resolveConflict(_ lhs: DomainAvailability, _ rhs: DomainAvailability) -> DomainAvailability {
    if lhs == .unavailable || rhs == .unavailable { return .unavailable }
    func version(_ state: DomainAvailability) -> SemVer {
        if case .introduced(let v) = state { return v }
        return SemVer(0)
    }
    return version(lhs) >= version(rhs) ? lhs : rhs
}

/// Merges one symbol's raw availability entries into a per-domain state map —
/// the ONE union semantics both candidates (`runUnion`) and extended-type
/// symbols (Select's type index) use: a wildcard `*` unavailable fans out to
/// every domain, and disagreements resolve higher-restriction-wins. Returns
/// true when any entry conflicted with an existing state.
@discardableResult
func mergeAvailability(
    _ entries: [Symbol.Availability],
    into states: inout [AvailabilityDomain: DomainAvailability]
) -> Bool {
    var conflicted = false
    func merge(_ domain: AvailabilityDomain, _ new: DomainAvailability) {
        if let old = states[domain], old != new {
            conflicted = true
            states[domain] = resolveConflict(old, new)
        } else {
            states[domain] = new
        }
    }
    for entry in entries {
        guard let domainString = entry.domain else { continue }
        if domainString == "*" {
            // A wildcard unavailable marks the whole API unavailable on
            // every domain. (Wildcard-deprecated never reaches here for
            // candidates — Select already rejects deprecated symbols.)
            if entry.isUnconditionallyUnavailable == true {
                for domain in AvailabilityDomain.allCases {
                    merge(domain, .unavailable)
                }
            }
            continue
        }
        guard let domain = AvailabilityDomain(graphDomain: domainString) else { continue }
        let state: DomainAvailability = if entry.isUnconditionallyUnavailable == true {
            .unavailable
        } else if let introduced = entry.introduced {
            .introduced(SemVer(introduced))
        } else {
            .sinceForever
        }
        merge(domain, state)
    }
    return conflicted
}

/// Merges the per-platform candidates into one `UnifiedAPI` per USR: unions the
/// availability domains, clamps nothing yet (that is a view on the record),
/// flags beta-tier domains, and verifies that fragments/structure agree across
/// platforms. Pure in-memory: no graph re-decode, no xcrun.
func runUnion(candidates: [Candidate], sdks: [PlatformSDK]) -> UnionResult {
    // domain -> SDK version, for beta-tier detection.
    var sdkVersion: [AvailabilityDomain: SemVer] = [:]
    for sdk in sdks {
        guard let domains = AvailabilityDomain.sdkPlatforms[sdk.platform] else { continue }
        let version = parseSDKVersion(sdk.version)
        for domain in domains {
            sdkVersion[domain] = version
        }
    }

    // Group by USR, preserving first-seen order for determinism.
    var groups: [String: [Candidate]] = [:]
    var order: [String] = []
    var platformContribution: [String: Int] = [:]
    for candidate in candidates {
        if groups[candidate.usr] == nil { order.append(candidate.usr) }
        groups[candidate.usr, default: []].append(candidate)
        platformContribution[candidate.platform, default: 0] += 1
    }

    var apis: [UnifiedAPI] = []
    var conflictCount = 0

    for usr in order {
        let group = groups[usr]!
        let representative = group[0]

        // Structure must agree across platforms; a genuine mismatch is a
        // disagreement, not a silent pick. swiftExtension and swiftGenerics
        // are part of the structure: Transform emits the representative's
        // constraints and Policy qualifies siblings against them, so a
        // cross-platform constraint mismatch must never pass silently.
        let structureDisagrees = group.contains {
            $0.kind != representative.kind
                || $0.pathComponents != representative.pathComponents
                || $0.swiftExtension != representative.swiftExtension
                || $0.genericParameters != representative.genericParameters
                || $0.genericConstraints != representative.genericConstraints
        }
        let fragmentsDisagree = group.contains {
            $0.declarationFragments != representative.declarationFragments
        }
        var variantsByPlatform: [String: [Symbol.Fragment]]?
        if structureDisagrees || fragmentsDisagree {
            var variants: [String: [Symbol.Fragment]] = [:]
            for candidate in group {
                variants[candidate.platform] = candidate.declarationFragments
            }
            variantsByPlatform = variants
        }

        // Union availability across every contributing platform.
        var states: [AvailabilityDomain: DomainAvailability] = [:]
        var conflicted = false
        for candidate in group {
            // Merge first, then fold — `conflicted ||` would short-circuit
            // the merge itself.
            conflicted = mergeAvailability(candidate.availability, into: &states) || conflicted
        }
        if conflicted { conflictCount += 1 }

        var betaDomains: Set<AvailabilityDomain> = []
        for domain in AvailabilityDomain.allCases {
            if case .introduced(let version) = states[domain],
               let sdk = sdkVersion[domain], version == sdk {
                betaDomains.insert(domain)
            }
        }

        apis.append(UnifiedAPI(
            usr: usr,
            module: representative.module,
            kind: representative.kind,
            pathComponents: representative.pathComponents,
            declarationFragments: representative.declarationFragments,
            fragmentVariantsByPlatform: variantsByPlatform,
            swiftExtension: representative.swiftExtension,
            genericParameters: representative.genericParameters,
            genericConstraints: representative.genericConstraints,
            availability: states,
            betaTierDomains: betaDomains,
            contributingPlatforms: Set(group.map(\.platform)).sorted()
        ))
    }

    apis.sort {
        ($0.pathComponents.joined(separator: "."), $0.usr)
            < ($1.pathComponents.joined(separator: "."), $1.usr)
    }

    let stats = UnionStats(
        uniqueAPIs: apis.count,
        annotated: apis.filter(\.hasAnnotation).count,
        betaTier: apis.count(where: { !$0.betaTierDomains.isEmpty }),
        fragmentDisagreements: apis.filter(\.hasFragmentDisagreement).count,
        availabilityConflicts: conflictCount,
        platformContribution: platformContribution
    )
    return UnionResult(apis: apis, stats: stats)
}

// MARK: - Stage 4: Sibling index + delegate policy

/// How a generated overload's body reaches SwiftUI. `direct` passes the
/// resolved `String` straight to Apple's `StringProtocol`-taking sibling;
/// `textVerbatim` wraps it in `Text(verbatim:)` for a `Text`-taking sibling.
/// The emitted call is by NAME (`self.init(...)` / `method(...)`) — compile-time
/// overload resolution picks the sibling; this classification is only the gate
/// proving such a target exists.
enum DelegatePolicy: String {
    case direct
    case textVerbatim = "text-verbatim"
}

/// The spellings Apple uses for a String sibling's string parameter,
/// counted per matched LocalizedStringKey slot for the run summary.
enum StringSiblingSpelling: String, CaseIterable {
    case someStringProtocol = "some StringProtocol"
    case genericWhereClause = "<S> where S : StringProtocol"
    case bareString = "String"
}

// MARK: Sibling index

/// Sibling index key: same extended type, same member title — a member title
/// (`init(_:text:prompt:)`) already encodes the name and every external label.
struct SiblingKey: Hashable {
    let extendedType: String
    let member: String
}

/// One indexed declaration a candidate may delegate to.
struct SiblingEntry {
    let usr: String
    let kind: CandidateKind
    let declarationFragments: [Symbol.Fragment]
    let swiftExtension: Symbol.SwiftExtension?
    /// Declaration-level generic parameter names and constraints — the
    /// qualification check compares these too, not just `swiftExtension`.
    let genericParameters: [String]
    let genericConstraints: [Symbol.SwiftExtension.Constraint]
}

/// Every canonical (non-synthesized) public, non-deprecated init/method/func
/// across all graphs, keyed by (extendedType, member title) and deduplicated
/// by USR. Built during Select's streaming pass — no graph is ever re-decoded.
///
/// Indexing ALL public members (not just plausible siblings) is the simplest
/// correct strategy: candidates are unknown while streaming, and the whole
/// index stays small (a few thousand entries) once synthesized copies are
/// dropped. Deprecated declarations are excluded — delegating to one would
/// bake deprecation warnings into generated code.
struct SiblingIndex {
    private(set) var entries: [SiblingKey: [SiblingEntry]] = [:]
    private var indexedUSRs: Set<String> = []
    private(set) var entryCount = 0
    /// The platforms (xcrun SDK names) whose GRAPHS contain each indexed USR.
    /// Emit's `#if os(...)` gates derive from the candidate ∩ matched-sibling
    /// intersection of this data (spec amendment 51c214c): graph absence is
    /// the sound compile gate — the extractor omits unavailable symbols, and
    /// `@available(<os>, unavailable)` alone cannot stop a platform from
    /// typechecking a delegating body; only `#if os(...)` can. Recorded on
    /// EVERY sighting — the USR dedup below must not blind platform coverage.
    private(set) var graphPlatformsByUSR: [String: Set<String>] = [:]
    /// USRs whose availability declares the macCatalyst domain AVAILABLE
    /// (introduced or bare mention, not unavailable) — the Catalyst guard's
    /// sibling half; see `sharedPlatforms` in `classifyPolicy`.
    private(set) var macCatalystAvailableUSRs: Set<String> = []

    mutating func add(_ symbol: Symbol, platform: String) {
        guard let (kind, frags) = eligibleDeclaration(symbol),
              !symbol.identifier.precise.contains(synthesizedUSRMarker),
              !isDeprecatedOrObsoleted(symbol.availability)
        else { return }
        graphPlatformsByUSR[symbol.identifier.precise, default: []].insert(platform)
        if declaresMacCatalystAvailable(symbol.availability) {
            macCatalystAvailableUSRs.insert(symbol.identifier.precise)
        }
        guard !indexedUSRs.contains(symbol.identifier.precise) else { return }
        indexedUSRs.insert(symbol.identifier.precise)
        entryCount += 1
        let key = SiblingKey(
            extendedType: symbol.pathComponents.dropLast().joined(separator: "."),
            member: symbol.pathComponents.last ?? ""
        )
        entries[key, default: []].append(SiblingEntry(
            usr: symbol.identifier.precise,
            kind: kind,
            declarationFragments: frags,
            swiftExtension: symbol.swiftExtension,
            genericParameters: (symbol.swiftGenerics?.parameters ?? []).map(\.name),
            genericConstraints: symbol.swiftGenerics?.constraints ?? []
        ))
    }
}

// MARK: Parameter parsing

/// One parsed parameter of a declaration.
///
/// All ranges are FRAGMENT indices into the declaration's
/// `declarationFragments`. The declaration is parsed ONCE — the same slots
/// travel from sibling matching through policy classification into Transform,
/// which splices replacement text by these indices and never re-parses.
struct ParameterSlot {
    let label: String // external label; "_" when unnamed
    /// Fragment index of the `externalParam` label fragment.
    let labelIndex: Int
    /// Fragment index of the `internalParam` fragment, when the declaration
    /// spells a distinct internal name (`_ titleKey:`); nil when the external
    /// label doubles as the internal name (`prompt:`).
    let internalParamIndex: Int?
    let internalName: String?
    let typeText: String // normalized: whitespace-collapsed, default value stripped
    let typeFragments: [Symbol.Fragment] // non-text fragments in the type region
    /// Fragment indices spanning every fragment that contributed a
    /// non-whitespace character to the type region (default value included);
    /// nil when the slot never grew a type region.
    let typeRange: Range<Int>?
    /// Label fragment through the last fragment that contributed to the slot.
    let slotRange: Range<Int>
    let hasDefaultValue: Bool
    let isVariadic: Bool

    func containsType(in usrs: Set<String>) -> Bool {
        typeFragments.contains { usrs.contains($0.preciseIdentifier ?? "") }
    }
}

/// Parses a declaration's parameter list out of its fragments.
///
/// Grammar (verified empirically against the SDK 26.5 graphs): every parameter
/// begins with an `externalParam` fragment (spelling `_` when unnamed); a text
/// fragment containing `:` separates the name region from the type region;
/// parameters separate at top-level commas; the list is bounded by the
/// declaration's outermost parentheses. Depth is tracked for parentheses
/// (closure types), square brackets (collections), angle brackets (generic
/// arguments — `->` is an arrow, not a bracket close), and braces (closure
/// default values) so nested commas never split a slot.
///
/// Real fragment shapes the grammar was validated against (SDK 26.5 graphs):
///
///   Label.init(_:image:) — the plain case; `nonisolated` is an attribute:
///     [attribute "nonisolated"] [text " "] [keyword "init"] [text "("]
///     [externalParam "_"] [text " "] [internalParam "titleKey"] [text ": "]
///     [typeIdentifier "LocalizedStringKey"] [text ", "] [externalParam "image"]
///     [text " "] [internalParam "name"] [text ": "] [typeIdentifier "String"]
///     [text ")"]
///
///   View.navigationTitle(_:) (extension graph) — the closing paren shares a
///   text fragment with the return arrow, and a trailing newline fragment ends
///   the declaration:
///     ... [typeIdentifier "LocalizedStringKey"] [text ") -> "]
///     [keyword "some"] [text " "] [typeIdentifier "View"] [text "\n"]
///
///   AccessibilityRotorEntry.init(_:id:textRange:prepare:) — one text fragment
///   mixes a generic close, a default value, and the separator (">? = nil, "),
///   and a parameter attribute rides INSIDE the type region:
///     [externalParam "textRange"] [text ": "] [typeIdentifier "Range"]
///     [text "<"] [typeIdentifier "String"] [text "."] [typeIdentifier "Index"]
///     [text ">? = nil, "] [externalParam "prepare"] [text ": "]
///     [attribute "@escaping "] [text "() -> "] [typeIdentifier "Void"]
///     [text " = {})"]
///
///   navigationTitle(_:) @ViewBuilder variant — a parameter attribute BEFORE
///   the label is two attribute fragments outside any slot:
///     [text ">("] [attribute "@"] [attribute "ViewBuilder"] [text " "]
///     [externalParam "_"] [text " "] [internalParam "title"]
///     [text ": () -> "] [typeIdentifier "V"] ...
///
/// Returns nil when no parameter list closes — the caller treats that
/// declaration as unrecognized (candidate) or skips it (sibling). Never guesses.
func parseParameterSlots(_ fragments: [Symbol.Fragment]) -> [ParameterSlot]? {
    struct BuildingSlot {
        var label: String
        var labelIndex: Int
        var internalParamIndex: Int?
        var internalName: String?
        var typeText = ""
        var typeFragments: [Symbol.Fragment] = []
        var firstTypeIndex: Int?
        var lastTypeIndex: Int?
        var lastIndex: Int
        var inTypeRegion = false
    }
    var finished: [BuildingSlot] = []
    var current: BuildingSlot?
    var parenDepth = 0, angleDepth = 0, squareDepth = 0, braceDepth = 0
    var inParams = false
    var paramsClosed = false

    func closeCurrent() {
        if let slot = current { finished.append(slot) }
        current = nil
    }

    for (index, fragment) in fragments.enumerated() {
        if paramsClosed { break }
        if fragment.kind == "text" {
            var previous: Character = " "
            for ch in fragment.spelling {
                defer { previous = ch }
                if !inParams {
                    if ch == "(" {
                        inParams = true
                        parenDepth = 1
                        angleDepth = 0
                        squareDepth = 0
                        braceDepth = 0
                    }
                    continue
                }
                switch ch {
                case "(": parenDepth += 1
                case ")":
                    parenDepth -= 1
                    if parenDepth == 0 {
                        closeCurrent()
                        paramsClosed = true
                    }
                case "[": squareDepth += 1
                case "]": squareDepth -= 1
                case "{": braceDepth += 1
                case "}": braceDepth -= 1
                case "<": angleDepth += 1
                case ">" where previous != "-": // "->" is an arrow
                    if angleDepth > 0 { angleDepth -= 1 }
                case "," where parenDepth == 1 && angleDepth == 0
                    && squareDepth == 0 && braceDepth == 0:
                    closeCurrent()
                    continue
                default:
                    break
                }
                if paramsClosed { break }
                if var slot = current {
                    slot.lastIndex = index
                    if slot.inTypeRegion {
                        slot.typeText.append(ch)
                        if !ch.isWhitespace {
                            if slot.firstTypeIndex == nil { slot.firstTypeIndex = index }
                            slot.lastTypeIndex = index
                        }
                    } else if ch == ":" {
                        slot.inTypeRegion = true
                    }
                    current = slot
                }
            }
        } else if inParams {
            if fragment.kind == "externalParam", parenDepth == 1, angleDepth == 0,
               squareDepth == 0, braceDepth == 0 {
                closeCurrent()
                current = BuildingSlot(label: fragment.spelling, labelIndex: index, lastIndex: index)
            } else if var slot = current {
                if fragment.kind == "internalParam", !slot.inTypeRegion {
                    slot.internalParamIndex = index
                    slot.internalName = fragment.spelling
                    slot.lastIndex = index
                    current = slot
                } else if slot.inTypeRegion {
                    slot.typeText += fragment.spelling
                    slot.typeFragments.append(fragment)
                    if slot.firstTypeIndex == nil { slot.firstTypeIndex = index }
                    slot.lastTypeIndex = index
                    slot.lastIndex = index
                    current = slot
                }
            }
        }
    }
    guard paramsClosed else { return nil }

    // Normalization of a slot's type text is a CLOSED SET of exactly three
    // rules. Sibling matching compares these normalized strings, so extending
    // the set changes MATCH SEMANTICS (which declarations count as siblings),
    // not cosmetics — extend only with a spec amendment.
    //  1. Whitespace collapses to single spaces: the same type is spelled
    //     with differing whitespace across the platform graphs.
    //  2. A default value (" = ...") is stripped: a candidate's slot must
    //     compare equal to a sibling's whether or not one spells a default.
    //  3. Variadics are DETECTED (isVariadic), never normalized away: Swift
    //     cannot forward a variadic argument list, so variadic candidates are
    //     rejected outright rather than matched.
    return finished.map { building in
        let collapsed = building.typeText
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let defaultStart = collapsed.range(of: " = ")
        let typeText = if let defaultStart {
            String(collapsed[..<defaultStart.lowerBound])
        } else {
            collapsed
        }
        return ParameterSlot(
            label: building.label,
            labelIndex: building.labelIndex,
            internalParamIndex: building.internalParamIndex,
            internalName: building.internalName,
            typeText: typeText,
            typeFragments: building.typeFragments,
            typeRange: building.firstTypeIndex.map { first in
                // lastTypeIndex is always set alongside firstTypeIndex.
                first..<(building.lastTypeIndex! + 1)
            },
            slotRange: building.labelIndex..<(building.lastIndex + 1),
            hasDefaultValue: defaultStart != nil,
            isVariadic: collapsed.contains("...")
        )
    }
}

// MARK: StringProtocol resolution

/// The USR of `Swift.StringProtocol`. Unlike `LocalizedStringKey`/`Text`, it
/// cannot be discovered from the swept graphs (the stdlib's graph is not
/// extracted), so the stable stdlib mangling is pinned here.
let stringProtocolUSR = "s:Sy"

/// Names of generic parameters constrained to `StringProtocol`, from the
/// declaration's constraint fragments (the triple `S`, `" : "`,
/// `StringProtocol` — spelled inline or in a `where` clause) plus the
/// extension's own constraint list.
func stringProtocolConstrainedNames(
    fragments: [Symbol.Fragment],
    swiftExtension: Symbol.SwiftExtension?
) -> Set<String> {
    var names: Set<String> = []
    for index in fragments.indices.dropFirst(2) {
        let fragment = fragments[index]
        guard fragment.kind == "typeIdentifier",
              fragment.preciseIdentifier == stringProtocolUSR
              || fragment.spelling == "StringProtocol"
        else { continue }
        let separator = fragments[index - 1]
        let subject = fragments[index - 2]
        if separator.kind == "text",
           separator.spelling.trimmingCharacters(in: .whitespaces).hasSuffix(":"),
           subject.kind == "typeIdentifier" || subject.kind == "genericParameter" {
            names.insert(subject.spelling)
        }
    }
    for constraint in swiftExtension?.constraints ?? []
        where constraint.kind == "conformance" && constraint.rhs == "StringProtocol" {
        names.insert(constraint.lhs)
    }
    return names
}

/// How a sibling's slot accepts a `String`, or nil if it does not.
func stringSiblingSpelling(
    of slot: ParameterSlot,
    constrainedNames: Set<String>
) -> StringSiblingSpelling? {
    if slot.typeText == "String" { return .bareString }
    if slot.typeText == "some StringProtocol",
       slot.containsType(in: [stringProtocolUSR]) { return .someStringProtocol }
    if constrainedNames.contains(slot.typeText) { return .genericWhereClause }
    return nil
}

/// True when a sibling's slot is `Text` / `Text?` (optionality of the target
/// slot never matters — the generated body always synthesizes a non-nil value).
func isTextSlot(_ slot: ParameterSlot, textUSRs: Set<String>) -> Bool {
    (slot.typeText == "Text" || slot.typeText == "Text?")
        && slot.containsType(in: textUSRs)
}

// MARK: Policy classification

/// A unified API whose delegate policy is proven, carrying THE parse forward:
/// `slots`/`lskPositions` come from the one `parseParameterSlots` call made
/// during classification — Transform splices by these and never re-parses.
struct ClassifiedAPI {
    let api: UnifiedAPI
    let policy: DelegatePolicy
    /// The candidate's parsed parameter slots.
    let slots: [ParameterSlot]
    /// Indices into `slots` whose type mentions `LocalizedStringKey`.
    let lskPositions: [Int]
    /// The sibling declaration the policy was proven against. The generated
    /// body delegates by NAME (overload resolution re-finds it at compile
    /// time); this is carried for the manifest/debugging trail.
    let matchedSibling: SiblingEntry
    /// Platforms (xcrun SDK names) whose GRAPHS contain both the candidate
    /// and the matched sibling (plus the macCatalyst guard's `iphoneos`).
    /// `@available(<os>, unavailable)` does not stop a platform from
    /// typechecking the delegating body — only `#if os(...)` does — so when
    /// this set is not all five platforms, Emit compiles the member only
    /// where its delegate provably exists (MenuBarExtra's ImageResource
    /// inits are in no SDK but macOS's).
    let delegatePlatforms: Set<String>
}

/// The verdict for one unified candidate.
enum PolicyVerdict {
    case classified(ClassifiedAPI, spellings: [StringSiblingSpelling])
    /// `lskReturnOnly` marks the sub-case where `LocalizedStringKey` matched
    /// only outside the parameter list (e.g. return position) — counted
    /// separately in the summary.
    case rejected(RejectionReason, lskReturnOnly: Bool)
}

/// Classifies one unified API's delegate policy against the sibling index.
///
/// A sibling qualifies when: same kind, same member title (name + labels, via
/// the index key), its extension imposes no constraint the candidate's does
/// not (it may be MORE general, never more constrained), every non-LSK
/// parameter matches by normalized type text, and every LSK position accepts
/// a `String` (policy `direct`) or a `Text` (policy `textVerbatim`). Variadics
/// reject outright — Swift cannot forward a variadic argument list. When in
/// doubt, reject: a reject is a manifest line, a wrong accept is broken
/// public API.
func classifyPolicy(
    for api: UnifiedAPI,
    siblings: SiblingIndex,
    lskUSRs: Set<String>,
    textUSRs: Set<String>
) -> PolicyVerdict {
    guard let slots = parseParameterSlots(api.declarationFragments) else {
        return .rejected(.unrecognizedShape, lskReturnOnly: false)
    }
    guard !slots.contains(where: \.isVariadic) else {
        return .rejected(.unrecognizedShape, lskReturnOnly: false)
    }
    // LSK anywhere in a slot's type marks it an LSK position. Aggregates like
    // [LocalizedStringKey] cannot be satisfied by resolving one Localizable —
    // no sibling slot passes the String/Text test for them, so they land in
    // no-delegate-target below rather than getting a guessed transform.
    let lskPositions = slots.indices.filter { slots[$0].containsType(in: lskUSRs) }
    guard !lskPositions.isEmpty else {
        return .rejected(.unrecognizedShape, lskReturnOnly: true)
    }

    let candidateLabels = slots.map(\.label)
    let candidateConstraints = (api.swiftExtension?.constraints ?? []) + api.genericConstraints
    let candidateParameters = Set(api.genericParameters)

    let candidateMacCatalystAvailable = switch api.availability[.macCatalyst] {
    case .introduced, .sinceForever: true
    case .unavailable, nil: false
    }

    /// Platforms whose graphs hold both the candidate and this sibling — the
    /// provably-compilable set for a member delegating to the sibling.
    ///
    /// macCatalyst guard: Catalyst has no SDK or graphs of its own and
    /// compiles as `os(iOS)`, so graph intersection alone would gate
    /// Catalyst-available API out of the iOS compile it rides. When BOTH
    /// sides declare macCatalyst available, the pair provably exists in the
    /// shared iphoneos SDK universe (Catalyst declarations cannot be
    /// `#if`-compiled out of it), so `iphoneos` joins the set. One side
    /// alone is not enough — the other may still be absent from the iOS SDK,
    /// and adding `os(iOS)` would break device builds.
    func sharedPlatforms(with sibling: SiblingEntry) -> Set<String> {
        var shared = Set(api.contributingPlatforms)
            .intersection(siblings.graphPlatformsByUSR[sibling.usr] ?? [])
        if candidateMacCatalystAvailable,
           siblings.macCatalystAvailableUSRs.contains(sibling.usr) {
            shared.insert("iphoneos")
        }
        return shared
    }

    /// The sibling's parsed slots, when its shape matches everywhere except
    /// (possibly) the LSK positions; nil otherwise.
    ///
    /// Constraint rule (spec: a sibling may be MORE general, never more
    /// constrained): every sibling constraint — extension-level AND
    /// declaration-level (`swiftGenerics`; AccessibilityRotorEntry's String
    /// sibling spells `ID == Never` only there) — must either appear among
    /// the candidate's constraints or bind a generic parameter the sibling
    /// introduces beyond the candidate's (the `S`/`L` of its string slot,
    /// which the forwarded `String` argument satisfies).
    func matchingSlots(of sibling: SiblingEntry) -> [ParameterSlot]? {
        guard sibling.usr != api.usr, sibling.kind == api.kind,
              // A pair that coexists in no compile can delegate nowhere.
              !sharedPlatforms(with: sibling).isEmpty
        else { return nil }
        let siblingOnlyParameters = Set(sibling.genericParameters)
            .subtracting(candidateParameters)
        let siblingConstraints =
            (sibling.swiftExtension?.constraints ?? []) + sibling.genericConstraints
        guard siblingConstraints.allSatisfy({ constraint in
            candidateConstraints.contains(constraint)
                || siblingOnlyParameters.contains(baseIdentifier(constraint.lhs))
        }),
            let siblingSlots = parseParameterSlots(sibling.declarationFragments),
            siblingSlots.count == slots.count,
            siblingSlots.map(\.label) == candidateLabels
        else { return nil }
        for index in slots.indices where !lskPositions.contains(index) {
            guard siblingSlots[index].typeText == slots[index].typeText else { return nil }
        }
        return siblingSlots
    }

    let entries = siblings.entries[
        SiblingKey(extendedType: api.extendedType, member: api.member)
    ] ?? []

    for sibling in entries {
        guard let siblingSlots = matchingSlots(of: sibling) else { continue }
        let constrainedNames = stringProtocolConstrainedNames(
            fragments: sibling.declarationFragments,
            swiftExtension: sibling.swiftExtension
        )
        let spellings = lskPositions.compactMap {
            stringSiblingSpelling(of: siblingSlots[$0], constrainedNames: constrainedNames)
        }
        if spellings.count == lskPositions.count {
            return .classified(ClassifiedAPI(
                api: api, policy: .direct, slots: slots,
                lskPositions: lskPositions, matchedSibling: sibling,
                delegatePlatforms: sharedPlatforms(with: sibling)
            ), spellings: spellings)
        }
    }
    for sibling in entries {
        guard let siblingSlots = matchingSlots(of: sibling) else { continue }
        if lskPositions.allSatisfy({ isTextSlot(siblingSlots[$0], textUSRs: textUSRs) }) {
            return .classified(ClassifiedAPI(
                api: api, policy: .textVerbatim, slots: slots,
                lskPositions: lskPositions, matchedSibling: sibling,
                delegatePlatforms: sharedPlatforms(with: sibling)
            ), spellings: [])
        }
    }
    return .rejected(.noDelegateTarget, lskReturnOnly: false)
}

struct PolicyStats {
    var direct = 0
    var textVerbatim = 0
    var rejectedNoDelegateTarget = 0
    var rejectedUnrecognizedShape = 0
    var lskReturnOnly = 0
    var spellingCounts: [StringSiblingSpelling: Int] = [:]
}

struct PolicyResult {
    let classified: [ClassifiedAPI]
    /// Stage 4 rejects, in the SAME shape Select's rejects use — Stage 5's
    /// manifest consumes one combined list.
    let rejected: [RejectedCandidate]
    let stats: PolicyStats
}

/// Stage 4 proper: classify every unified API's delegate policy. Pure function
/// over (unified APIs, sibling index) — no I/O, no graph access.
func runPolicy(
    apis: [UnifiedAPI],
    siblings: SiblingIndex,
    lskUSRs: Set<String>,
    textUSRs: Set<String>
) -> PolicyResult {
    var classified: [ClassifiedAPI] = []
    var rejected: [RejectedCandidate] = []
    var stats = PolicyStats()
    for api in apis {
        switch classifyPolicy(for: api, siblings: siblings, lskUSRs: lskUSRs, textUSRs: textUSRs) {
        case .classified(let item, let spellings):
            classified.append(item)
            switch item.policy {
            case .direct: stats.direct += 1
            case .textVerbatim: stats.textVerbatim += 1
            }
            for spelling in spellings {
                stats.spellingCounts[spelling, default: 0] += 1
            }
        case .rejected(let reason, let lskReturnOnly):
            rejected.append(RejectedCandidate(
                contributingPlatforms: api.contributingPlatforms,
                module: api.module,
                usr: api.usr,
                title: api.pathComponents.joined(separator: "."),
                reason: reason,
                note: nil
            ))
            switch reason {
            case .noDelegateTarget: stats.rejectedNoDelegateTarget += 1
            case .unrecognizedShape: stats.rejectedUnrecognizedShape += 1
            case .deprecated: break // Stage 4 never rejects for deprecation
            }
            if lskReturnOnly { stats.lskReturnOnly += 1 }
        }
    }
    return PolicyResult(classified: classified, rejected: rejected, stats: stats)
}

// MARK: - Stage 5: Transform

// MARK: Extension constraint rendering

/// The leading identifier of a constraint operand (`Label<Text, Image>` ->
/// `Label`; `C.Element` -> `C`).
func baseIdentifier(_ text: String) -> String {
    String(text.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
}

/// Renders an extension's generic constraints as a `where` clause ("" when
/// unconstrained). The kind mapping was inspected empirically in the SDK 26.5
/// graphs — exactly three kinds occur (macOS SwiftUI graph: "conformance"
/// 1489, "sameType" 1294, "superclass" 143 — e.g. TableColumn's
/// `RowValue: NSObject`), matching SymbolKit's documented closed set.
/// conformance and superclass both spell `:`; sameType spells `==`. Any other
/// kind returns nil and the caller rejects the API rather than guessing.
///
/// An rhs spelled as a generic SPECIALIZATION of a generic-parameter name
/// (Button's `Label == Label<Text, Image>`) would resolve to the PARAMETER,
/// not the SwiftUI type, inside our extension — a shadowing Apple's own
/// module context never sees. A parameter can never be specialized, so the
/// `Name<` spelling proves it is the module type: it gets a `SwiftUI.`
/// qualifier (SwiftUI re-exports SwiftUICore, so every swept surface type
/// resolves under it). Dependent members (`Sort.Compared`) DO name the
/// parameter and stay unqualified.
func renderConstraints(_ constraints: [Symbol.SwiftExtension.Constraint]) -> String? {
    guard !constraints.isEmpty else { return "" }
    let parameterNames = Set(constraints.map { baseIdentifier($0.lhs) })
    var parts: [String] = []
    for constraint in constraints {
        let base = baseIdentifier(constraint.rhs)
        let rhs = parameterNames.contains(base)
            && constraint.rhs.dropFirst(base.count).first == "<"
            ? "SwiftUI.\(constraint.rhs)"
            : constraint.rhs
        switch constraint.kind {
        case "conformance", "superclass": parts.append("\(constraint.lhs): \(rhs)")
        case "sameType": parts.append("\(constraint.lhs) == \(rhs)")
        default: return nil
        }
    }
    return "where " + parts.joined(separator: ", ")
}

// MARK: Transformed overload

/// One `Localizable` slot the transform inserted into the overload, in
/// declaration order. Emit's DocC parameter lines and example synthesis
/// consume these — the naming rule lives ONLY in `transform`, never re-derived.
struct InsertedSlot {
    /// The `some Localizable` parameter's internal name (`localizable`,
    /// `localizable2`, ...).
    let localizableName: String
    /// The inserted fallback parameter's label (`defaultValue`,
    /// `defaultPrompt`, ...).
    let fallbackName: String
    /// Apple's external label for the slot; "_" when unnamed. Emit's example
    /// synthesis spells the call argument with it.
    let appleLabel: String
}

/// One generated overload, ready for Emit (Stage 6). `signatureText` is the
/// member declaration without a body; `bodyText` is its single delegating
/// expression. `api` rides along so Emit can render availability annotations.
struct TransformedOverload {
    let api: UnifiedAPI
    let policy: DelegatePolicy
    /// "" for a free function — Emit renders no extension block.
    let extendedType: String
    let extensionConstraints: [Symbol.SwiftExtension.Constraint]
    /// Rendered `where` clause for the extension header; "" when unconstrained.
    let extensionConstraintsText: String
    let signatureText: String
    let bodyText: String
    /// The inserted Localizable slots, in declaration order (>1 is rare;
    /// counted in the summary).
    let insertedSlots: [InsertedSlot]
    /// True when any non-Localizable parameter has no default value — Emit's
    /// example synthesis cannot mechanically produce a full call expression
    /// then, and falls back to the call shape.
    let hasOtherRequiredParameters: Bool
    /// External labels of the GENERATED overload's parameters in order
    /// (Apple's labels with each inserted fallback label spliced in) — the
    /// call-shape fallback for examples.
    let overloadParameterLabels: [String]
    /// The platforms (xcrun SDK names, in `gatePlatformOrder`) whose graphs
    /// contain both the candidate and its matched delegate — empty when that
    /// is ALL platforms (the common case: no gate). Non-empty means Emit
    /// wraps the member in `#if os(...)`: the delegate provably exists only
    /// in those SDKs, and `@available` cannot stop the other compiles from
    /// typechecking the body.
    let gatePlatforms: [String]
}

/// `#if os(...)` emission order for gate platforms — the xcrun SDK names in
/// `AvailabilityDomain` order (iOS, macOS, tvOS, watchOS, visionOS;
/// macCatalyst rides iOS and has no SDK of its own).
let gatePlatformOrder = ["iphoneos", "macosx", "appletvos", "watchos", "xros"]

enum TransformVerdict {
    case transformed(TransformedOverload)
    case rejected(RejectedCandidate)
}

/// The declaration's source text as the graph spells it (joined fragments) —
/// retained on every transform reject so the manifest shows exactly what was
/// refused.
func declarationText(_ fragments: [Symbol.Fragment]) -> String {
    fragments.map(\.spelling).joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: Signature and body rewrite

/// Words that cannot appear bare as an argument in the delegating call. A
/// forwarding name that hits this set rejects the API (Apple would have to
/// ship a keyword-labeled parameter with no distinct internal name — never
/// observed; backtick-spelled internal names pass because the backticks are
/// part of the fragment spelling and miss this exact-match set).
let swiftKeywords: Set<String> = [
    "as", "any", "await", "borrowing", "break", "case", "catch", "class",
    "consuming", "continue", "default", "defer", "deinit", "do", "else",
    "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func",
    "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
    "nil", "nonisolated", "open", "operator", "private", "protocol", "public",
    "repeat", "rethrows", "return", "self", "Self", "static", "struct",
    "subscript", "super", "switch", "throw", "throws", "true", "try",
    "typealias", "var", "where", "while"
]

/// Stage 5 proper: rewrites one classified API into overload source text by
/// splicing the parse carried in `ClassifiedAPI` — a pure function that never
/// re-parses the declaration. Any shape outside the validated grammar rejects
/// `.unrecognizedShape` with the raw declaration retained for the manifest.
/// Never emits a guess.
func transform(_ classified: ClassifiedAPI) -> TransformVerdict {
    let api = classified.api
    let fragments = api.declarationFragments

    func reject(_ note: String) -> TransformVerdict {
        .rejected(RejectedCandidate(
            contributingPlatforms: api.contributingPlatforms,
            module: api.module,
            usr: api.usr,
            title: api.pathComponents.joined(separator: "."),
            reason: .unrecognizedShape,
            note: "\(note) — declaration: \(declarationText(fragments))"
        ))
    }

    // The representative fragments are an arbitrary platform's pick when the
    // graphs disagree — transforming them would bake one platform's shape
    // into every platform's overload. 0 such APIs today; future-SDK guard.
    guard !api.hasFragmentDisagreement else {
        return reject("fragment disagreement across platforms")
    }

    let constraints = api.swiftExtension?.constraints ?? []
    guard let constraintsText = renderConstraints(constraints) else {
        return reject("unrecognized extension constraint kind")
    }

    let slots = classified.slots
    let lskPositions = classified.lskPositions

    // Names for the Localizable slots and their inserted fallback parameters.
    var localizableNames: [String] = []
    var fallbackNames: [String] = []
    for (ordinal, position) in lskPositions.enumerated() {
        localizableNames.append(ordinal == 0 ? "localizable" : "localizable\(ordinal + 1)")
        let label = slots[position].label
        fallbackNames.append(label == "_"
            ? "defaultValue"
            : "default" + label.prefix(1).uppercased() + label.dropFirst())
    }

    // Inserted names must not collide with each other or with anything the
    // signature already names — a collision would shadow a forwarded value.
    var existingNames: Set<String> = []
    for slot in slots {
        existingNames.insert(slot.label)
        if let internalName = slot.internalName { existingNames.insert(internalName) }
    }
    let insertedNames = localizableNames + fallbackNames
    guard Set(insertedNames).count == insertedNames.count,
          existingNames.isDisjoint(with: insertedNames)
    else {
        return reject("inserted parameter name collides with an existing one")
    }

    // Splice plan over fragment indices: replacements land in place of a
    // fragment's spelling; insertions append immediately after one.
    var replaceAt: [Int: String] = [:]
    var insertAfter: [Int: String] = [:]

    for (ordinal, position) in lskPositions.enumerated() {
        let slot = slots[position]
        // The recognized LSK-slot shape: the whole type region is exactly one
        // fragment (the LocalizedStringKey type identifier — classification
        // already proved its USR) with no default value. Optional/aggregate/
        // defaulted spellings are unrecognized, not guessed at.
        guard let typeRange = slot.typeRange, typeRange.count == 1,
              slot.typeFragments == [fragments[typeRange.lowerBound]],
              slot.typeText == slot.typeFragments[0].spelling,
              !slot.hasDefaultValue
        else {
            return reject("LocalizedStringKey slot '\(slot.label)' is not a plain single-fragment type")
        }
        if let internalIndex = slot.internalParamIndex {
            replaceAt[internalIndex] = localizableNames[ordinal]
        } else {
            // No distinct internal name in the original — give the overload
            // one, keeping Apple's external label exactly.
            insertAfter[slot.labelIndex] = " " + localizableNames[ordinal]
        }
        replaceAt[typeRange.lowerBound] = "some Localizable"
        insertAfter[typeRange.lowerBound] = ", \(fallbackNames[ordinal]): String? = nil"
    }

    // Delegating-call arguments, one per slot, in declaration order — plus
    // the emit-facing facts gathered on the same walk: the generated
    // overload's label sequence and whether any passthrough parameter is
    // required (no default), which decides example synthesis.
    var forwardedValues: [String] = []
    var overloadLabels: [String] = []
    var hasOtherRequired = false
    for (index, slot) in slots.enumerated() {
        overloadLabels.append(slot.label)
        if let ordinal = lskPositions.firstIndex(of: index) {
            overloadLabels.append(fallbackNames[ordinal])
            var resolved = "\(localizableNames[ordinal])" +
                ".defaultedLocalizedString(defaultValue: \(fallbackNames[ordinal]))"
            if classified.policy == .textVerbatim {
                resolved = "Text(verbatim: \(resolved))"
            }
            forwardedValues.append(slot.label == "_" ? resolved : "\(slot.label): \(resolved)")
            continue
        }
        if !slot.hasDefaultValue { hasOtherRequired = true }
        guard !slot.typeText.hasPrefix("inout ") else {
            return reject("inout parameter '\(slot.label)' cannot be forwarded verbatim")
        }
        guard !slot.typeFragments.contains(where: {
            $0.kind == "attribute" && $0.spelling.contains("autoclosure")
        }) else {
            return reject("@autoclosure parameter '\(slot.label)' cannot be forwarded verbatim")
        }
        guard let name = slot.internalName ?? (slot.label == "_" ? nil : slot.label),
              !swiftKeywords.contains(name)
        else {
            return reject("parameter '\(slot.label)' has no forwardable internal name")
        }
        forwardedValues.append(slot.label == "_" ? name : "\(slot.label): \(name)")
    }

    var signature = ""
    for (index, fragment) in fragments.enumerated() {
        signature += replaceAt[index] ?? fragment.spelling
        if let insertion = insertAfter[index] { signature += insertion }
    }
    signature = signature.trimmingCharacters(in: .whitespacesAndNewlines)

    let arguments = forwardedValues.joined(separator: ", ")
    let bodyText = switch api.kind {
    case .initializer:
        "self.init(\(arguments))"
    case .method, .function:
        // api.member is "name(_:label:)" — the call name precedes the "(".
        "\(api.member.prefix(while: { $0 != "(" }))(\(arguments))"
    }

    return .transformed(TransformedOverload(
        api: api,
        policy: classified.policy,
        extendedType: api.extendedType,
        extensionConstraints: constraints,
        extensionConstraintsText: constraintsText,
        signatureText: signature,
        bodyText: bodyText,
        insertedSlots: lskPositions.indices.map { ordinal in
            InsertedSlot(
                localizableName: localizableNames[ordinal],
                fallbackName: fallbackNames[ordinal],
                appleLabel: slots[lskPositions[ordinal]].label
            )
        },
        hasOtherRequiredParameters: hasOtherRequired,
        overloadParameterLabels: overloadLabels,
        gatePlatforms: classified.delegatePlatforms.count == requiredSDKs.count
            ? []
            : gatePlatformOrder.filter { classified.delegatePlatforms.contains($0) }
    ))
}

struct TransformResult {
    let overloads: [TransformedOverload]
    let rejected: [RejectedCandidate]
    /// Overloads with more than one Localizable slot — expected rare.
    let multiSlotCount: Int
}

/// Stage 5 driver: transforms every classified API, preserving the input
/// order (already deterministically sorted by Union). Pure — no I/O.
func runTransform(_ classified: [ClassifiedAPI]) -> TransformResult {
    var overloads: [TransformedOverload] = []
    var rejected: [RejectedCandidate] = []
    var multiSlotCount = 0
    for item in classified {
        switch transform(item) {
        case .transformed(let overload):
            overloads.append(overload)
            if overload.insertedSlots.count > 1 { multiSlotCount += 1 }
        case .rejected(let reject):
            rejected.append(reject)
        }
    }
    return TransformResult(overloads: overloads, rejected: rejected, multiSlotCount: multiSlotCount)
}

// MARK: - Stage 6: Emit

// MARK: Output locations

/// Repo-relative output paths: Emit writes here, `--check` compares here.
let generatedDirRelativePath = "Sources/FOSMVVM/SwiftUI Support/Generated"
let manifestRelativePath = "Sources/FOSMVVM/SwiftUI Support/SweepCoverage.md"

// MARK: Generation stamp

/// The run identity as rendered into every generated file and the manifest:
/// the five SDK versions — and NOTHING else. Deliberately no date, no
/// timestamp, and no Xcode version: two machines with identical SDKs must
/// produce byte-identical output, and Xcode's version varies independently
/// of the SDKs (the CI runner's Xcode 26.6 shipped the same 26.5 SDKs —
/// an Xcode line here turned that skew into false whole-surface drift).
struct GenerationStamp {
    /// Format is load-bearing: readCheckedInSDKStamp parses this line back out
    /// of the manifest ("- SDKs: " prefix, " | " separator, "platform version").
    let sdkLine: String // "macosx 26.5 | iphoneos 26.5 | ..."
}

func makeGenerationStamp(sdks: [PlatformSDK]) -> GenerationStamp {
    GenerationStamp(
        // Writer side of readCheckedInSDKStamp's parser — change one, change both.
        sdkLine: sdks.map { "\($0.platform) \($0.version)" }.joined(separator: " | ")
    )
}

// MARK: Header rendering

/// The copyright year stamped into generated headers. swiftformat's
/// fileHeader rule resolves `{created.year}` from each file's creation date,
/// which for a checked-in file pins to the year it was first added — so
/// regeneration must never restamp the year, or `--check` would drift across
/// a year boundary. Bump only if swiftformat starts rewriting the header of
/// a newly ADDED generated file.
let generatedFileCopyrightYear = 2026

/// The Apache header exactly as the repo's swiftformat fileHeader rule
/// renders it (see `.swiftformat --header`), so a swiftformat pass over a
/// generated file is a no-op. The doubled space in `(the  License);`
/// reproduces the checked-in rendering byte-for-byte.
func renderLicenseHeader(fileName: String) -> String {
    """
    // \(fileName)
    //
    // Copyright \(generatedFileCopyrightYear) FOS Computer Services, LLC
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
    """
}

/// The DO-NOT-EDIT stamp: a SECOND comment block, separated from the Apache
/// header by a blank line so swiftformat's fileHeader rule leaves it intact.
///
/// The trailing swiftformat directive keeps Apple's generic signatures as the
/// graphs spell them: Transform copies generic parameter lists and `where`
/// clauses VERBATIM (spec rule), and the opaqueGenericParameters /
/// simplifyGenericConstraints rules would rewrite exactly those — the
/// directive resolves the conflict in the file, not in the repo config.
func renderGeneratedStamp(_ stamp: GenerationStamp) -> String {
    """
    // GENERATED FILE — DO NOT EDIT
    // Generated by scripts/localizable-overload-sweep.swift
    // SDKs: \(stamp.sdkLine)
    // Regenerate: swift scripts/localizable-overload-sweep.swift
    //
    // Generic signatures mirror Apple's declarations verbatim:
    // swiftformat:disable opaqueGenericParameters simplifyGenericConstraints
    """
}

// MARK: Availability rendering

/// The `@available` lines for one overload. A domain ABSENT from the
/// availability map gets no line at all — absence is not unavailability
/// (Apple's own annotations omit absent platforms; the trailing `*` covers
/// them). Only explicit `unavailable` records earn
/// `@available(<domain>, unavailable)` lines.
func renderAvailabilityLines(_ api: UnifiedAPI) -> [String] {
    var lines: [String] = []
    let surviving = api.surviving
    if !surviving.isEmpty {
        let arguments = surviving
            .map { "\($0.domain.rawValue) \($0.version.display)" }
            .joined(separator: ", ")
        lines.append("@available(\(arguments), *)")
    }
    for domain in api.unavailableDomains {
        lines.append("@available(\(domain.rawValue), unavailable)")
    }
    return lines
}

/// The `@available` lines for one extension BLOCK. The block HEADER
/// references the extended TYPE, so its `introduced` requirement is the
/// type's own availability (same floor clamp as members), taken from
/// Select's type index. Deriving it from the members was WRONG: omitting a
/// domain is not neutral — one member without (say) a tvOS entry dropped
/// tvOS from the annotation, and the wildcard `*` then claimed the block at
/// the tvOS floor, below the type's introduction (TabContent, tvOS 18).
/// All-members-unavailable domains keep their
/// `@available(<domain>, unavailable)` lines and win over an introduced
/// entry for the same domain.
///
/// Known theoretical residue: `where` clause constraint types are header
/// references too, and their availability is NOT derived here — Apple's
/// extension-block members have so far always carried compatible
/// constraints; the CI platform compiles are the backstop.
func renderBlockAvailabilityLines(
    typeAvailability: [AvailabilityDomain: DomainAvailability],
    members: [TransformedOverload]
) -> [String] {
    let unavailable = AvailabilityDomain.allCases.filter { domain in
        members.allSatisfy { $0.api.availability[domain] == .unavailable }
    }
    let introduced = AvailabilityDomain.allCases
        .compactMap { domain -> (domain: AvailabilityDomain, version: SemVer)? in
            guard !unavailable.contains(domain),
                  case .introduced(let version) = typeAvailability[domain],
                  version > domain.floor
            else { return nil }
            return (domain, version)
        }
    var lines: [String] = []
    if !introduced.isEmpty {
        let arguments = introduced
            .map { "\($0.domain.rawValue) \($0.version.display)" }
            .joined(separator: ", ")
        lines.append("@available(\(arguments), *)")
    }
    for domain in unavailable {
        lines.append("@available(\(domain.rawValue), unavailable)")
    }
    return lines
}

// MARK: DocC rendering

/// The Apple member the overload mirrors, qualified for the DocC one-liner.
func appleMemberTitle(_ overload: TransformedOverload) -> String {
    overload.extendedType.isEmpty
        ? overload.api.member
        : "\(overload.extendedType).\(overload.api.member)"
}

/// A one-line example call, or nil when a full expression is not
/// mechanically derivable (multiple Localizable slots, other required
/// parameters, or a member whose receiver we cannot mechanically
/// instantiate). Never guesses an argument value.
func exampleExpression(_ overload: TransformedOverload) -> String? {
    guard overload.insertedSlots.count == 1,
          !overload.hasOtherRequiredParameters,
          let slot = overload.insertedSlots.first
    else { return nil }
    let argument = slot.appleLabel == "_"
        ? "viewModel.title"
        : "\(slot.appleLabel): viewModel.title"
    let callName = overload.api.member.prefix(while: { $0 != "(" })
    switch overload.api.kind {
    case .initializer:
        return "\(overload.extendedType)(\(argument))"
    case .method, .function:
        if overload.extendedType.isEmpty {
            return "\(callName)(\(argument))"
        }
        // `EmptyView()` is the one mechanical receiver — every View member
        // applies to it. Members of other types fall back to the call shape.
        guard overload.extendedType == "View" else { return nil }
        return "EmptyView().\(callName)(\(argument))"
    }
}

/// The GENERATED overload's call shape (`Label(_:defaultValue:image:)`) —
/// the example fallback when no full expression is mechanical.
func callShape(_ overload: TransformedOverload) -> String {
    let labels = overload.overloadParameterLabels.map { "\($0):" }.joined()
    let callName = overload.api.member.prefix(while: { $0 != "(" })
    switch overload.api.kind {
    case .initializer:
        return "\(overload.extendedType)(\(labels))"
    case .method, .function:
        return overload.extendedType.isEmpty
            ? "\(callName)(\(labels))"
            : "\(overload.extendedType).\(callName)(\(labels))"
    }
}

/// Renders one overload's DocC block (unindented). The file's FIRST overload
/// carries the full example; the rest get the one-liner plus parameters.
/// Only the inserted parameters are documented — Apple's passthrough
/// parameters keep Apple's semantics, which this sweep never restates (and
/// never invents).
func renderDocC(_ overload: TransformedOverload, isFirstInFile: Bool) -> [String] {
    var lines = [
        "/// Localizable-accepting form of SwiftUI's `\(appleMemberTitle(overload))`."
    ]
    if isFirstInFile {
        lines.append("///")
        lines.append("/// ## Example")
        lines.append("///")
        lines.append("/// ```swift")
        lines.append("/// @ViewModel public struct MyViewModel: RequestableViewModel {")
        lines.append("///     @LocalizedString public var title")
        lines.append("///     ...")
        lines.append("/// }")
        lines.append("///")
        if let expression = exampleExpression(overload) {
            lines.append("/// // In a ViewModelView body:")
            lines.append("/// \(expression)")
        } else {
            lines.append("/// // Call shape — supply the remaining arguments:")
            lines.append("/// \(callShape(overload))")
        }
        lines.append("/// ```")
    }
    lines.append("///")
    lines.append("/// - Parameters:")
    for slot in overload.insertedSlots {
        lines.append("///   - \(slot.localizableName): The ``Localizable`` to display.")
        lines.append("///   - \(slot.fallbackName): Fallback text used if localization did not complete.")
    }
    return lines
}

// MARK: File rendering

/// One rendered generated source file.
struct GeneratedFile {
    let fileName: String
    let contents: String
    let overloadCount: Int
}

/// The module a Swift-mangled USR names (`s:22UniformTypeIdentifiers6UTTypeV`
/// -> `UniformTypeIdentifiers`), or nil for stdlib shortcuts and clang USRs.
func mangledModuleName(_ usr: String) -> String? {
    guard usr.hasPrefix("s:") else { return nil }
    let rest = usr.dropFirst(2)
    let digits = rest.prefix(while: \.isNumber)
    guard !digits.isEmpty, let length = Int(digits) else { return nil }
    let name = rest.dropFirst(digits.count).prefix(length)
    guard name.count == length else { return nil }
    return String(name)
}

/// Modules the emitted signatures reference beyond the SwiftUI umbrella —
/// e.g. `DocumentLaunchView` inits take `UTType`, which needs
/// `import UniformTypeIdentifiers`. Derived from the type fragments' USR
/// manglings; never guessed from spellings.
func additionalImports(_ overloads: [TransformedOverload]) -> [String] {
    var modules: Set<String> = []
    for overload in overloads {
        for fragment in overload.api.declarationFragments
            where fragment.kind == "typeIdentifier" {
            guard let module = mangledModuleName(fragment.preciseIdentifier ?? ""),
                  module != "Swift", module != "SwiftUI", module != "SwiftUICore"
            else { continue }
            modules.insert(module)
        }
    }
    return modules.sorted()
}

/// xcrun SDK name -> `#if os(...)` condition token. macCatalyst compiles as
/// part of the iOS build and has no SDK or symbol graphs of its own, so
/// `os(iOS)` is the closest expressible gate for iphoneos-backed presence.
let osConditionByPlatform: [String: String] = [
    "macosx": "os(macOS)",
    "iphoneos": "os(iOS)",
    "appletvos": "os(tvOS)",
    "watchos": "os(watchOS)",
    "xros": "os(visionOS)"
]

/// Renders one overload: availability annotation(s), DocC, declaration.
/// The single emit-time text normalization: constraint spacing `S : P` (as
/// the graphs spell it) becomes `S: P` — the spelling swiftformat's
/// spaceAroundOperators rule demands, and the emitter must be a fixed point
/// of the repo's swiftformat pass.
///
/// A member with `gatePlatforms` is wrapped in `#if os(...)`: its delegate
/// exists only in those platforms' SDK graphs, and `@available(<os>,
/// unavailable)` does not exempt a body from a platform's typechecking —
/// only a compile-time gate does. The `@available` lines still render inside
/// the gate: they carry OS-version floors, a different job from SDK
/// membership.
func renderMember(
    _ overload: TransformedOverload,
    isFirstInFile: Bool,
    indent: String,
    accessPrefix: String
) -> [String] {
    var lines: [String] = []
    // DocC precedes the availability attributes: swiftformat's
    // docCommentsBeforeModifiers rule rewrites the reverse order.
    lines += renderDocC(overload, isFirstInFile: isFirstInFile)
    lines += renderAvailabilityLines(overload.api)
    let signature = overload.signatureText.replacingOccurrences(of: " : ", with: ": ")
    lines.append("\(accessPrefix)\(signature) {")
    lines.append("    \(overload.bodyText)")
    lines.append("}")
    if !overload.gatePlatforms.isEmpty {
        let condition = overload.gatePlatforms
            .compactMap { osConditionByPlatform[$0] }
            .joined(separator: " || ")
        lines = ["#if \(condition)"] + lines + ["#endif"]
    }
    return lines.map { indent + $0 }
}

/// Renders the complete source file for one extended type. Extension blocks
/// are ordered by constraint clause text (unconstrained first); members
/// within a block are ordered by USR. Both orders are deterministic; neither
/// is semantic.
///
/// The `+Localizable` basename suffix is load-bearing, not style: SwiftPM
/// derives object-file names from source basenames, so two files named
/// `View.swift` in one target — the retained hand-written one and a generated
/// one — fail the build with "multiple producers". The suffix keeps every
/// generated basename disjoint from the hand-written sources forever.
func renderGeneratedFile(
    extendedType: String,
    overloads: [TransformedOverload],
    stamp: GenerationStamp,
    typeAvailability: [String: [AvailabilityDomain: DomainAvailability]]
) throws -> GeneratedFile {
    let fileName = (extendedType.isEmpty ? "GlobalFunctions" : extendedType) + "+Localizable.swift"

    // The extension header's availability comes from the TYPE it references.
    // A swept member whose extended type never appeared as a public type
    // symbol would mean the type index is broken — never guess an annotation.
    var extendedTypeAvailability: [AvailabilityDomain: DomainAvailability] = [:]
    if !extendedType.isEmpty {
        guard let availability = typeAvailability[extendedType] else {
            throw Failure("no indexed availability for extended type '\(extendedType)' — " +
                "cannot annotate its extension header")
        }
        extendedTypeAvailability = availability
    }

    var blockOrder: [String] = []
    var blocks: [String: [TransformedOverload]] = [:]
    for overload in overloads {
        if blocks[overload.extensionConstraintsText] == nil {
            blockOrder.append(overload.extensionConstraintsText)
        }
        blocks[overload.extensionConstraintsText, default: []].append(overload)
    }
    blockOrder.sort()

    var lines: [String] = []
    lines.append(renderLicenseHeader(fileName: fileName))
    lines.append("")
    lines.append(renderGeneratedStamp(stamp))
    lines.append("")
    lines.append("#if canImport(SwiftUI)")
    for module in (["SwiftUI"] + additionalImports(overloads)).sorted() {
        lines.append("import \(module)")
    }

    var isFirstInFile = true
    for constraintsText in blockOrder {
        let members = blocks[constraintsText]!.sorted { $0.api.usr < $1.api.usr }
        lines.append("")
        if extendedType.isEmpty {
            // Free functions: no extension block. `public` is spelled on the
            // member — top-level declarations do not inherit it the way
            // `public extension` members do.
            for (index, member) in members.enumerated() {
                if index > 0 { lines.append("") }
                lines += renderMember(
                    member, isFirstInFile: isFirstInFile, indent: "", accessPrefix: "public "
                )
                isFirstInFile = false
            }
        } else {
            let clause = constraintsText.isEmpty ? "" : " \(constraintsText)"
            lines += renderBlockAvailabilityLines(
                typeAvailability: extendedTypeAvailability, members: members
            )
            lines.append("public extension \(extendedType)\(clause) {")
            for (index, member) in members.enumerated() {
                if index > 0 { lines.append("") }
                lines += renderMember(
                    member, isFirstInFile: isFirstInFile, indent: "    ", accessPrefix: ""
                )
                isFirstInFile = false
            }
            lines.append("}")
        }
    }
    lines.append("#endif")
    return GeneratedFile(
        fileName: fileName,
        contents: lines.joined(separator: "\n") + "\n",
        overloadCount: overloads.count
    )
}

// MARK: Manifest rendering

/// The manifest's section order — the closed set of rejection reasons.
let manifestReasonOrder: [RejectionReason] = [.deprecated, .noDelegateTarget, .unrecognizedShape]

/// One manifest reject line: the per-stage rejects merged by (USR, reason) —
/// a Select-stage deprecated reject arrives once per platform graph — so
/// every skipped API appears exactly once per reason.
struct ManifestReject {
    let title: String
    let usr: String
    let reason: RejectionReason
    let platforms: [String]
    let note: String?
}

func mergeRejects(_ rejects: [RejectedCandidate]) -> [ManifestReject] {
    struct Key: Hashable {
        let usr: String
        let reason: String
    }
    var order: [Key] = []
    var grouped: [Key: (first: RejectedCandidate, platforms: Set<String>)] = [:]
    for reject in rejects {
        let key = Key(usr: reject.usr, reason: reject.reason.rawValue)
        if var existing = grouped[key] {
            existing.platforms.formUnion(reject.contributingPlatforms)
            grouped[key] = existing
        } else {
            order.append(key)
            grouped[key] = (reject, Set(reject.contributingPlatforms))
        }
    }
    return order.map { key in
        let (first, platforms) = grouped[key]!
        return ManifestReject(
            title: first.title,
            usr: first.usr,
            reason: first.reason,
            platforms: platforms.sorted(),
            note: first.note
        )
    }.sorted { ($0.title, $0.usr) < ($1.title, $1.usr) }
}

/// Renders `SweepCoverage.md`. Every candidate that did not become an
/// overload appears exactly once under its closed-set reason; the beta-tier
/// section is emitted even when empty so its appearance or disappearance is
/// diff-visible.
func renderManifest(
    stamp: GenerationStamp,
    sweptCandidateRows: Int,
    uniqueAPIs: Int,
    overloads: [TransformedOverload],
    rejects: [RejectedCandidate],
    betaTierAPIs: [UnifiedAPI]
) -> String {
    let merged = mergeRejects(rejects)

    var lines: [String] = []
    lines.append("# Sweep Coverage")
    lines.append("")
    lines.append("GENERATED FILE — DO NOT EDIT.")
    lines.append("Generated by `scripts/localizable-overload-sweep.swift`.")
    lines.append("")
    lines.append("- SDKs: \(stamp.sdkLine)")
    lines.append("- Regenerate: `swift scripts/localizable-overload-sweep.swift`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("- Swept candidate rows (pre-union, across all platform graphs): \(sweptCandidateRows)")
    lines.append("- Unique APIs (post-union): \(uniqueAPIs)")
    lines.append("- Generated overloads: \(overloads.count)")
    lines.append("  - policy `direct` (String sibling): " +
        "\(overloads.count(where: { $0.policy == .direct }))")
    lines.append("  - policy `text-verbatim` (Text sibling): " +
        "\(overloads.count(where: { $0.policy == .textVerbatim }))")
    for reason in manifestReasonOrder {
        lines.append("- Rejected — `\(reason.rawValue)`: " +
            "\(merged.count(where: { $0.reason == reason }))")
    }

    for reason in manifestReasonOrder {
        lines.append("")
        lines.append("## Rejected — \(reason.rawValue)")
        lines.append("")
        let section = merged.filter { $0.reason == reason }
        if section.isEmpty {
            lines.append("None.")
        }
        for reject in section {
            lines.append("- `\(reject.title)` — platforms: " +
                reject.platforms.joined(separator: ", "))
            if let note = reject.note {
                lines.append("  - \(note)")
            }
        }
    }

    lines.append("")
    lines.append("## Beta-tier (informational)")
    lines.append("")
    if betaTierAPIs.isEmpty {
        lines.append("None.")
    }
    for api in betaTierAPIs {
        let domains = AvailabilityDomain.allCases
            .filter { api.betaTierDomains.contains($0) }
            .map(\.rawValue)
            .joined(separator: ", ")
        lines.append("- `\(api.pathComponents.joined(separator: "."))` — beta on: \(domains)")
    }
    return lines.joined(separator: "\n") + "\n"
}

// MARK: Emit driver

/// Everything a run renders: one source file per extended type, in
/// deterministic (sorted) file order, plus the manifest.
struct EmitOutput {
    let files: [GeneratedFile]
    let manifest: String
}

/// The full render — pure; no I/O. Throws only when a swept member's
/// extended type has no indexed availability (a broken type index).
func renderEmitOutput(
    overloads: [TransformedOverload],
    rejects: [RejectedCandidate],
    betaTierAPIs: [UnifiedAPI],
    sweptCandidateRows: Int,
    uniqueAPIs: Int,
    stamp: GenerationStamp,
    typeAvailability: [String: [AvailabilityDomain: DomainAvailability]]
) throws -> EmitOutput {
    var typeOrder: [String] = []
    var byType: [String: [TransformedOverload]] = [:]
    for overload in overloads {
        if byType[overload.extendedType] == nil { typeOrder.append(overload.extendedType) }
        byType[overload.extendedType, default: []].append(overload)
    }
    typeOrder.sort()

    return try EmitOutput(
        files: typeOrder.map {
            try renderGeneratedFile(
                extendedType: $0, overloads: byType[$0]!, stamp: stamp,
                typeAvailability: typeAvailability
            )
        },
        manifest: renderManifest(
            stamp: stamp,
            sweptCandidateRows: sweptCandidateRows,
            uniqueAPIs: uniqueAPIs,
            overloads: overloads,
            rejects: rejects,
            betaTierAPIs: betaTierAPIs
        )
    )
}

/// Writes the rendered output into the package tree. The Generated directory
/// is replaced wholesale so files for types that vanished from the SDKs
/// cannot linger.
func writeEmitOutput(_ output: EmitOutput, packageRoot: URL) throws {
    let generatedDir = packageRoot
        .appendingPathComponent(generatedDirRelativePath, isDirectory: true)
    do {
        if FileManager.default.fileExists(atPath: generatedDir.path) {
            try FileManager.default.removeItem(at: generatedDir)
        }
        try FileManager.default.createDirectory(at: generatedDir, withIntermediateDirectories: true)
        for file in output.files {
            try Data(file.contents.utf8)
                .write(to: generatedDir.appendingPathComponent(file.fileName))
        }
        try Data(output.manifest.utf8)
            .write(to: packageRoot.appendingPathComponent(manifestRelativePath))
    } catch {
        throw Failure("could not write generated output: \(error)")
    }
}

// MARK: Check mode

// MARK: Staleness gate — SDK stamp comparison

/// The checked-in SDK stamp, parsed from SweepCoverage.md's `- SDKs:` line into
/// platform -> version. That manifest line is the SINGLE source of the stamp;
/// every generated file header carries the same string. Throws if the manifest
/// or the line is absent (a check with no baseline to compare against) or the
/// line is malformed — a stamp that cannot be read is a hard error, never a
/// silent skip.
func readCheckedInSDKStamp(packageRoot: URL) throws -> [String: String] {
    let url = packageRoot.appendingPathComponent(manifestRelativePath)
    let contents: String
    do {
        contents = try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw Failure("could not read \(manifestRelativePath) for the SDK stamp: \(error)")
    }
    let prefix = "- SDKs: "
    guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
        throw Failure("no `- SDKs:` line in \(manifestRelativePath) — " +
            "cannot determine the checked-in stamp")
    }
    var stamp: [String: String] = [:]
    for piece in String(line.dropFirst(prefix.count)).components(separatedBy: " | ") {
        let parts = piece.split(separator: " ")
        guard parts.count == 2 else {
            throw Failure("malformed SDK stamp entry '\(piece)' in \(manifestRelativePath)")
        }
        stamp[String(parts[0])] = String(parts[1])
    }
    return stamp
}

/// Resolves each required SDK's version WITHOUT the hard-exit that full
/// generation uses. `--check` treats an unresolvable SDK as a skip-trigger (a
/// runner may lack, e.g., the visionOS image), so this reports `nil` for a
/// platform whose SDK version cannot be read rather than refusing to run.
///
/// Twin of `resolveSDKs` (full-generation mode) — the two must stay in
/// lockstep on the missing-SDK rule (non-zero xcrun status OR empty stdout =
/// missing); only the CONSEQUENCE differs (skip here, hard exit there).
func resolveSDKVersionsForCheck() throws -> [(platform: String, version: String?)] {
    var result: [(platform: String, version: String?)] = []
    for platform in requiredSDKs {
        let versionResult = try runXcrun(["--sdk", platform, "--show-sdk-version"])
        let version = (versionResult.status == 0 && !versionResult.stdout.isEmpty)
            ? versionResult.stdout : nil
        result.append((platform, version))
    }
    return result
}

/// Compares the runner's five SDK versions against the checked-in stamp and
/// prints a per-platform verdict. Returns true only when EVERY platform matches
/// (the byte-compare should run); false when any platform's SDK version differs
/// from the stamp, its SDK is missing, or the stamp names a platform that is no
/// longer required (informational SKIP — regeneration is a deliberate act). A
/// byte-compare on a different SDK would flag all files as
/// drifted, indistinguishable from real drift, so the mismatch path never fails
/// the gate. Runs BEFORE the expensive extraction so a skip is cheap.
func stampComparisonPasses(packageRoot: URL) throws -> Bool {
    let stamp = try readCheckedInSDKStamp(packageRoot: packageRoot)
    let resolved = try resolveSDKVersionsForCheck()

    print("== Staleness gate: SDK stamp comparison ==")
    var allMatch = true
    // Verdict column is 13 wide: the longest label ("NOT IN STAMP", 12) must
    // still leave a separator space before the detail text.
    for (platform, runnerVersion) in resolved {
        let stampVersion = stamp[platform]
        let verdict: String
        switch (stampVersion, runnerVersion) {
        case (let stamped?, let runner?) where stamped == runner:
            verdict = pad("MATCH", 13) + "stamp \(stamped)   runner \(runner)"
        case (let stamped?, let runner?):
            verdict = pad("MISMATCH", 13) + "stamp \(stamped)   runner \(runner)"
            allMatch = false
        case (let stamped?, nil):
            verdict = pad("SDK MISSING", 13) + "stamp \(stamped)   runner (not installed)"
            allMatch = false
        case (nil, let runner?):
            verdict = pad("NOT IN STAMP", 13) + "runner \(runner)"
            allMatch = false
        case (nil, nil):
            verdict = "SDK MISSING + NOT IN STAMP"
            allMatch = false
        }
        print("  \(pad(platform, 12))\(verdict)")
    }
    // Reverse direction: a stamp entry for a platform this script no longer
    // requires means the stamp predates a requiredSDKs change — the checked-in
    // output cannot be trusted against today's platform set, so skip.
    for platform in stamp.keys.sorted() where !requiredSDKs.contains(platform) {
        print("  \(pad(platform, 12))\(pad("STAMP ONLY", 13))stamp \(stamp[platform]!)   " +
            "(not a required SDK anymore)")
        allMatch = false
    }
    if allMatch {
        print("  all five SDKs match the checked-in stamp — running byte-compare")
    } else {
        print("\n  staleness gate SKIPPED (SDK mismatch — regeneration is a deliberate act)")
    }
    return allMatch
}

/// Left-justifies `text` to `width` columns for the verdict listing.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

/// Shells to `/usr/bin/diff -u` and returns at most `maxLines` lines of the
/// unified diff. Output is captured via a temp file, not a pipe — large
/// diffs would deadlock a pipe buffer.
func unifiedDiffExcerpt(checkedIn: URL, rendered: String, maxLines: Int) -> [String] {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory
        .appendingPathComponent("sweep-diff-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: dir) }
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderedURL = dir.appendingPathComponent("rendered")
        try rendered.write(to: renderedURL, atomically: true, encoding: .utf8)
        let outURL = dir.appendingPathComponent("diff.out")
        fm.createFile(atPath: outURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = ["-u", checkedIn.path, renderedURL.path]
        process.standardOutput = out
        process.standardError = out
        try process.run()
        process.waitUntilExit()
        try out.close()
        let text = try String(contentsOf: outURL, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines)) + ["… diff truncated at \(maxLines) lines"]
        }
        return lines
    } catch {
        return ["(diff unavailable: \(error))"]
    }
}

struct DriftReport {
    /// One line per drifted file: `missing:` / `differs:` / `stale:`.
    let drift: [String]
    /// Bounded unified-diff excerpts (the manifest's always, plus the first
    /// two differing generated files) so a remote CI failure is diagnosable
    /// from the job log alone.
    let diagnostics: [String]
}

/// Byte-compares the freshly rendered output against the checked-in files
/// and returns the drift list (empty when clean). Missing, differing, and
/// stale (checked in but no longer generated) files all count. The SDK/Xcode
/// stamp lines participate in the byte-compare, but only after
/// `stampComparisonPasses` has confirmed every runner SDK matches the stamp —
/// so a stamp-line difference here can only be real drift, never an SDK skew.
func driftReport(_ output: EmitOutput, packageRoot: URL) -> DriftReport {
    var expected: [String: String] = [:]
    for file in output.files {
        expected["\(generatedDirRelativePath)/\(file.fileName)"] = file.contents
    }
    expected[manifestRelativePath] = output.manifest

    var drift: [String] = []
    var diagnostics: [String] = []
    var fileExcerptsEmitted = 0
    for (relativePath, contents) in expected.sorted(by: { $0.key < $1.key }) {
        let url = packageRoot.appendingPathComponent(relativePath)
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            drift.append("missing: \(relativePath)")
            continue
        }
        if existing != contents {
            drift.append("differs: \(relativePath)")
            let isManifest = relativePath == manifestRelativePath
            if isManifest || fileExcerptsEmitted < 2 {
                if !isManifest { fileExcerptsEmitted += 1 }
                diagnostics.append("--- diff excerpt: \(relativePath) ---")
                diagnostics.append(contentsOf: unifiedDiffExcerpt(
                    checkedIn: url,
                    rendered: contents,
                    maxLines: isManifest ? 120 : 60
                ))
            }
        }
    }

    let generatedDir = packageRoot
        .appendingPathComponent(generatedDirRelativePath, isDirectory: true)
    let checkedIn = (try? FileManager.default.contentsOfDirectory(
        at: generatedDir, includingPropertiesForKeys: nil
    )) ?? []
    for url in checkedIn.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        guard url.pathExtension == "swift" else { continue }
        let relativePath = "\(generatedDirRelativePath)/\(url.lastPathComponent)"
        if expected[relativePath] == nil {
            drift.append("stale: \(relativePath)")
        }
    }
    return DriftReport(drift: drift, diagnostics: diagnostics)
}

// MARK: - Main

/// Returns the process exit code (nonzero only for `--check` drift; every
/// hard failure throws instead).
func main(options: Options) throws -> Int32 {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("localizable-overload-sweep-\(UUID().uuidString)", isDirectory: true)
    // Cleanup must run on failure paths too — a mid-pipeline throw would
    // otherwise leak multi-GB graph JSON. Failure and success paths agree.
    defer {
        if options.keepGraphs {
            print("Graphs kept at: \(tempRoot.path)")
        } else {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    // Staleness gate: before the expensive extraction, compare the runner's SDK
    // versions against the checked-in stamp. A mismatch (or a missing SDK) is an
    // informational SKIP (exit 0) — regeneration is a deliberate act, and a
    // byte-compare on a different SDK would flag every file as drifted,
    // indistinguishable from real drift. Only when all five match does the full
    // pipeline + byte-compare run.
    if options.check {
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("Package.swift").path
        ) else {
            throw Failure("run from the package root — no Package.swift in \(packageRoot.path)")
        }
        guard try stampComparisonPasses(packageRoot: packageRoot) else {
            return 0
        }
    }

    let (sdks, graphs) = try runExtract(outputRoot: tempRoot)

    print("\nExtracted \(graphs.count) graph group(s) across \(sdks.count) platform(s).")

    let typeUSRs = try discoverTypeUSRs(graphs)
    print("\n== LocalizedStringKey USR(s) ==")
    for usr in typeUSRs.lsk.sorted() {
        print("  \(usr)")
    }
    print("== Text USR(s) ==")
    for usr in typeUSRs.text.sorted() {
        print("  \(usr)")
    }

    let selection = try runSelect(graphs: graphs, lskUSRs: typeUSRs.lsk, filter: options.filter)

    if let filter = options.filter {
        print("\n== Candidates (extended type == \(filter)) ==")
        let sorted = selection.candidates.sorted {
            ($0.member, $0.platform, $0.module) < ($1.member, $1.platform, $1.module)
        }
        for candidate in sorted {
            print("  \(candidate.platform)  \(candidate.module)  " +
                "\(candidate.extendedType).\(candidate.member)  [\(candidate.kind.rawValue)]")
        }
        print("  \(selection.candidates.count) candidate(s) (pre-union, across all graphs).")
    } else {
        var byKind: [CandidateKind: Int] = [:]
        for candidate in selection.candidates {
            byKind[candidate.kind, default: 0] += 1
        }
        print("\n== Candidate totals (pre-union, across all graphs) ==")
        print("  total: \(selection.candidates.count)")
        for kind in CandidateKind.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            print("  \(kind.rawValue): \(byKind[kind, default: 0])")
        }
        print("  rejected (deprecated): \(selection.rejected.count)")
        print("  synthesized rows collapsed onto canonical USRs: \(selection.synthesizedRowsCollapsed)")
    }

    let union = runUnion(candidates: selection.candidates, sdks: sdks)

    let policy = runPolicy(
        apis: union.apis,
        siblings: selection.siblingIndex,
        lskUSRs: typeUSRs.lsk,
        textUSRs: typeUSRs.text
    )
    let transformed = runTransform(policy.classified)

    // Single manifest source: every stage's rejects join one list.
    let manifestRejects = selection.rejected + policy.rejected + transformed.rejected

    var verdictByUSR: [String: String] = [:]
    for item in policy.classified {
        verdictByUSR[item.api.usr] = "policy: \(item.policy.rawValue)"
    }
    for reject in policy.rejected {
        verdictByUSR[reject.usr] = "rejected: \(reject.reason.rawValue)"
    }

    if let filter = options.filter {
        print("\n== Unified APIs (extended type == \(filter)) ==")
        for api in union.apis.sorted(by: { ($0.member, $0.usr) < ($1.member, $1.usr) }) {
            print("  \(api.extendedType).\(api.member)  [\(api.kind.rawValue)]")
            print("     \(verdictByUSR[api.usr] ?? "policy: (unclassified?)")")
            let introduced = api.surviving
                .map { "\($0.domain.rawValue) \($0.version.display)" }
                .joined(separator: ", ")
            print("     introduced: \(introduced.isEmpty ? "(none — all at/below floor)" : introduced)")
            let unavailable = api.unavailableDomains.map(\.rawValue).joined(separator: ", ")
            if !unavailable.isEmpty { print("     unavailable: \(unavailable)") }
            if !api.betaTierDomains.isEmpty {
                let beta = api.betaTierDomains.map(\.rawValue).sorted().joined(separator: ", ")
                print("     beta-tier: \(beta)")
            }
            if api.hasFragmentDisagreement {
                print("     !! fragment disagreement across: " +
                    "\(api.contributingPlatforms.joined(separator: ", "))")
            }
            print("     annotation: \(api.hasAnnotation ? "yes" : "none")  " +
                "platforms: \(api.contributingPlatforms.joined(separator: ", "))")
        }

        print("\n== Transformed overloads (extended type == \(filter)) ==")
        for overload in transformed.overloads {
            let constraintSuffix = overload.extensionConstraintsText.isEmpty
                ? "" : " \(overload.extensionConstraintsText)"
            if overload.extendedType.isEmpty {
                print("\(overload.signatureText) {")
                print("    \(overload.bodyText)")
                print("}")
            } else {
                print("public extension \(overload.extendedType)\(constraintSuffix) {")
                print("    \(overload.signatureText) {")
                print("        \(overload.bodyText)")
                print("    }")
                print("}")
            }
            print("")
        }
    }

    let stats = union.stats
    print("\n== Union summary ==")
    print("  unique APIs (post-union): \(stats.uniqueAPIs)")
    print("  with surviving annotations: \(stats.annotated)")
    print("  beta-tier (>=1 domain at its SDK version): \(stats.betaTier)")
    print("  fragment disagreements across platforms: \(stats.fragmentDisagreements)")
    print("  availability conflicts across platforms: \(stats.availabilityConflicts)")
    print("  candidate contribution per platform:")
    for platform in requiredSDKs {
        print("    \(platform): \(stats.platformContribution[platform, default: 0])")
    }

    let policyStats = policy.stats
    print("\n== Delegate policy summary ==")
    print("  direct (String sibling): \(policyStats.direct)")
    print("  text-verbatim (Text sibling): \(policyStats.textVerbatim)")
    print("  rejected no-delegate-target: \(policyStats.rejectedNoDelegateTarget)")
    print("  rejected unrecognized-shape: \(policyStats.rejectedUnrecognizedShape)")
    print("    of which LocalizedStringKey in return position only: \(policyStats.lskReturnOnly)")
    print("  String-sibling spellings (per matched LSK slot):")
    for spelling in StringSiblingSpelling.allCases {
        print("    \(spelling.rawValue): \(policyStats.spellingCounts[spelling, default: 0])")
    }
    print("\n== Transform summary ==")
    print("  transformed: \(transformed.overloads.count)")
    print("  multi-Localizable-slot overloads: \(transformed.multiSlotCount)")
    print("  rejected at transform (unrecognized-shape): \(transformed.rejected.count)")
    for reject in transformed.rejected {
        print("    !! \(reject.usr)")
        if let note = reject.note {
            print("       \(note)")
        }
    }

    print("\n  manifest rejects (select + policy + transform): \(manifestRejects.count)")
    print("  sibling index entries: \(selection.siblingIndex.entryCount)")

    var exitCode: Int32 = 0
    if options.filter != nil {
        // A filtered run renders a partial surface — writing it would wipe
        // the full Generated/ directory. Filter is a debugging affordance;
        // emit is skipped outright.
        print("\n== Emit ==\n  skipped (--filter set)")
    } else {
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("Package.swift").path
        ) else {
            throw Failure("run from the package root — no Package.swift in \(packageRoot.path)")
        }

        let stamp = makeGenerationStamp(sdks: sdks)
        let output = try renderEmitOutput(
            overloads: transformed.overloads,
            rejects: manifestRejects,
            betaTierAPIs: union.apis.filter { !$0.betaTierDomains.isEmpty },
            sweptCandidateRows: selection.candidates.count,
            uniqueAPIs: union.stats.uniqueAPIs,
            stamp: stamp,
            typeAvailability: selection.typeAvailability
        )

        print("\n== Emit ==")
        print("  files: \(output.files.count)  overloads: \(transformed.overloads.count)")
        let gated = transformed.overloads.filter { !$0.gatePlatforms.isEmpty }
        print("  #if-gated members (delegate absent from some SDK graph): \(gated.count)")
        for overload in gated {
            print("    \(overload.extendedType).\(overload.api.member) -> " +
                overload.gatePlatforms.joined(separator: ", "))
        }
        for file in output.files {
            print("    \(file.fileName): \(file.overloadCount) overload(s)")
        }

        if options.check {
            let report = driftReport(output, packageRoot: packageRoot)
            if report.drift.isEmpty {
                print("  --check: clean — checked-in output matches regeneration")
            } else {
                print("  --check: DRIFT in \(report.drift.count) file(s):")
                for line in report.drift {
                    print("    \(line)")
                }
                for line in report.diagnostics {
                    print("    \(line)")
                }
                exitCode = 1
            }
        } else {
            try writeEmitOutput(output, packageRoot: packageRoot)
            print("  wrote \(generatedDirRelativePath)/ and \(manifestRelativePath)")
        }
    }

    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print(String(format: "  peak RSS: %.0f MB", Double(usage.ru_maxrss) / 1048576))
    return exitCode
}

let options = parseOptions()

if options.check, options.filter != nil {
    fail("--check cannot be combined with --filter")
}

do {
    let exitCode = try main(options: options)
    exit(exitCode)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
