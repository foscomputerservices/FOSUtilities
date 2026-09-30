// LoadingPlan.swift
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

/// One clause of a factory's plan: the models of one type, within one scope, that the subject
/// may `operation`. Mint one on the model type and read it back by the same handle:
///
/// ```swift
/// static let workspaces = Workspace.loadingPlan(.read, within: .subject)
/// static let boards     = Board.loadingPlan(.read, within: .subject, via: Workspace.self)
///     .refinedByRequest                              // the request's filter, sort, window land here
/// static var loadingPlans: LoadingPlans { workspaces; boards }
///
/// // projection: no fetching here, the plan already ran
/// let boards = try context.records(boards)
/// ```
///
/// The verb names the authority the subject must hold, never a fetch: a plan declares a
/// result set, the executor loads it once per request, and the grants decide what is in it.
/// A create names the container it creates into with ``FOSMVVM/Model/creationPlan(within:)``.
public struct LoadingPlan<Model: FOSMVVM.Model>: LoadingPlanWalkFace, Sendable {
    package var declarationToken: ObjectIdentifier {
        ObjectIdentifier(token)
    }

    package var recordType: any FOSMVVM.Model.Type {
        Model.self
    }

    package let scope: ContainmentScope
    package let intermediates: [any FOSMVVM.Model.Type]
    package let operation: ContainerOperation
    package private(set) var isRefinedByRequest: Bool

    /// The hidden identity of THIS declaration site: minted once in the private init, carried
    /// through struct copies (`.refinedByRequest`), so `static let x = T.loadingPlan(...).refinedByRequest`
    /// is one identity. See PlanDeclarationToken.
    private let token = PlanDeclarationToken()

    fileprivate init(
        scope: ContainmentScope,
        intermediates: [any FOSMVVM.Model.Type],
        operation: ContainerOperation,
        isRefinedByRequest: Bool
    ) {
        self.scope = scope
        self.intermediates = intermediates
        self.operation = operation
        self.isRefinedByRequest = isRefinedByRequest
    }

    /// The same plan, marked as the one the request's filter, sort, and window bind to.
    /// At most one plan per request carries the mark.
    ///
    /// ```swift
    /// static let cards = Card.loadingPlan(.read, within: .request).refinedByRequest
    /// ```
    public var refinedByRequest: LoadingPlan<Model> {
        // Per-anchor windows are refined in the plan's declaration order (the walk's deterministic
        // pre-order); that ordering is a walk mechanic, not part of the observable promise above.
        var marked = self
        marked.isRefinedByRequest = true
        return marked
    }
}

public extension Model {
    /// The models of this type, within `scope`, that the subject may `operation` — one clause of
    /// a factory's plan:
    ///
    /// ```swift
    /// static let workspaces = Workspace.loadingPlan(.read, within: .subject)
    /// static let boards     = Board.loadingPlan(.read, within: .subject, via: Workspace.self)
    /// static let targets    = Board.loadingPlan(.archive, within: .subject)   // an archive request's candidates
    /// ```
    ///
    /// `via:` lists the *intermediate* containment hops from the scope's container; the last hop
    /// to this type is always implicit. `.anyOperation` is not a plan and fails at boot.
    static func loadingPlan(
        _ operation: ModelOperation,
        within scope: ContainmentScope,
        via intermediates: any FOSMVVM.Model.Type...
    ) -> LoadingPlan<Self> {
        .init(
            scope: scope,
            intermediates: intermediates,
            operation: operation.containerOperation,
            isRefinedByRequest: false
        )
    }

    /// The one container a create request creates this type into — the write's candidate scope:
    ///
    /// ```swift
    /// static let candidates = Card.creationPlan(within: .request)          // into the Board the client named
    /// static let candidates = Workspace.creationPlan(within: .application) // create at the top
    /// ```
    ///
    /// No `via:`: the scope's container *is* the create scope, and a path could fan out to many.
    /// Never `.subject`: a create names a container, not a set the subject holds — it fails at boot.
    static func creationPlan(within scope: ContainmentScope) -> LoadingPlan<Self> {
        .init(
            scope: scope,
            intermediates: [],
            operation: .createRecords,
            isRefinedByRequest: false
        )
    }
}

/// A factory's plan: its clauses, declared in a builder block so no type erasure appears at
/// the site.
///
/// ```swift
/// static var loadingPlans: LoadingPlans {
///     workspaces
///     boards
/// }
/// ```
public struct LoadingPlans: Sendable {
    /// One clause, opaque outside the framework.
    public struct Element: Sendable {
        package let face: any LoadingPlanWalkFace
    }

    package let plans: [any LoadingPlanWalkFace]

    package init(plans: [any LoadingPlanWalkFace]) {
        self.plans = plans
    }
}

