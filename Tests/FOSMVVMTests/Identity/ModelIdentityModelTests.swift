// ModelIdentityModelTests.swift
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

struct ModelIdentityModelTests {
    /// Group 1: namespace default vs override (dispatch through Model.self, not the concrete type).
    @Test func defaultNamespaceIsReflectionOfType() {
        func namespace<M: Model>(of _: M.Type) -> ModelNamespace {
            M.modelIdentityNamespace
        }
        #expect(namespace(of: TestGadget.self) == ModelNamespace(for: TestGadget.self))
    }

    @Test func overriddenNamespaceAnchorsToMarker() {
        func namespace<M: Model>(of _: M.Type) -> ModelNamespace {
            M.modelIdentityNamespace
        }
        #expect(namespace(of: TestWidget.self) == ModelNamespace(for: TestWidgetIdentity.self))
        #expect(namespace(of: TestWidget.self) != ModelNamespace(for: TestWidget.self))
    }

    /// Group 2: minted-identity equality/hash — all constructed through the PUBLIC mint path
    /// (`model.modelIdentity`), never the internal init. No `@testable`.
    @Test func mintedIdentityEqualityFollowsNamespaceAndId() throws {
        let uuid = UUID()
        let a = try TestWidget(id: uuid).modelIdentity
        let b = try TestWidget(id: uuid).modelIdentity
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        // Same UUID, different namespace ⇒ unequal (proves namespace participates; a collision can't alias).
        let c = try TestGadget(id: uuid).modelIdentity
        #expect(a != c)
    }

    /// Group 3: `identity == model` — heterogeneous filtering sugar (NOT Equatable conformance).
    @Test func identityEqualsModel() throws {
        let uuid = UUID()
        let widget = TestWidget(id: uuid)
        let identity = try widget.modelIdentity
        #expect(identity == widget) // rooted in that model's id
        #expect(!(identity == TestWidget(id: UUID()))) // different id
        #expect(!(identity == TestWidget(id: nil))) // unpersisted ⇒ false, no throw escapes
    }

    /// Group 4 (value contract): Codable round-trip preserves the identity — minted publicly, then
    /// encode→decode == original. Asserts the value contract, not the encoded shape.
    @Test func mintedIdentityCodableRoundTrips() throws {
        let original = try TestWidget(id: UUID()).modelIdentity
        let back: ModelIdentity = try original.toJSON().fromJSON()
        #expect(back == original)
    }

    /// Group 7: throwing path — unpersisted model throws, does not crash.
    @Test func modelIdentityThrowsForNilId() {
        #expect(throws: (any Error).self) {
            _ = try TestWidget(id: nil).modelIdentity
        }
    }
}
