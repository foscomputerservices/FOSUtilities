// LoadRequirementTests.swift
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

private struct Dock: Model {
    var id: ModelIdType?
}

private struct Berth: Model {
    var id: ModelIdType?
}

// MARK: - Trait fixture

/// A bare conformer: adopts the trait, declares nothing — the defaults compile.
extension TestViewModel: ComposableFactory {}

// `LoadRequirement`'s minting behavior (implicit terminal, `via:` ordering,
// `.newRoot` roots, `.refinedByRequest`, the write-family verbs) is asserted
// through the walk in `SealedRequirementTests` — the requirement's declaration
// data is sealed behind the public marker, so the contract now lives at the
// plan's tuple surface, not on the requirement members.

// MARK: - ComposedChild

@Suite("ComposedChild")
struct ComposedChildTests {
    @Test(".child(_:) shares the parent's scope with no intermediate hops")
    func parentScopeDefault() {
        let child = ComposedChild.child(TestViewModel.self)

        #expect(same(child.factoryType, TestViewModel.self))
        #expect(child.rootScope == .parentRoot)
        #expect(child.intermediates.isEmpty)
    }

    @Test(".child(_:via:) roots by containment descent — intermediates in order")
    func viaChild() {
        let child = ComposedChild.child(TestViewModel.self, via: Dock.self, Berth.self)

        #expect(same(child.factoryType, TestViewModel.self))
        #expect(child.rootScope == .parentRoot)
        #expect(child.intermediates.count == 2)
        #expect(same(child.intermediates[0], Dock.self))
        #expect(same(child.intermediates[1], Berth.self))
    }

    @Test(".child(_:rootedAt:) starts a fresh root from the declared source")
    func rootedAtChild() {
        let apexChild = ComposedChild.child(TestViewModel.self, rootedAt: .apex)
        let queryChild = ComposedChild.child(TestViewModel.self, rootedAt: .query)

        #expect(same(apexChild.factoryType, TestViewModel.self))
        #expect(apexChild.rootScope == .newRoot(.apex))
        #expect(apexChild.intermediates.isEmpty)
        #expect(queryChild.rootScope == .newRoot(.query))
    }
}

// MARK: - ComposableFactory defaults

@Suite("ComposableFactory")
struct ComposableFactoryTests {
    @Test("A bare conformer compiles and inherits the empty defaults")
    func bareConformerDefaults() {
        #expect(TestViewModel.dataRequirements.isEmpty)
        #expect(TestViewModel.children.isEmpty)
    }
}
