// SealedRequirementTests.swift
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

// Contract note (spec Testing group 10/11): `DataRequirement` is a sealed public
// marker; its declaration data is asserted THROUGH the walk's `package` tuple
// surface — the contract the FOSMVVMVapor executor binds — never by reading
// requirement members (they are internal after the seal).

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

private struct Berth: Model {
    var id: ModelIdType?
}

private struct SlipAssignment: Model {
    var id: ModelIdType?
}

private struct CrewMember: Model {
    var id: ModelIdType?
}

private struct Dock: Model {
    var id: ModelIdType?
}

// MARK: - Foreign requirement (compiles — the marker is public and memberless)

/// A conformer minted OUTSIDE ``LoadRequirement``. It satisfies the public marker
/// but not the internal walk face, so the walk cannot honor it.
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

/// Lists a foreign requirement — the walk must reject it, naming this factory
/// and the offending type.
private struct ForeignReqVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [ForeignRequirement()]
    }
}

/// One `via:` requirement — its C7 baseline tuple is `path: [Berth]`.
private struct PackViaVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(SlipAssignment.self, in: .parentRoot, via: Berth.self)]
    }
}

/// The three write-family verbs, one requirement each.
private struct WriteVerbsVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.write(Berth.self, in: .parentRoot),
            LoadRequirement.create(CrewMember.self, in: .parentRoot),
            LoadRequirement.delete(SlipAssignment.self, in: .parentRoot)
        ]
    }
}

/// Minting shapes re-pointed from the sealed representation onto the walk.
private struct ImplicitTerminalVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(Berth.self, in: .parentRoot)]
    }
}

private struct ApexRootVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(Berth.self, in: .newRoot(.apex))]
    }
}

private struct MultiHopViaVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(SlipAssignment.self, in: .parentRoot, via: Dock.self, Berth.self)]
    }
}

private struct MarkedVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest,
            LoadRequirement.read(CrewMember.self, in: .parentRoot)
        ]
    }
}

// MARK: - Handle-resolution fixtures (tuples(matching:) — declaration-token exactness)

/// A child that loads Berth at ITS OWN root — composed one hop deeper (via Dock), so the
/// walk records its tuple path absolutely as `[Dock]`. Its own handle declares no `via:`.
private struct DeepBerthVM: PlanFixture {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [berths]
    }
}

/// Parent loads Berth at the query root (path `[]`) AND composes ``DeepBerthVM`` via Dock
/// (child path `[Dock]`). Two same-typed Berth tuples in one plan — each declaration's
/// handle must resolve to exactly its OWN tuple.
private struct TwoBerthPathsVM: PlanFixture {
    static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [berths]
    }

    static var children: [ComposedChild] {
        [.child(DeepBerthVM.self, via: Dock.self)]
    }
}

/// Composes the SAME child on two distinct paths: its one Berth declaration walks to TWO
/// tuples (path `[]` and path `[Dock]`) — genuine ambiguity.
private struct TwiceComposedParentVM: PlanFixture {
    static var children: [ComposedChild] {
        [
            .child(DeepBerthVM.self),
            .child(DeepBerthVM.self, via: Dock.self)
        ]
    }
}

/// Declares Berth twice, textually identically — two declaration sites collapsing (by dedup)
/// onto ONE tuple. Each handle must still resolve, unambiguously, to that tuple.
private struct TwinDeclarationsVM: PlanFixture {
    static let portBerths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static let starboardBerths = LoadRequirement.read(Berth.self, in: .parentRoot)
    static var dataRequirements: [any DataRequirement] {
        [portBerths, starboardBerths]
    }
}

// MARK: - Non-ViewModel factory fixture (the un-pin: spec §3.4)

/// A `ServerRequestBody` that is NOT a ViewModel — a report/CLI body — adopting
/// the composable trait with one `.read` requirement. Before the un-pin this
/// could not conform: the trait required `ViewModelFactory where Self: ViewModel`.
private struct NonVMReportBody: ServerRequestBody, ComposableFactory {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(Berth.self, in: .parentRoot)]
    }
}

// MARK: - Tests

