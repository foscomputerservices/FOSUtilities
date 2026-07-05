// RecordLoadPlanTests.swift
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

// Contract note (spec Testing, shared group): declarations are made via the PUBLIC
// trait surface; assertions land at the plan's `package` surface — which IS the
// contract its consumer, the FOSMVVMVapor executor, binds.

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

private struct Harbor: Model {
    var id: ModelIdType?
}

/// An `.inherits` container — traversing it never re-anchors.
private struct Dock: Container {
    var id: ModelIdType?
}

private struct Berth: Model {
    var id: ModelIdType?
}

private struct SlipAssignment: Model {
    var id: ModelIdType?
}

private struct CrewMember: Model {
    var id: ModelIdType?
}

private struct Paycheck: Model {
    var id: ModelIdType?
}

private struct HarborBanner: Model {
    var id: ModelIdType?
}

/// A `.guards` container — traversing it re-anchors its subtree.
private struct PersonnelFolder: Container {
    var id: ModelIdType?
    static var authorityFlow: AuthorityFlow {
        .guards
    }
}

/// A second `.guards` container, for the LAST-guard-wins pin.
private struct RestrictedVault: Container {
    var id: ModelIdType?
    static var authorityFlow: AuthorityFlow {
        .guards
    }
}

private struct PersonnelFile: Model {
    var id: ModelIdType?
}

private struct PersonnelNote: Model {
    var id: ModelIdType?
}

private struct VaultFile: Model {
    var id: ModelIdType?
}

// MARK: - Factory fixture plumbing

/// Minimal `ViewModelFactoryContext` for trait conformers that never project.
private struct PlanFixtureContext: ViewModelFactoryContext {
    var appVersion: SystemVersion {
        .init(major: 1, minor: 0)
    }
}

/// A plain-struct `ComposableFactory` conformer: only the trait's
/// declaration members vary per fixture; everything else defaults here.
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

// MARK: - Factory fixtures: substitution graph (spec test 1)

/// Root: own requirements (implicit terminal + `via:`) and all three child placements.
private struct HarborPageVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.read(Berth.self, in: .parentRoot),
            LoadRequirement.read(SlipAssignment.self, in: .parentRoot, via: Berth.self)
        ]
    }

    static var children: [ComposedChild] {
        [
            .child(CrewRosterVM.self),
            .child(BerthBoardVM.self, via: Dock.self),
            .child(BannerVM.self, rootedAt: .apex)
        ]
    }
}

private struct CrewRosterVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(CrewMember.self, in: .parentRoot)]
    }
}

private struct BerthBoardVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.read(Berth.self, in: .parentRoot),
            LoadRequirement.read(Paycheck.self, in: .newRoot(.query))
        ]
    }
}

private struct BannerVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(HarborBanner.self, in: .parentRoot)]
    }
}

// MARK: - Factory fixtures: diamonds (spec test 2)

private struct SharedLeafVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(CrewMember.self, in: .parentRoot)]
    }
}

/// Same child composed under two parents at the SAME scope — one security question.
private struct SameAnchorDiamondVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(PortSideVM.self), .child(StarboardSideVM.self)]
    }
}

private struct PortSideVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(SharedLeafVM.self)]
    }
}

private struct StarboardSideVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(SharedLeafVM.self)]
    }
}

/// Same child composed twice — one path through a `.guards` container, one not:
/// two different security questions, never merged.
private struct AnchorConflictDiamondVM: PlanFixture {
    static var children: [ComposedChild] {
        [
            .child(SharedLeafVM.self, via: PersonnelFolder.self),
            .child(SharedLeafVM.self)
        ]
    }
}

// MARK: - Factory fixtures: cycle (spec test 3)

private struct CycleAVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(CycleBVM.self)]
    }
}

private struct CycleBVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(CycleAVM.self)]
    }
}

// MARK: - Factory fixtures: anchor resolution (spec test 4)

/// Descends via an `.inherits` container, then a `.guards` container.
private struct GuardedDescentVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(PersonnelDeskVM.self, via: Dock.self, PersonnelFolder.self)]
    }
}

private struct PersonnelDeskVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.read(PersonnelFile.self, in: .parentRoot),
            LoadRequirement.read(PersonnelNote.self, in: .parentRoot, via: PersonnelFile.self)
        ]
    }
}

/// Two `.guards` containers on one path — the LAST one traversed anchors.
private struct DoubleGuardVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(VaultDeskVM.self, via: PersonnelFolder.self, RestrictedVault.self)]
    }
}

private struct VaultDeskVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(VaultFile.self, in: .parentRoot)]
    }
}

// MARK: - Factory fixtures: .refinedByRequest (spec test 5)

private struct SingleMarkVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest,
            LoadRequirement.read(CrewMember.self, in: .parentRoot)
        ]
    }
}

