// DataRequirement.swift
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

/// One declared data need of a composable factory — a sealed declaration token.
///
/// Mint requirements with ``LoadRequirement``; never conform directly:
///
/// ```swift
/// static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
///
/// static var dataRequirements: [any DataRequirement] { [berths] }
/// ```
///
/// The protocol carries no members: the boot walk reads requirements through an
/// internal face. A foreign conformance is rejected at boot with an "unknown
/// requirement kind" error naming the factory and the offending type.
public protocol DataRequirement: Sendable {}

/// The hidden identity of one authored declaration site (a `static let` handle). Every mint
/// through a ``LoadRequirement`` verb allocates one; struct copies (e.g. `.refinedByRequest`)
/// carry it forward, so one declaration chain is ONE identity. Reference identity
/// (`ObjectIdentifier`) is the point: two textually identical declarations are two distinct
/// declaration sites. Never public, never on any Codable/Hashable surface.
final class RequirementDeclarationToken: Sendable {}

/// The declaration data the boot walk aggregates into a request's load plan —
/// exactly what the declaration site states, nothing more. Sealed behind the
/// public ``DataRequirement`` marker: only ``LoadRequirement`` realizes it, and
/// the walk casts to this face to read it.
protocol DataRequirementWalkFace {
    /// The identity of the authored declaration site — the exact-match key the plan's
    /// handle→tuple lookup resolves on.
    var declarationToken: ObjectIdentifier { get }

    /// The record type this requirement loads — the terminal hop of its containment path.
    var recordType: any Model.Type { get }

    /// Where the requirement roots its containment scope, as declared with `in:`.
    var rootScope: RootScope { get }

    /// The declared intermediate containment hops (`via:`), in order. Empty means one implicit hop
    /// from the root to ``recordType``.
    var intermediates: [any Model.Type] { get }

    /// The authority this requirement exercises — the ``ContainerOperation`` its verb names.
    var operation: ContainerOperation { get }

    /// Whether the request's declared refinement axes land on this requirement. At most one per plan.
    var isRefinedByRequest: Bool { get }
}

/// A typed load: records of one type, in one rooted scope, under one authority.
///
/// ```swift
/// static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
///     .refinedByRequest
/// ```
///
/// Every requirement *loads* — the verb names the authority exercised (the
/// CRUD-family ``ContainerOperation``), never the SQL. `.read` requirements
/// belong to factories; the write-family verbs (`.write` / `.create` /
/// `.delete`) belong to write requests and load the candidate set a submitted
/// target must belong to. A plain read never loads a candidate set.
public struct LoadRequirement<Record: Model>: DataRequirement, DataRequirementWalkFace {
    var declarationToken: ObjectIdentifier {
        ObjectIdentifier(token)
    }

    var recordType: any Model.Type {
        Record.self
    }

    let rootScope: RootScope
    let intermediates: [any Model.Type]
    let operation: ContainerOperation
    private(set) var isRefinedByRequest: Bool

    /// The hidden identity of THIS declaration site: minted once in the private init, carried
    /// through struct copies (`.refinedByRequest`), so `static let x = .read(...).refinedByRequest`
    /// is one identity. See RequirementDeclarationToken.
    private let token = RequirementDeclarationToken()

    /// Records this scope's grants authorize reading.
    ///
    /// ```swift
    /// .read(Berth.self, in: .parentRoot)              // one hop: implicit
    /// .read(SlipAssignment.self, in: .parentRoot,
    ///       via: Berth.self)                          // via = INTERMEDIATE hops only
    /// ```
    ///
    /// `via:` lists the *intermediate* containment hops from the root — the terminal hop to
    /// `record` is always implicit; never list it.
    public static func read<each Hop: Model>(
        _ record: Record.Type,
        in root: RootScope,
        via intermediates: repeat (each Hop).Type
    ) -> LoadRequirement<Record> {
        .init(
            rootScope: root,
            intermediates: hops(repeat each intermediates),
            operation: .readRecords,
            isRefinedByRequest: false
        )
    }

    /// Records this scope's grants authorize updating — an update request's candidate set: the
    /// submitted target must resolve to a member.
    ///
    /// ```swift
    /// static let candidates = LoadRequirement.write(Berth.self, in: .parentRoot)
    /// ```
    ///
    /// `via:` lists the *intermediate* containment hops from the root; the terminal hop to `record`
    /// is always implicit.
    public static func write<each Hop: Model>(
        _ record: Record.Type,
        in root: RootScope,
        via intermediates: repeat (each Hop).Type
    ) -> LoadRequirement<Record> {
        .init(
            rootScope: root,
            intermediates: hops(repeat each intermediates),
            operation: .writeRecords,
            isRefinedByRequest: false
        )
    }

    /// The scope a caller may create records into — a create request's candidate scope.
    ///
    /// ```swift
    /// static let candidates = LoadRequirement.create(Berth.self, in: .parentRoot)
    /// ```
    ///
    /// Restricted to zero intermediates: the root container *is* the create scope. A `via:` path can
    /// fan out to many container instances, and which one receives the new record must never be a guess.
    public static func create(
        _ record: Record.Type,
        in root: RootScope
    ) -> LoadRequirement<Record> {
        .init(
            rootScope: root,
            intermediates: [],
            operation: .createRecords,
            isRefinedByRequest: false
        )
    }

    /// Records this scope's grants authorize deleting — a delete request's candidate set.
    ///
    /// ```swift
    /// static let candidates = LoadRequirement.delete(Berth.self, in: .parentRoot)
    /// ```
    ///
    /// `via:` lists the *intermediate* containment hops from the root; the terminal hop to `record`
    /// is always implicit.
    public static func delete<each Hop: Model>(
        _ record: Record.Type,
        in root: RootScope,
        via intermediates: repeat (each Hop).Type
    ) -> LoadRequirement<Record> {
        .init(
            rootScope: root,
            intermediates: hops(repeat each intermediates),
            operation: .deleteRecords,
            isRefinedByRequest: false
        )
    }

    /// The one requirement the request's declared refinement axes land on:
    ///
    /// ```swift
    /// static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    ///     .refinedByRequest
    /// ```
    ///
    /// The axes live on the request *type* (its `Sort` associatedtype, its ``PaginatedQuery``
    /// conformance) — this modifier only picks the target they apply to. At most one requirement
    /// per plan may carry the mark.
    ///
    /// When the marked requirement is composed through a `.guards` diamond — reached on two
    /// differently-anchored paths — each anchored window is refined independently. Reach for
    /// per-relation windows when the refinement must span anchors rather than repeat within each.
    public var refinedByRequest: LoadRequirement<Record> {
        // Per-anchor windows are refined in the plan's declaration order (the walk's deterministic
        // pre-order); that ordering is a walk mechanic, not part of the observable promise above.
        var marked = self
        marked.isRefinedByRequest = true
        return marked
    }

    /// Collects a `via:` parameter pack of metatypes into the erased hop list the
    /// walk face carries — the one place heterogeneous-path erasure happens,
    /// behind the seal.
    private static func hops<each Hop: Model>(
        _ intermediates: repeat (each Hop).Type
    ) -> [any Model.Type] {
        var result = [any Model.Type]()
        for hop in repeat each intermediates {
            result.append(hop)
        }
        return result
    }

    private init(
        rootScope: RootScope,
        intermediates: [any Model.Type],
        operation: ContainerOperation,
        isRefinedByRequest: Bool
    ) {
        self.rootScope = rootScope
        self.intermediates = intermediates
        self.operation = operation
        self.isRefinedByRequest = isRefinedByRequest
    }
}
