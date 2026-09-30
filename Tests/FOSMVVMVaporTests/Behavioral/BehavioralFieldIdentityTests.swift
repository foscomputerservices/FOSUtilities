// BehavioralFieldIdentityTests.swift
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

/// Design 1.14 / OQ12 / OQ29 / DocC 4.10. The contract is identity, never the string: two mints
/// of the same key path (and index) are equal, a different property or index is a different
/// identity, and the value survives a `Codable` round trip.
private struct BehavioralIdentityFields {
    let title: String
    let detail: String
    let tags: [String]
}

private struct BehavioralOtherFields {
    let title: String
}

/// The Fields shape: the identity is minted once, in the protocol's own extension, over `\Self`.
private protocol BehavioralSharedFields {
    var title: String { get }
}

private extension BehavioralSharedFields {
    static var titleFieldId: FormFieldIdentifier {
        #fieldId(\Self.title)
    }
}

private struct BehavioralIdentityBody: BehavioralSharedFields {
    let title: String
}

private final class BehavioralIdentityRow: BehavioralSharedFields {
    let title: String

    init(title: String) {
        self.title = title
    }
}

@Suite("Behavioral: #fieldId identity")
struct BehavioralFieldIdentityTests {
    @Test("Two mints of the same key path are equal")
    func sameKeyPathIsEqual() {
        #expect(#fieldId(\BehavioralIdentityFields.title) == #fieldId(\BehavioralIdentityFields.title))
    }

    @Test("Two properties of one type are different identities")
    func differentPropertiesDiffer() {
        #expect(#fieldId(\BehavioralIdentityFields.title) != #fieldId(\BehavioralIdentityFields.detail))
    }

    @Test("An identity survives a Codable round trip")
    func identityRoundTrips() throws {
        let identity = #fieldId(\BehavioralIdentityFields.title)

        let roundTripped: FormFieldIdentifier = try identity.toJSON().fromJSON()

        #expect(roundTripped == identity)
    }

    @Test("Two mints of the same key path and index are equal")
    func sameIndexIsEqual() {
        #expect(
            #fieldId(\BehavioralIdentityFields.tags, index: 2) ==
                #fieldId(\BehavioralIdentityFields.tags, index: 2)
        )
    }

    @Test("Two indices of one collection are different identities")
    func differentIndicesDiffer() {
        #expect(
            #fieldId(\BehavioralIdentityFields.tags, index: 1) !=
                #fieldId(\BehavioralIdentityFields.tags, index: 2)
        )
    }

    /// negative space: DocC 4.10 offers both spellings for one property — "the collection as a
    /// whole" and "element i" — so the indexed mint must not collide with the plain one.
    @Test("The collection as a whole is a different identity from any element")
    func collectionDiffersFromItsElements() {
        #expect(
            #fieldId(\BehavioralIdentityFields.tags) !=
                #fieldId(\BehavioralIdentityFields.tags, index: 0)
        )
    }

    @Test("An indexed identity survives a Codable round trip")
    func indexedIdentityRoundTrips() throws {
        let identity = #fieldId(\BehavioralIdentityFields.tags, index: 3)

        let roundTripped: FormFieldIdentifier = try identity.toJSON().fromJSON()

        #expect(roundTripped == identity)
    }

    /// negative space: "a model has one set of field identities" — one set per model, not one set
    /// shared by every model. OQ30 scopes the identity by the type the key path names, so a form
    /// showing fields of two models cannot route one model's message onto the other's field.
    @Test("The same property name on two types is a different identity")
    func samePropertyNameOnTwoTypesIsADifferentIdentity() {
        #expect(#fieldId(\BehavioralIdentityFields.title) != #fieldId(\BehavioralOtherFields.title))
    }

    /// The shared `Fields` contract: the one line in the protocol's own extension mints the one
    /// identity for every adopter, and an explicit protocol root names the same field.
    @Test("A Fields protocol's own mint is one identity for every adopter")
    func fieldsProtocolMintIsSharedByAdopters() {
        #expect(BehavioralIdentityBody.titleFieldId == BehavioralIdentityRow.titleFieldId)
        #expect(BehavioralIdentityBody.titleFieldId == #fieldId(\BehavioralSharedFields.title))
    }
}
