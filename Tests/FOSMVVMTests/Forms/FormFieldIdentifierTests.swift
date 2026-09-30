// FormFieldIdentifierTests.swift
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
import Testing

private struct TestCard {
    let title: String
    let summary: String
    let tags: [String]
    let author: TestAuthor
}

private struct TestBoard {
    let title: String
}

private struct TestAuthor {
    let name: String
}

private struct TestOuter {
    struct Inner {
        let title: String
    }

    let inner: Inner
}

/// The Fields pattern the generator scaffolds: the identity is minted in the protocol's own
/// extension, over `\Self`, and every conforming type answers with the same identity.
private protocol TestCardFields {
    var title: String { get }
    var tags: [String] { get }
}

private extension TestCardFields {
    static var titleField: FormField<String> {
        .init(fieldId: #fieldId(\Self.title), title: .empty, type: .text(inputType: .text))
    }

    static func tagField(_ index: Int) -> FormField<String> {
        .init(fieldId: #fieldId(\Self.tags, index: index), title: .empty, type: .text(inputType: .text))
    }
}

/// A second Fields contract carrying the same property name.
private protocol TestBoardFields {
    var title: String { get }
}

private extension TestBoardFields {
    static var titleField: FormField<String> {
        .init(fieldId: #fieldId(\Self.title), title: .empty, type: .text(inputType: .text))
    }
}

private struct TestCardBody: TestCardFields {
    let title: String
    let tags: [String]
}

private final class TestCardRow: TestCardFields {
    let title: String
    let tags: [String]

    init(title: String, tags: [String]) {
        self.title = title
        self.tags = tags
    }
}

private struct TestBoardBody: TestBoardFields {
    let title: String
}

@Suite("Field Identity")
struct FormFieldIdentifierTests {
    // MARK: The shared Fields contract

    @Test func mintsOneIdentityForAPropertyOfAFieldsProtocol() {
        #expect(TestCardBody.titleField.fieldId == TestCardRow.titleField.fieldId)
    }

    @Test func mintsOneIdentityForAnElementOfAFieldsProtocol() {
        #expect(TestCardBody.tagField(2).fieldId == TestCardRow.tagField(2).fieldId)
    }

    @Test func namesTheProtocolWhereSelfIsWritten() {
        #expect(TestCardBody.titleField.fieldId == #fieldId(\TestCardFields.title))
    }

    @Test func separatesTwoFieldsProtocolsCarryingTheSameProperty() {
        #expect(TestCardBody.titleField.fieldId != TestBoardBody.titleField.fieldId)
    }

    // MARK: The identity's scope

    @Test func mintsTheSameIdentityForTheSameProperty() {
        #expect(#fieldId(\TestCard.title) == #fieldId(\TestCard.title))
    }

    @Test func mintsDistinctIdentitiesForDistinctProperties() {
        #expect(#fieldId(\TestCard.title) != #fieldId(\TestCard.summary))
    }

    @Test func mintsDistinctIdentitiesForTheSamePropertyOfDistinctTypes() {
        #expect(#fieldId(\TestCard.title) != #fieldId(\TestBoard.title))
    }

    @Test func mintsDistinctIdentitiesForTheSameElementOfDistinctTypes() {
        #expect(#fieldId(\TestCard.tags, index: 0) != #fieldId(\TestBoard.title, index: 0))
    }

    @Test func separatesANestedPropertyFromTheOneThatCarriesIt() {
        #expect(#fieldId(\TestCard.author.name) != #fieldId(\TestCard.author))
    }

    @Test func separatesANestedTypesPropertyFromTheSamePathThroughAProperty() {
        #expect(#fieldId(\TestOuter.Inner.title) != #fieldId(\TestOuter.inner.title))
    }

    // MARK: A repeated field

    @Test func mintsTheSameIdentityForTheSameElement() {
        #expect(#fieldId(\TestCard.tags, index: 2) == #fieldId(\TestCard.tags, index: 2))
    }

    @Test func mintsDistinctIdentitiesForDistinctElements() {
        #expect(#fieldId(\TestCard.tags, index: 0) != #fieldId(\TestCard.tags, index: 1))
    }

    @Test func separatesAnElementFromTheCollection() {
        #expect(#fieldId(\TestCard.tags) != #fieldId(\TestCard.tags, index: 0))
    }

    @Test func separatesElementsOfDistinctProperties() {
        #expect(#fieldId(\TestCard.title, index: 0) != #fieldId(\TestCard.tags, index: 0))
    }

    @Test func takesTheIndexFromAnExpression() {
        let indexes = [3, 4]

        #expect(#fieldId(\TestCard.tags, index: indexes[0]) == #fieldId(\TestCard.tags, index: 3))
        #expect(#fieldId(\TestCard.tags, index: indexes[0]) != #fieldId(\TestCard.tags, index: indexes[1]))
    }

    // MARK: The value on the wire

    @Test func roundTripsThroughJSON() throws {
        let fieldId = #fieldId(\TestCard.title)
        let decoded: FormFieldIdentifier = try fieldId.toJSON().fromJSON()

        #expect(decoded == fieldId)
        #expect(decoded != #fieldId(\TestBoard.title))
    }

    @Test func roundTripsAnElementThroughJSON() throws {
        let fieldId = #fieldId(\TestCard.tags, index: 7)
        let decoded: FormFieldIdentifier = try fieldId.toJSON().fromJSON()

        #expect(decoded == fieldId)
        #expect(decoded != #fieldId(\TestCard.tags, index: 8))
    }

    @Test func roundTripsAFieldsProtocolIdentityThroughJSON() throws {
        let fieldId = TestCardBody.titleField.fieldId
        let decoded: FormFieldIdentifier = try fieldId.toJSON().fromJSON()

        #expect(decoded == TestCardRow.titleField.fieldId)
        #expect(decoded != TestBoardBody.titleField.fieldId)
    }

    @Test func hashesConsistentlyWithEquality() {
        let identities: Set<FormFieldIdentifier> = [
            #fieldId(\TestCard.title),
            #fieldId(\TestCard.title),
            #fieldId(\TestBoard.title),
            #fieldId(\TestCard.tags, index: 0),
            #fieldId(\TestCard.tags, index: 0),
            #fieldId(\TestCard.tags, index: 1)
        ]

        #expect(identities.count == 4)
    }
}
