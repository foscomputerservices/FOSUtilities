// SealedPlanTests.swift
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

// Contract note (spec Testing group 10/11): a ``LoadingPlan``'s declaration data is
// sealed; it is asserted THROUGH the walk's `package` tuple surface — the contract the
// FOSMVVMVapor executor binds — never by reading plan members.

import FOSFoundation
import FOSMVVM
import Foundation
import Testing

/// `#expect`'s operator rewriting can't type-check `==` on existential metatypes;
/// plain `Any.Type` equality outside the macro can.
private func same(_ lhs: Any.Type, _ rhs: Any.Type) -> Bool {
    lhs == rhs
}

// MARK: - Model fixtures

private struct Card: Model {
    var id: ModelIdType?
}

private struct Assignment: Model {
    var id: ModelIdType?
}

private struct Member: Model {
    var id: ModelIdType?
}

private struct Board: Model {
    var id: ModelIdType?
}

// MARK: - Foreign requirement (compiles — the former marker is public and memberless)

/// A conformer minted OUTSIDE ``LoadingPlan``. It satisfies the former public marker but is
/// not a plan, so it can only be listed in the deprecated `dataRequirements` — the
/// `loadingPlans` builder accepts nothing but a ``LoadingPlan``.
@available(*, deprecated, message: "exercises the former dataRequirements list")
private struct ForeignRequirement: DataRequirement {}

// MARK: - Factory fixture plumbing

private struct PlanFixtureContext: ViewModelFactoryContext {
    var appVersion: SystemVersion {
        .init(major: 1, minor: 0)
    }
}

private protocol PlanFixture: ComposableFactory {
    init()
}

private extension PlanFixture {
    var vmId: ViewModelId {
        ViewModelId()
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func model(context: PlanFixtureContext) async throws -> Self {
        .init()
    }
}

// MARK: - Factory fixtures

/// Lists a foreign requirement alongside a genuine plan through the deprecated
/// `dataRequirements` — the foreign entry is not a plan, so the walk drops it.
@available(*, deprecated, message: "exercises the former dataRequirements list")
private struct ForeignReqVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .parent)

    static var dataRequirements: [any DataRequirement] {
        [ForeignRequirement(), cards]
    }
}

/// One `via:` plan — its C7 baseline tuple is `path: [Card]`.
private struct PackViaVM: PlanFixture {
    static let assignments = Assignment.loadingPlan(.read, within: .parent, via: Card.self)

    static var loadingPlans: LoadingPlans {
        assignments
    }
}

/// The three write operations, one plan each.
private struct WriteVerbsVM: PlanFixture {
    static let cards = Card.loadingPlan(.write, within: .parent)
    static let members = Member.creationPlan(within: .parent)
    static let assignments = Assignment.loadingPlan(.archive, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
        members
        assignments
    }
}

/// Minting shapes re-pointed from the sealed representation onto the walk.
private struct ImplicitTerminalVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private struct ApplicationScopeVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .application)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private struct SubjectScopeVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .subject)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

private struct MultiHopViaVM: PlanFixture {
    static let assignments = Assignment.loadingPlan(.read, within: .parent, via: Board.self, Card.self)

    static var loadingPlans: LoadingPlans {
        assignments
    }
}

private struct MarkedVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .parent).refinedByRequest
    static let members = Member.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
        members
    }
}

// MARK: - Handle-resolution fixtures (tuples(matching:) — declaration-token exactness)

/// A child that loads Card within ITS OWN parent scope — composed one hop deeper (via Board),
/// so the walk records its tuple path absolutely as `[Board]`. Its own handle declares no `via:`.
private struct DeepCardVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

/// Parent loads Card within the request scope (path `[]`) AND composes ``DeepCardVM`` via Board
/// (child path `[Board]`). Two same-typed Card tuples in one plan — each declaration's
/// handle must resolve to exactly its OWN tuple.
private struct TwoCardPathsVM: PlanFixture {
    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }

    static var children: [ComposedChild] {
        [.child(DeepCardVM.self, via: Board.self)]
    }
}

