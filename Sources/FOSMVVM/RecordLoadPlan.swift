// RecordLoadPlan.swift
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

import Foundation

// swiftformat:disable:next docComments
// package: consumed by FOSMVVMVapor's executor — a different target of this
// package; no app-facing need; internal cannot cross modules; package is the
// only level that serves. Its `tuples(matching:)` member serves one further
// cross-module consumer — FOSMVVMVapor's `ProjectionContext.records(_:)`, which
// resolves a sealed requirement handle (by its hidden declaration token) to the
// exact tuple(s) the walk derived from that declaration site; same target
// boundary, same justification. Its `requirementTokensAreStable(for:)` member
// serves that same consumer — FOSMVVMVapor's boot registration lints a factory's
// `dataRequirements`/`candidates` for token stability, reading only a Bool verdict
// (never a token value) across the boundary.
/// The walk's output for one root factory: every record load its composition
/// graph declares, absolute and deduplicated, ready for the executor to resolve.
///
/// ```swift
/// let plan = try RecordLoadPlan.walk(from: BerthsViewModel.self)
/// for tuple in plan.tuples { /* resolve + load through the engine */ }
/// ```
///
/// Build one only through ``walk(from:)`` — at boot, once per request type; the
/// request *instance* never changes the plan, it only parameterizes resolution.
package struct RecordLoadPlan: Hashable, Sendable {
    /// The declared loads, in deterministic walk order (a factory's own
    /// requirements first, then its children depth-first, declaration order).
    package let tuples: [Tuple]

    /// The M2 collapse-legality map: maximal runs of consecutive ``tuples``
    /// indices that share root, anchor, and operation. Boundaries fall wherever
    /// any of the three changes — a `.guards` anchor always starts a new run.
    package let collapseRuns: [Range<Int>]

    /// Declaration-site identity → the ``tuples`` indices the walk derived from that
    /// declaration. One index is the normal case; several means the same declaration was
    /// composed onto multiple distinct paths (e.g. the same child composed twice) — genuine
    /// ambiguity the reader must reject. Internal: the token vocabulary never leaves FOSMVVM;
    /// cross-module reads go through ``tuples(matching:)``.
    ///
    /// Excluded from Hashable (see the manual conformance below): tokens are declaration
    /// IDENTITY, not walk structure — a factory whose `dataRequirements` is a computed var
    /// mints fresh tokens per walk, yet its two walks are structurally the same plan.
    let declarationTuples: [ObjectIdentifier: [Int]]

    // MARK: Hashable Protocol

    /// Structural identity only — tuples + collapseRuns; declarationTuples deliberately
    /// excluded (identity map, not structure — see its comment).
    package static func == (lhs: RecordLoadPlan, rhs: RecordLoadPlan) -> Bool {
        lhs.tuples == rhs.tuples && lhs.collapseRuns == rhs.collapseRuns
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(tuples)
        hasher.combine(collapseRuns)
    }

    /// One declared load: records of one type, on one absolute containment
    /// path, under one authority. Identity — every stored property — is what
    /// the walk dedups on: same-anchor duplicates collapse; different anchors
    /// are different security questions and never merge.
    package struct Tuple: Hashable, Sendable {
        /// The source of the root this load descends from. `.parentRoot`
        /// declarations resolve through the composition chain: to the nearest
        /// `.newRoot` ancestor's source, else to the request root (`.query`).
        package let root: RootSource

        /// The absolute containment hops from the root down to — but not
        /// including — ``recordType``, in traversal order.
        package let path: [any Model.Type]

        /// The record type this tuple loads — the implicit terminal hop.
        package let recordType: any Model.Type

        /// The authority the load exercises.
        package let operation: ContainerOperation

        /// The last `.guards` container type traversed on ``path`` — the
        /// type-position the executor binds `authorizedAs:` to once that level
        /// has loaded. `nil` means the tuple's own root anchors.
        package let anchor: (any Model.Type)?

        /// Whether the request type's declared refinement axes land here.
        package let isRefinedByRequest: Bool

        package init(
            root: RootSource,
            path: [any Model.Type],
            recordType: any Model.Type,
            operation: ContainerOperation,
            anchor: (any Model.Type)?,
            isRefinedByRequest: Bool
        ) {
            self.root = root
            self.path = path
            self.recordType = recordType
            self.operation = operation
            self.anchor = anchor
            self.isRefinedByRequest = isRefinedByRequest
        }

        // MARK: Hashable Protocol

        // swiftformat:disable:next docComments
        // Metatype members hash by ObjectIdentifier — type identity, which the SPMLibraries umbrella keeps unique across target boundaries.
        package static func == (lhs: Tuple, rhs: Tuple) -> Bool {
            lhs.root == rhs.root
                && lhs.path.map(ObjectIdentifier.init) == rhs.path.map(ObjectIdentifier.init)
                && ObjectIdentifier(lhs.recordType) == ObjectIdentifier(rhs.recordType)
                && lhs.operation == rhs.operation
                && lhs.anchor.map(ObjectIdentifier.init) == rhs.anchor.map(ObjectIdentifier.init)
                && lhs.isRefinedByRequest == rhs.isRefinedByRequest
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(root)
            hasher.combine(path.map(ObjectIdentifier.init))
            hasher.combine(ObjectIdentifier(recordType))
            hasher.combine(operation)
            hasher.combine(anchor.map(ObjectIdentifier.init))
            hasher.combine(isRefinedByRequest)
        }
    }

    /// The walk's fail-fasts — thrown at boot, never at request time.
    package enum WalkError: Error, Hashable, CustomDebugStringConvertible {
        /// The composition graph revisits a factory already on the current
        /// descent. The emitted chain is the full descent from the walk's
        /// root down to the repeat — it starts at the root, not necessarily
        /// at the repeated factory — and always ENDS at the repeated factory.
        case cycle(factoryPath: [String])

        /// More than one requirement in the plan carries `.refinedByRequest`;
        /// the request type's axes can land on at most one tuple. The SAME
        /// marked requirement reached twice through an anchor-conflict
        /// diamond (two tuples, same record type, different anchors — see
        /// the diamond tests) also lands here: `recordTypes` then names one
        /// type twice, which reads like two declarations but is one
        /// declaration composed on two differently-anchored paths.
        case multipleRefinedByRequest(recordTypes: [String])

        /// A `dataRequirements` entry does not realize the framework's
        /// requirement kind — the walk reads requirements through an internal
        /// face, so a foreign conformer cannot be honored and could never load.
        /// Names the declaring factory and the offending type.
        case unknownRequirementKind(factory: String, requirementType: String)

        package var debugDescription: String {
            switch self {
            case .cycle(let factoryPath):
                "RecordLoadPlan.WalkError: composition cycle: \(factoryPath.joined(separator: " → "))"
            case .multipleRefinedByRequest(let recordTypes):
                "RecordLoadPlan.WalkError: multiple .refinedByRequest marks: \(recordTypes.joined(separator: ", "))"
            case .unknownRequirementKind(let factory, let requirementType):
                "RecordLoadPlan.WalkError: unknown requirement kind \(requirementType) declared by \(factory)"
            }
        }
    }

    /// Walks `rootFactory`'s composition graph — pure, no I/O — into a plan:
    /// child-relative declarations become absolute, same-anchor duplicates
    /// collapse, cycles and multiple `.refinedByRequest` marks throw.
    ///
    /// ```swift
    /// let plan = try RecordLoadPlan.walk(from: BerthsViewModel.self)
    /// ```
    ///
    /// - Throws: ``WalkError``.
    package static func walk(
        from rootFactory: any ComposableFactory.Type
    ) throws -> RecordLoadPlan {
        var walker = Walker()
        try walker.visit(rootFactory, root: .query, prefix: [])

        let marked = walker.tuples.filter(\.isRefinedByRequest)
        guard marked.count <= 1 else {
            throw WalkError.multipleRefinedByRequest(
                recordTypes: marked.map { String(describing: $0.recordType) }
            )
        }

        return .init(
            tuples: walker.tuples,
            collapseRuns: collapseRuns(over: walker.tuples),
            declarationTuples: walker.declarationTuples
        )
    }

    /// Whether `factory`'s `dataRequirements` mints the SAME declaration identities on two
    /// consecutive reads — `false` when it is a computed property (each access allocates fresh
    /// tokens), `true` for stored `static let`s. The declaration token is the exact-match key the
    /// handle→tuple lookup resolves on, so an unstable `dataRequirements` silently breaks
    /// ``tuples(matching:)``; the boot registration lints this and fails fast.
    ///
    /// (Package, not internal: the declaration-token vocabulary is FOSMVVM-internal, but the
    /// FOSMVVMVapor boot registration — a different target — needs this verdict. It reads no token
    /// value across the boundary, only this Bool.)
    package static func requirementTokensAreStable(
        for factory: any ComposableFactory.Type
    ) -> Bool {
        // Both reads MUST be held alive at once: a token is a class-instance address, so if the
        // first array were released before the second is built, ARC could recycle the same address
        // into the second's tokens — a false "stable" verdict. Keep both alive across the compare.
        let first = factory.dataRequirements
        let second = factory.dataRequirements
        defer { withExtendedLifetime((first, second)) {} }
        func tokens(_ requirements: [any DataRequirement]) -> [ObjectIdentifier] {
            requirements.compactMap { ($0 as? any DataRequirementWalkFace)?.declarationToken }
        }
        return tokens(first) == tokens(second)
    }

    /// Every plan tuple a declared requirement handle resolves to — an EXACT match on the
    /// handle's hidden declaration-site identity, never a structural heuristic.
    ///
    /// Empty means the handle never reached this plan (the caller fails fast, never serving
    /// an empty result). Exactly one is the resolved tuple. More than one means the same
    /// declaration was composed onto multiple distinct paths (the same child composed twice)
    /// — genuine ambiguity the caller must reject rather than guess.
    package func tuples(matching requirement: any DataRequirement) -> [Tuple] {
        guard let face = requirement as? any DataRequirementWalkFace else {
            return []
        }

        return (declarationTuples[face.declarationToken] ?? []).map { tuples[$0] }
    }

    private struct Walker {
        private(set) var tuples = [Tuple]()
        private(set) var declarationTuples = [ObjectIdentifier: [Int]]()
        private var seenIndex = [Tuple: Int]()
        private var descent = [(id: ObjectIdentifier, name: String)]()

        mutating func visit(
            _ factory: any ComposableFactory.Type,
            root: RootSource,
            prefix: [any Model.Type]
        ) throws {
            let factoryId = ObjectIdentifier(factory)
            let factoryName = String(describing: factory)
            guard !descent.contains(where: { $0.id == factoryId }) else {
                throw WalkError.cycle(factoryPath: descent.map(\.name) + [factoryName])
            }

            descent.append((id: factoryId, name: factoryName))
            defer { descent.removeLast() }

            for requirement in factory.dataRequirements {
                guard let face = requirement as? any DataRequirementWalkFace else {
                    throw WalkError.unknownRequirementKind(
                        factory: factoryName,
                        requirementType: String(describing: type(of: requirement))
                    )
                }
                let scope = resolve(face.rootScope, root: root, prefix: prefix)
                let path = scope.prefix + face.intermediates
                let tuple = Tuple(
                    root: scope.root,
                    path: path,
                    recordType: face.recordType,
                    operation: face.operation,
                    anchor: Self.anchor(on: path),
                    isRefinedByRequest: face.isRefinedByRequest
                )

                // Dedup keeps one tuple per identity, but every declaration that produced it
                // maps to it: two textually identical declarations collapsing to one tuple
                // both resolve — each to that single tuple, unambiguously.
                let index: Int
                if let existing = seenIndex[tuple] {
                    index = existing
                } else {
                    tuples.append(tuple)
                    index = tuples.count - 1
                    seenIndex[tuple] = index
                }
                if declarationTuples[face.declarationToken, default: []].contains(index) == false {
                    declarationTuples[face.declarationToken, default: []].append(index)
                }
            }

            for child in factory.children {
                let scope = resolve(child.rootScope, root: root, prefix: prefix)
                try visit(
                    child.factoryType,
                    root: scope.root,
                    prefix: scope.prefix + child.intermediates
                )
            }
        }

        private func resolve(
            _ rootScope: RootScope,
            root: RootSource,
            prefix: [any Model.Type]
        ) -> (root: RootSource, prefix: [any Model.Type]) {
            switch rootScope {
            case .parentRoot: (root: root, prefix: prefix)
            case .newRoot(let source): (root: source, prefix: [])
            }
        }

        /// The root's own type never anchors — guards apply to containers
        /// traversed BELOW the root, and the path holds exactly those.
        private static func anchor(on path: [any Model.Type]) -> (any Model.Type)? {
            var anchor: (any Model.Type)?
            for hop in path {
                if let container = hop as? any Container.Type,
                   container.authorityFlow == .guards {
                    anchor = hop
                }
            }

            return anchor
        }
    }

    /// anchor == nil means "anchored at the tuple's own root", so the root
    /// source is part of anchor identity — runs never span roots.
    private static func collapseRuns(over tuples: [Tuple]) -> [Range<Int>] {
        guard !tuples.isEmpty else { return [] }

        var runs = [Range<Int>]()
        var start = tuples.startIndex
        for index in tuples.indices.dropFirst() where !sameRun(tuples[index], tuples[index - 1]) {
            runs.append(start..<index)
            start = index
        }
        runs.append(start..<tuples.endIndex)

        return runs
    }

    private static func sameRun(_ lhs: Tuple, _ rhs: Tuple) -> Bool {
        lhs.root == rhs.root
            && lhs.operation == rhs.operation
            && lhs.anchor.map(ObjectIdentifier.init) == rhs.anchor.map(ObjectIdentifier.init)
    }
}
