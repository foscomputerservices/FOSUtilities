// LoadingPlanTests.swift
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

private struct Board: Model {
    var id: ModelIdType?
}

private struct Card: Model {
    var id: ModelIdType?
}

// MARK: - Trait fixture

/// A near-bare conformer: adopts the trait with an empty plan block and no children.
extension TestViewModel: ComposableFactory {}

// `LoadingPlan`'s minting behavior (implicit terminal, `via:` ordering, the named
// scopes, `.refinedByRequest`, the write operations) is asserted through the walk in
// `SealedPlanTests` — a plan's declaration data is sealed, so the contract lives at
// the plan's tuple surface, not on the plan's members.

// MARK: - ComposedChild

@Suite("ComposedChild")
struct ComposedChildTests {
    @Test(".child(_:) shares the parent's scope with no intermediate hops")
    func parentScopeDefault() {
        let child = ComposedChild.child(TestViewModel.self)

        #expect(same(child.factoryType, TestViewModel.self))
        #expect(child.scope == .parent)
        #expect(child.intermediates.isEmpty)
    }

    @Test(".child(_:via:) descends by containment — intermediates in order")
    func viaChild() {
        let child = ComposedChild.child(TestViewModel.self, via: Board.self, Card.self)

        #expect(same(child.factoryType, TestViewModel.self))
        #expect(child.scope == .parent)
        #expect(child.intermediates.count == 2)
        #expect(same(child.intermediates[0], Board.self))
        #expect(same(child.intermediates[1], Card.self))
    }

    @Test(".child(_:within:) opens the declared scope")
    func withinChild() {
        let applicationChild = ComposedChild.child(TestViewModel.self, within: .application)
        let requestChild = ComposedChild.child(TestViewModel.self, within: .request)
        let subjectChild = ComposedChild.child(TestViewModel.self, within: .subject)

        #expect(same(applicationChild.factoryType, TestViewModel.self))
        #expect(applicationChild.scope == .application)
        #expect(applicationChild.intermediates.isEmpty)
        #expect(requestChild.scope == .request)
        #expect(subjectChild.scope == .subject)
    }
}

// MARK: - ComposableFactory defaults

@Suite("ComposableFactory")
struct ComposableFactoryTests {
    @Test("An empty plan block and the children default both read back empty")
    func bareConformerDefaults() {
        #expect(TestViewModel.loadingPlans.plans.isEmpty)
        #expect(TestViewModel.children.isEmpty)
    }
}