@Suite("Sealed DataRequirement")
struct SealedRequirementTests {
    @Test("A foreign DataRequirement conformer is rejected by the walk, naming the factory and the type")
    func foreignConformerIsRejectedByWalk() {
        #expect(throws: RecordLoadPlan.WalkError.unknownRequirementKind(
            factory: "ForeignReqVM",
            requirementType: "ForeignRequirement"
        )) {
            try RecordLoadPlan.walk(from: ForeignReqVM.self)
        }
    }

    @Test("The rejection message names both the factory and the offending requirement type")
    func rejectionMessageNamesFactoryAndType() {
        do {
            _ = try RecordLoadPlan.walk(from: ForeignReqVM.self)
            Issue.record("Expected the walk to reject a foreign requirement")
        } catch let error as RecordLoadPlan.WalkError {
            #expect(error.debugDescription.contains("ForeignReqVM"))
            #expect(error.debugDescription.contains("ForeignRequirement"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("pack-based via: produces the C7 baseline tuple, byte-identical")
    func packViaProducesIdenticalTuples() throws {
        let plan = try RecordLoadPlan.walk(from: PackViaVM.self)

        let expected = RecordLoadPlan.Tuple(
            root: .query,
            path: [Berth.self],
            recordType: SlipAssignment.self,
            operation: .readRecords,
            anchor: nil,
            isRefinedByRequest: false
        )

        #expect(plan.tuples == [expected])
    }

    @Test("Each write-family verb carries its ContainerOperation into the plan")
    func writeVerbsCarryTheirOperations() throws {
        let plan = try RecordLoadPlan.walk(from: WriteVerbsVM.self)

        let write = try #require(plan.tuples.first { same($0.recordType, Berth.self) })
        let create = try #require(plan.tuples.first { same($0.recordType, CrewMember.self) })
        let delete = try #require(plan.tuples.first { same($0.recordType, SlipAssignment.self) })

        #expect(write.operation == .writeRecords)
        #expect(create.operation == .createRecords)
        #expect(delete.operation == .deleteRecords)
    }

    // compile-audit: `.create` accepts no `via:` intermediates — the root
    // container IS the create scope. Uncommenting the next line must fail to
    // compile (extra argument 'via' in call).
    // _ = LoadRequirement.create(Berth.self, in: .parentRoot, via: Dock.self)

    @Test(".read with no via: is the implicit terminal hop — an empty path at the query root")
    func implicitTerminalReadWalksToEmptyPath() throws {
        let plan = try RecordLoadPlan.walk(from: ImplicitTerminalVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(same(tuple.recordType, Berth.self))
        #expect(tuple.path.isEmpty)
        #expect(tuple.root == .query)
        #expect(tuple.operation == .readRecords)
        #expect(tuple.isRefinedByRequest == false)
    }

    @Test(".newRoot(.apex) roots a fresh apex tree")
    func apexRootWalksToApexTuple() throws {
        let plan = try RecordLoadPlan.walk(from: ApexRootVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(tuple.root == .apex)
    }

    @Test("via: hops land on the tuple path in declaration order")
    func viaHopsOrderedOnPath() throws {
        let plan = try RecordLoadPlan.walk(from: MultiHopViaVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(same(tuple.recordType, SlipAssignment.self))
        #expect(tuple.path.count == 2)
        #expect(same(tuple.path[0], Dock.self))
        #expect(same(tuple.path[1], Berth.self))
    }

    @Test(".refinedByRequest marks exactly its own requirement, leaving siblings unmarked")
    func refinedByRequestMarksOnlyItsRequirement() throws {
        let plan = try RecordLoadPlan.walk(from: MarkedVM.self)

        let marked = plan.tuples.filter(\.isRefinedByRequest)
        #expect(marked.count == 1)
        #expect(try same(#require(marked.first).recordType, Berth.self))
    }

    @Test("A non-ViewModel ServerRequestBody adopts the un-pinned trait; the walk derives its plan")
    func nonViewModelBodyWalksAPlan() throws {
        let plan = try RecordLoadPlan.walk(from: NonVMReportBody.self)

        let tuple = try #require(plan.tuples.first)
        #expect(plan.tuples.count == 1)
        #expect(same(tuple.recordType, Berth.self))
        #expect(tuple.operation == .readRecords)
    }

    @Test("Each declaration's handle resolves to exactly its OWN tuple in a two-same-typed-tuple plan")
    func handlesResolveByDeclarationIdentity() throws {
        let plan = try RecordLoadPlan.walk(from: TwoBerthPathsVM.self)
        #expect(plan.tuples.count == 2)

        // The parent's bare declaration → the path-[] tuple; the child's bare declaration →
        // its prefix-substituted path-[Dock] tuple. Both textually identical bare handles —
        // resolution is by declaration identity, never by shape.
        let parentMatches = plan.tuples(matching: TwoBerthPathsVM.berths)
        #expect(parentMatches.count == 1)
        #expect(try #require(parentMatches.first).path.isEmpty)

        let childMatches = plan.tuples(matching: DeepBerthVM.berths)
        #expect(childMatches.count == 1)
        #expect(try #require(childMatches.first).path.count == 1)
        #expect(try same(#require(childMatches.first).path[0], Dock.self))
    }

    @Test("A handle that was never declared in the plan matches nothing")
    func undeclaredHandleMatchesNothing() throws {
        let plan = try RecordLoadPlan.walk(from: TwoBerthPathsVM.self)

        // A textually identical — but freshly minted — handle is a DIFFERENT declaration
        // site: it never reached this plan, so it matches nothing (the reader fails fast).
        let freshTwin = LoadRequirement.read(Berth.self, in: .parentRoot)
        #expect(plan.tuples(matching: freshTwin).isEmpty)
    }

    @Test("The same child composed onto two paths makes its one declaration ambiguous (>1 match)")
    func twiceComposedDeclarationReturnsMultipleCandidates() throws {
        let plan = try RecordLoadPlan.walk(from: TwiceComposedParentVM.self)

        // One declaration, two tuples ([] and [Dock]) — the caller must reject, never guess.
        #expect(plan.tuples(matching: DeepBerthVM.berths).count == 2)
    }

    @Test("Two identical declarations dedup to ONE tuple; each handle still resolves to it exactly")
    func twinDeclarationsShareTheDedupedTuple() throws {
        let plan = try RecordLoadPlan.walk(from: TwinDeclarationsVM.self)
        #expect(plan.tuples.count == 1)

        let port = plan.tuples(matching: TwinDeclarationsVM.portBerths)
        let starboard = plan.tuples(matching: TwinDeclarationsVM.starboardBerths)
        #expect(port.count == 1)
        #expect(starboard.count == 1)
        #expect(port.first == starboard.first)
    }
}