/// Composes the SAME child on two distinct paths: its one Card declaration walks to TWO
/// tuples (path `[]` and path `[Board]`) — genuine ambiguity.
private struct TwiceComposedParentVM: PlanFixture {
    static var children: [ComposedChild] {
        [
            .child(DeepCardVM.self),
            .child(DeepCardVM.self, via: Board.self)
        ]
    }
}

/// Declares Card twice, textually identically — two declaration sites collapsing (by dedup)
/// onto ONE tuple. Each handle must still resolve, unambiguously, to that tuple.
private struct TwinDeclarationsVM: PlanFixture {
    static let firstCards = Card.loadingPlan(.read, within: .parent)
    static let secondCards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        firstCards
        secondCards
    }
}

// MARK: - Non-ViewModel factory fixture (the un-pin: spec §3.4)

/// A `ServerRequestBody` that is NOT a ViewModel — a report/CLI body — adopting
/// the composable trait with one `.read` plan. Before the un-pin this
/// could not conform: the trait required `ViewModelFactory where Self: ViewModel`.
private struct NonVMReportBody: ServerRequestBody, ComposableFactory {
    static let cards = Card.loadingPlan(.read, within: .parent)

    static var loadingPlans: LoadingPlans {
        cards
    }
}

// MARK: - Tests

@Suite("Sealed LoadingPlan")
struct SealedPlanTests {
    @available(*, deprecated, message: "exercises the former dataRequirements list")
    @Test("A foreign DataRequirement in the former dataRequirements list is dropped from the plan")
    func foreignConformerIsDroppedFromThePlan() throws {
        let plan = try RecordLoadPlan.walk(from: ForeignReqVM.self)

        // Only the genuine plan survives: the foreign entry is not a LoadingPlan, so the walk
        // has no declaration to derive a tuple from — it never loads, and never throws either.
        #expect(plan.tuples.count == 1)
        #expect(try same(#require(plan.tuples.first).recordType, Card.self))
        #expect(plan.tuples(matching: ForeignReqVM.cards).count == 1)
    }

    @Test("pack-based via: produces the C7 baseline tuple, byte-identical")
    func packViaProducesIdenticalTuples() throws {
        let plan = try RecordLoadPlan.walk(from: PackViaVM.self)

        let expected = RecordLoadPlan.Tuple(
            root: .request,
            path: [Card.self],
            recordType: Assignment.self,
            operation: .readRecords,
            anchor: nil,
            isRefinedByRequest: false
        )

        #expect(plan.tuples == [expected])
    }

    @Test("Each write operation carries its ContainerOperation into the plan")
    func writeVerbsCarryTheirOperations() throws {
        let plan = try RecordLoadPlan.walk(from: WriteVerbsVM.self)

        let write = try #require(plan.tuples.first { same($0.recordType, Card.self) })
        let create = try #require(plan.tuples.first { same($0.recordType, Member.self) })
        let archive = try #require(plan.tuples.first { same($0.recordType, Assignment.self) })

        #expect(write.operation == .writeRecords)
        #expect(create.operation == .createRecords)
        #expect(archive.operation == .archiveRecords)
    }

    // compile-audit: `creationPlan(within:)` accepts no `via:` intermediates — the scope's
    // container IS the create scope. Uncommenting the next line must fail to compile
    // (extra argument 'via' in call).
    // _ = Card.creationPlan(within: .parent, via: Board.self)