private struct DoubleMarkVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(Berth.self, in: .parentRoot).refinedByRequest]
    }

    static var children: [ComposedChild] {
        [.child(MarkedLeafVM.self)]
    }
}

private struct MarkedLeafVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(CrewMember.self, in: .parentRoot).refinedByRequest]
    }
}

/// The same MARKED leaf under two parents at the same scope — the diamond dedups
/// to ONE marked tuple; no false multi-mark rejection.
private struct MarkedDiamondVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(MarkedPortVM.self), .child(MarkedStarboardVM.self)]
    }
}

private struct MarkedPortVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(MarkedLeafVM.self)]
    }
}

private struct MarkedStarboardVM: PlanFixture {
    static var children: [ComposedChild] {
        [.child(MarkedLeafVM.self)]
    }
}

// MARK: - Factory fixtures: collapse boundaries (spec test 6)

/// Tuple order: two `.query`-rooted unanchored reads, an `.apex`-rooted read, then a
/// `.guards`-anchored read — three collapse runs.
private struct CollapseVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [
            LoadRequirement.read(Berth.self, in: .parentRoot),
            LoadRequirement.read(CrewMember.self, in: .parentRoot),
            LoadRequirement.read(HarborBanner.self, in: .newRoot(.apex))
        ]
    }

    static var children: [ComposedChild] {
        [.child(PersonnelDeskLiteVM.self, via: PersonnelFolder.self)]
    }
}

private struct PersonnelDeskLiteVM: PlanFixture {
    static var dataRequirements: [any DataRequirement] {
        [LoadRequirement.read(PersonnelFile.self, in: .parentRoot)]
    }
}

// MARK: - Tests

@Suite("RecordLoadPlan walk: substitution")
struct RecordLoadPlanSubstitutionTests {
    @Test("The walk substitutes all three placements — child-relative paths become absolute")
    func substitutionAcrossPlacements() throws {
        let plan = try RecordLoadPlan.walk(from: HarborPageVM.self)

        let expected: [RecordLoadPlan.Tuple] = [
            // Root factory's own requirements — the request root, absolute path as declared
            .init(root: .query, path: [], recordType: Berth.self, operation: .readRecords, anchor: nil, isRefinedByRequest: false),
            .init(root: .query, path: [Berth.self], recordType: SlipAssignment.self, operation: .readRecords, anchor: nil, isRefinedByRequest: false),
            // Parent-scope child: inherits the parent's root and prefix
            .init(root: .query, path: [], recordType: CrewMember.self, operation: .readRecords, anchor: nil, isRefinedByRequest: false),
            // via: child — the child's parent-relative declaration becomes absolute
            .init(root: .query, path: [Dock.self], recordType: Berth.self, operation: .readRecords, anchor: nil, isRefinedByRequest: false),
            // .newRoot(.query) requirement under a via: child — a fresh root resets the prefix
            .init(root: .query, path: [], recordType: Paycheck.self, operation: .readRecords, anchor: nil, isRefinedByRequest: false),
            // .newRoot(.apex) child — a fresh tree in the forest
            .init(root: .apex, path: [], recordType: HarborBanner.self, operation: .readRecords, anchor: nil, isRefinedByRequest: false)
        ]

        #expect(plan.tuples == expected)
    }

    @Test("The terminal hop stays implicit — the record type never appears in its own path")
    func terminalHopImplicit() throws {
        let plan = try RecordLoadPlan.walk(from: HarborPageVM.self)

        for tuple in plan.tuples {
            #expect(!tuple.path.contains(where: { same($0, tuple.recordType) }))
        }
    }
}

@Suite("RecordLoadPlan walk: diamonds")
struct RecordLoadPlanDiamondTests {
    @Test("A same-anchor diamond dedups to one tuple — one security question, asked once")
    func sameAnchorDiamondDedups() throws {
        let plan = try RecordLoadPlan.walk(from: SameAnchorDiamondVM.self)

        #expect(plan.tuples.count == 1)
        let tuple = try #require(plan.tuples.first)
        #expect(same(tuple.recordType, CrewMember.self))
        #expect(tuple.anchor == nil)
    }

    @Test("An anchor-conflict diamond keeps TWO tuples — different anchors never merge")
    func anchorConflictDiamondNeverMerges() throws {
        let plan = try RecordLoadPlan.walk(from: AnchorConflictDiamondVM.self)

        #expect(plan.tuples.count == 2)

        let guarded = try #require(plan.tuples.first { $0.anchor != nil })
        let unguarded = try #require(plan.tuples.first { $0.anchor == nil })

        #expect(same(guarded.recordType, CrewMember.self))
        #expect(same(unguarded.recordType, CrewMember.self))
        #expect(try same(#require(guarded.anchor), PersonnelFolder.self))
        #expect(guarded.path.count == 1)
        #expect(unguarded.path.isEmpty)
    }
}

