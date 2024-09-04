// LocalizableRefTests.swift
//
// Created by David Hunt on 6/23/24
// Copyright 2024 FOS Services, LLC
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

@Suite("LocalizableRef Tests")
struct LocalizableRefTests {
    // MARK: Initialization Methods

    @Test func testInit_minimal() {
        switch LocalizableRef(for: SingleModel.self, propertyName: "property") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "SingleModel.property")
        }
    }

    @Test func testInit_multiLevel() {
        switch LocalizableRef.value(keys: "level1", "level2", "level3") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "level1.level2.level3")
        }
    }

    @Test func testInit_multiLevel_blanks() {
        switch LocalizableRef.value(keys: "level1", "", "level3") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "level1.level3")
        }
    }

    @Test func testInit_generic() {
        switch LocalizableRef(for: GenericModel<String>.self, propertyName: "property") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "GenericModel.property")
        }
    }

    @Test func testInit_parentChild() {
        switch LocalizableRef(for: OuterModel.InnerModel.self, parentType: OuterModel.self, propertyName: "property") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "OuterModel.InnerModel.property")
        }
    }

    @Test func testInit_singleDiscriminatorKey() {
        switch LocalizableRef(for: SingleModel.self, parentKeys: "property", propertyName: "title") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "SingleModel.property.title")
        }
    }

    @Test func testInit_multipleDiscriminatorKey() {
        switch LocalizableRef(for: SingleModel.self, parentKeys: "property", "title", propertyName: "expanded") {
        case .arrayValue:
            #expect(Bool(false), "Incorrect LocalizableRef.arrayValue, expected .value")
        case .value(let key):
            #expect(key == "SingleModel.property.title.expanded")
        }
    }

    @Test func testInit_discriminatorIndex() {
        switch LocalizableRef(for: SingleModel.self, propertyName: "property", index: 0) {
        case .arrayValue(let key, let index):
            #expect(key == "SingleModel.property")
            #expect(index == 0)
        case .value:
            #expect(Bool(false), "Incorrect LocalizableRef.value, expected .arrayValue")
        }
    }

    @Test func testInit_discriminatorKeyAndIndex() {
        switch LocalizableRef(for: SingleModel.self, parentKeys: "property", propertyName: "title", index: 0) {
        case .arrayValue(let key, let index):
            #expect(key == "SingleModel.property.title")
            #expect(index == 0)
        case .value:
            #expect(Bool(false), "Incorrect LocalizableRef.value, expected .arrayValue")
        }
    }

    // MARK: Identifiable Protocol

    @Test func testIdentifiable_sameType() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: SingleModel.self, propertyName: "property2")

        #expect(ref1.id == ref1.id)
        #expect(ref1.id != ref2.id)
    }

    @Test func testIdentifiable_differentTypes() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: GenericModel<String>.self, propertyName: "property")

        #expect(ref1.id != ref2.id)
    }

    @Test func testIdentifiable_differentParentTypes() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: OuterModel.InnerModel.self, parentType: OuterModel.self, propertyName: "innerProperty")

        #expect(ref1.id != ref2.id)
    }

    @Test func testIdentifiable_differentGenericSubstitutions() {
        let ref1 = LocalizableRef(for: GenericModel<String>.self, propertyName: "property")
        let ref2 = LocalizableRef(for: GenericModel<Int>.self, propertyName: "property")

        // Generic substitution does NOT have any impact on the ref
        #expect(ref1.id == ref2.id)
    }

    @Test func testIdentifiable_sameType_differentIndexes() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property", index: 0)
        let ref2 = LocalizableRef(for: SingleModel.self, propertyName: "property", index: 1)

        #expect(ref1.id != ref2.id)
    }

    // MARK: CustomStringConvertible Protocol

    @Test func testCustomStringConvertible() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property", index: 0)

        #expect(!ref1.description.isEmpty)
    }

    // MARK: Hashable Protocol

    @Test func testHashable() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: SingleModel.self, propertyName: "property2")

        var dict = [LocalizableRef: Int]()
        dict[ref1] = 42
        dict[ref2] = 43

        #expect(dict[ref1] == 42)
        #expect(dict[ref2] == 43)
    }

    // MARK: Equatable Protocol

    @Test func testEquatable_sameType() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: SingleModel.self, propertyName: "property2")

        #expect(ref1 == ref1)
        #expect(ref1 != ref2)
    }

    @Test func testEquatable_differentTypes() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: GenericModel<String>.self, propertyName: "property")

        #expect(ref1 != ref2)
    }

    @Test func testEquatable_differentParentTypes() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property")
        let ref2 = LocalizableRef(for: OuterModel.InnerModel.self, parentType: OuterModel.self, propertyName: "innerProperty")

        #expect(ref1 != ref2)
    }

    @Test func testEquatable_differentGenericSubstitutions() {
        let ref1 = LocalizableRef(for: GenericModel<String>.self, propertyName: "property")
        let ref2 = LocalizableRef(for: GenericModel<Int>.self, propertyName: "property")

        // Generic substitution does NOT have any impact on the ref
        #expect(ref1 == ref2)
    }

    @Test func testEquatable_sameType_differentIndexes() {
        let ref1 = LocalizableRef(for: SingleModel.self, propertyName: "property", index: 0)
        let ref2 = LocalizableRef(for: SingleModel.self, propertyName: "property", index: 1)

        #expect(ref1 != ref2)
    }
}

// NOTE: For these tests, the properties are here merely for show;
//   they (nor their values) DO NOT have any impact on the tests.

private struct SingleModel {
    let property = "property"
    let property2 = "property2"
}

private struct GenericModel<T> {
    let property: T
}

private struct OuterModel {
    struct InnerModel {
        let innerProperty = "innerProperty"
    }

    let outerProperty = "outerProperty"
}