    @Test(".read with no via: is the implicit terminal hop — an empty path in the request scope")
    func implicitTerminalReadWalksToEmptyPath() throws {
        let plan = try RecordLoadPlan.walk(from: ImplicitTerminalVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(same(tuple.recordType, Card.self))
        #expect(tuple.path.isEmpty)
        #expect(tuple.root == .request)
        #expect(tuple.operation == .readRecords)
        #expect(tuple.isRefinedByRequest == false)
    }

    @Test("within: .application opens the application scope")
    func applicationScopeWalksToApplicationTuple() throws {
        let plan = try RecordLoadPlan.walk(from: ApplicationScopeVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(tuple.root == .application)
    }

    @Test("within: .subject opens the subject scope")
    func subjectScopeWalksToSubjectTuple() throws {
        let plan = try RecordLoadPlan.walk(from: SubjectScopeVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(tuple.root == .subject)
    }

    @Test("via: hops land on the tuple path in declaration order")
    func viaHopsOrderedOnPath() throws {
        let plan = try RecordLoadPlan.walk(from: MultiHopViaVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(same(tuple.recordType, Assignment.self))
        #expect(tuple.path.count == 2)
        #expect(same(tuple.path[0], Board.self))
        #expect(same(tuple.path[1], Card.self))
    }

    @Test(".refinedByRequest marks exactly its own plan, leaving siblings unmarked")
    func refinedByRequestMarksOnlyItsPlan() throws {
        let plan = try RecordLoadPlan.walk(from: MarkedVM.self)

        let marked = plan.tuples.filter(\.isRefinedByRequest)
        #expect(marked.count == 1)
        #expect(try same(#require(marked.first).recordType, Card.self))
    }

    @Test("A non-ViewModel ServerRequestBody adopts the un-pinned trait; the walk derives its plan")
    func nonViewModelBodyWalksAPlan() throws {
        let plan = try RecordLoadPlan.walk(from: NonVMReportBody.self)

        let tuple = try #require(plan.tuples.first)
        #expect(plan.tuples.count == 1)
        #expect(same(tuple.recordType, Card.self))
        #expect(tuple.operation == .readRecords)
    }

    @Test("Each declaration's handle resolves to exactly its OWN tuple in a two-same-typed-tuple plan")
    func handlesResolveByDeclarationIdentity() throws {
        let plan = try RecordLoadPlan.walk(from: TwoCardPathsVM.self)
        #expect(plan.tuples.count == 2)

        // The parent's bare declaration → the path-[] tuple; the child's bare declaration →
        // its prefix-substituted path-[Board] tuple. Both textually identical bare handles —
        // resolution is by declaration identity, never by shape.
        let parentMatches = plan.tuples(matching: TwoCardPathsVM.cards)
        #expect(parentMatches.count == 1)
        #expect(try #require(parentMatches.first).path.isEmpty)

        let childMatches = plan.tuples(matching: DeepCardVM.cards)
        #expect(childMatches.count == 1)
        #expect(try #require(childMatches.first).path.count == 1)
        #expect(try same(#require(childMatches.first).path[0], Board.self))
    }

    @Test("A handle that was never declared in the plan matches nothing")
    func undeclaredHandleMatchesNothing() throws {
        let plan = try RecordLoadPlan.walk(from: TwoCardPathsVM.self)

        // A textually identical — but freshly minted — handle is a DIFFERENT declaration
        // site: it never reached this plan, so it matches nothing (the reader fails fast).
        let freshTwin = Card.loadingPlan(.read, within: .parent)
        #expect(plan.tuples(matching: freshTwin).isEmpty)
    }

    @Test("The same child composed onto two paths makes its one declaration ambiguous (>1 match)")
    func twiceComposedDeclarationReturnsMultipleCandidates() throws {
        let plan = try RecordLoadPlan.walk(from: TwiceComposedParentVM.self)

        // One declaration, two tuples ([] and [Board]) — the caller must reject, never guess.
        #expect(plan.tuples(matching: DeepCardVM.cards).count == 2)
    }

    @Test("Two identical declarations dedup to ONE tuple; each handle still resolves to it exactly")
    func twinDeclarationsShareTheDedupedTuple() throws {
        let plan = try RecordLoadPlan.walk(from: TwinDeclarationsVM.self)
        #expect(plan.tuples.count == 1)

        let first = plan.tuples(matching: TwinDeclarationsVM.firstCards)
        let second = plan.tuples(matching: TwinDeclarationsVM.secondCards)
        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first.first == second.first)
    }
}