@Suite("RecordLoadPlan walk: fail-fasts")
struct RecordLoadPlanFailFastTests {
    @Test("A composition cycle is rejected with a typed error naming the cycle")
    func cycleRejected() {
        #expect(throws: RecordLoadPlan.WalkError.cycle(
            factoryPath: ["CycleAVM", "CycleBVM", "CycleAVM"]
        )) {
            try RecordLoadPlan.walk(from: CycleAVM.self)
        }
    }

    @Test("Two .refinedByRequest marks in one plan are rejected, naming both record types")
    func multipleRefinedByRequestRejected() {
        #expect(throws: RecordLoadPlan.WalkError.multipleRefinedByRequest(
            recordTypes: ["Berth", "CrewMember"]
        )) {
            try RecordLoadPlan.walk(from: DoubleMarkVM.self)
        }
    }

    @Test("A marked tuple deduped through a same-anchor diamond is ONE mark — no false rejection")
    func dedupedMarkIsNotAMultiMark() throws {
        let plan = try RecordLoadPlan.walk(from: MarkedDiamondVM.self)

        #expect(plan.tuples.count == 1)
        #expect(plan.tuples.filter(\.isRefinedByRequest).count == 1)
    }
}

@Suite("RecordLoadPlan walk: anchors")
struct RecordLoadPlanAnchorTests {
    @Test("A .guards container mid-path re-anchors its whole subtree; .inherits never does")
    func guardsMidPathReanchors() throws {
        let plan = try RecordLoadPlan.walk(from: GuardedDescentVM.self)

        #expect(plan.tuples.count == 2)

        let file = try #require(plan.tuples.first { same($0.recordType, PersonnelFile.self) })
        #expect(file.path.count == 2)
        #expect(try same(#require(file.anchor), PersonnelFolder.self))

        // Below the guard, deeper hops stay anchored at the guard
        let note = try #require(plan.tuples.first { same($0.recordType, PersonnelNote.self) })
        #expect(note.path.count == 3)
        #expect(try same(#require(note.anchor), PersonnelFolder.self))
    }

    @Test("Two .guards containers on one path — the LAST one traversed anchors")
    func lastGuardWins() throws {
        let plan = try RecordLoadPlan.walk(from: DoubleGuardVM.self)

        let tuple = try #require(plan.tuples.first)
        #expect(try same(#require(tuple.anchor), RestrictedVault.self))
    }

    @Test("No .guards below the root — the anchor is nil: the tuple's own root anchors")
    func rootAnchorsWhenNoGuards() throws {
        let plan = try RecordLoadPlan.walk(from: HarborPageVM.self)

        #expect(plan.tuples.allSatisfy { $0.anchor == nil })
    }
}

@Suite("RecordLoadPlan walk: refinement + determinism")
struct RecordLoadPlanDeterminismTests {
    @Test("Exactly one .refinedByRequest mark survives into the plan")
    func singleMarkCarries() throws {
        let plan = try RecordLoadPlan.walk(from: SingleMarkVM.self)

        let marked = plan.tuples.filter(\.isRefinedByRequest)
        #expect(marked.count == 1)
        #expect(try same(#require(marked.first).recordType, Berth.self))
    }

    @Test("The walk is deterministic — two walks of the same root produce equal plans")
    func determinism() throws {
        let first = try RecordLoadPlan.walk(from: HarborPageVM.self)
        let second = try RecordLoadPlan.walk(from: HarborPageVM.self)

        #expect(first == second)

        let guardedFirst = try RecordLoadPlan.walk(from: GuardedDescentVM.self)
        let guardedSecond = try RecordLoadPlan.walk(from: GuardedDescentVM.self)

        #expect(guardedFirst == guardedSecond)
    }
}

@Suite("RecordLoadPlan walk: collapse boundaries")
struct RecordLoadPlanCollapseTests {
    @Test("Consecutive same-root+anchor+operation tuples form one collapse run; boundaries split at root, anchor, or operation changes")
    func collapseRunsAsData() throws {
        let plan = try RecordLoadPlan.walk(from: CollapseVM.self)

        #expect(plan.tuples.count == 4)
        #expect(plan.collapseRuns == [0..<2, 2..<3, 3..<4])
    }

    @Test("A uniform plan is one run; runs tile the tuple indices exactly")
    func runsTileTheTuples() throws {
        let uniform = try RecordLoadPlan.walk(from: SingleMarkVM.self)
        #expect(uniform.collapseRuns == [0..<2])

        let plan = try RecordLoadPlan.walk(from: HarborPageVM.self)
        let covered = plan.collapseRuns.flatMap { Array($0) }
        #expect(covered == Array(plan.tuples.indices))
    }
}