/// Builds a ``LoadingPlans`` from the clauses listed in a factory's `loadingPlans` block.
@resultBuilder
public enum LoadingPlansBuilder {
    public static func buildExpression(_ plan: LoadingPlan<some FOSMVVM.Model>) -> LoadingPlans.Element {
        .init(face: plan)
    }

    public static func buildBlock(_ parts: LoadingPlans.Element...) -> LoadingPlans {
        .init(plans: parts.map(\.face))
    }
}

/// The identity of one authored declaration site (a `static let` handle). Every mint allocates
/// one; struct copies (e.g. `.refinedByRequest`) carry it forward, so one declaration chain is
/// ONE identity. Reference identity (`ObjectIdentifier`) is the point: two textually identical
/// declarations are two distinct declaration sites. Never public, never on any Codable/Hashable surface.
final class PlanDeclarationToken: Sendable {}

/// The declaration data the boot walk aggregates into a request's plan — exactly what the
/// declaration site states, nothing more. `package`, not public: the walk (this module) and the
/// executor (FOSMVVMVapor) read it; an app only ever holds a ``LoadingPlan``.
package protocol LoadingPlanWalkFace: Sendable {
    /// The identity of the authored declaration site — the exact-match key the plan's
    /// handle→tuple lookup resolves on.
    var declarationToken: ObjectIdentifier { get }
    /// The model type this plan loads — the terminal hop of its containment path.
    var recordType: any FOSMVVM.Model.Type { get }
    /// Where the plan is scoped, as declared with `within:`.
    var scope: ContainmentScope { get }
    /// The declared intermediate containment hops (`via:`), in order. Empty means one implicit hop
    /// from the scope's container to ``recordType``.
    var intermediates: [any FOSMVVM.Model.Type] { get }
    /// The member authority this plan exercises — the ``ContainerOperation`` a container's grant
    /// must extend; a named model must hold its ``ModelOperation`` twin.
    var operation: ContainerOperation { get }
    /// Whether the request's declared refinement axes land on this plan. At most one per plan.
    var isRefinedByRequest: Bool { get }
}

// MARK: - Former spellings, one release

/// The former marker behind `dataRequirements`, honored for one release. Declare ``LoadingPlans``.
@available(*, deprecated, message: "declare loadingPlans")
public protocol DataRequirement: Sendable {}

/// The former name of ``LoadingPlan``.
@available(*, deprecated, renamed: "LoadingPlan")
public typealias LoadRequirement<Record: FOSMVVM.Model> = LoadingPlan<Record>

/// A plan still lands in a former `dataRequirements` list.
@available(*, deprecated, message: "declare loadingPlans")
extension LoadingPlan: DataRequirement {}

@available(*, deprecated, message: "mint plans on the model type: T.loadingPlan(_:within:via:) / T.creationPlan(within:)")
public extension LoadingPlan {
    static func read<each Hop: FOSMVVM.Model>(_: Model.Type, in root: RootScope, via intermediates: repeat (each Hop).Type) -> LoadingPlan<Model> {
        .init(scope: root.containmentScope, intermediates: hops(repeat each intermediates), operation: .readRecords, isRefinedByRequest: false)
    }

    static func write<each Hop: FOSMVVM.Model>(_: Model.Type, in root: RootScope, via intermediates: repeat (each Hop).Type) -> LoadingPlan<Model> {
        .init(scope: root.containmentScope, intermediates: hops(repeat each intermediates), operation: .writeRecords, isRefinedByRequest: false)
    }

    static func create(_: Model.Type, in root: RootScope) -> LoadingPlan<Model> {
        .init(scope: root.containmentScope, intermediates: [], operation: .createRecords, isRefinedByRequest: false)
    }

    static func archive<each Hop: FOSMVVM.Model>(_: Model.Type, in root: RootScope, via intermediates: repeat (each Hop).Type) -> LoadingPlan<Model> {
        .init(scope: root.containmentScope, intermediates: hops(repeat each intermediates), operation: .archiveRecords, isRefinedByRequest: false)
    }

    static func destroy<each Hop: FOSMVVM.Model>(_: Model.Type, in root: RootScope, via intermediates: repeat (each Hop).Type) -> LoadingPlan<Model> {
        .init(scope: root.containmentScope, intermediates: hops(repeat each intermediates), operation: .destroyRecords, isRefinedByRequest: false)
    }

    private static func hops<each Hop: FOSMVVM.Model>(_ intermediates: repeat (each Hop).Type) -> [any FOSMVVM.Model.Type] {
        var result = [any FOSMVVM.Model.Type]()
        for hop in repeat each intermediates {
            result.append(hop)
        }
        return result
    }
}
