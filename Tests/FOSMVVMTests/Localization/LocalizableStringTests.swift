// LocalizableStringTests.swift
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
@testable import FOSMVVM
import Foundation
import Testing

@Suite("Localizable Sting Tests")
struct LocalizableStringTests: LocalizableTestCase {
    // MARK: Initialization Methods

    @Test func testInit_Localized() {
        let key = "test"
        let localized = LocalizableString.localized(key: key)
        switch localized {
        case .empty, .constant:
            #expect(Bool(false), "Expected localized")

        case .localized(let ref):
            switch ref {
            case .value(let key):
                #expect(key == key)
            case .arrayValue:
                #expect(Bool(false), "Expected .value")
            }
        }
    }

    // MARK: Localizable Protocol

    @Test func testLocalizable_Empty() throws {
        let empty = LocalizableString.empty
        #expect(empty.localizationStatus == .localized)
        #expect(empty.isEmpty)
        #expect(try empty.localizedString == "")
    }

    @Test func testLocalizable_Constant() throws {
        let constStr = "My Constant String"
        let constant = LocalizableString.constant(constStr)
        #expect(constant.localizationStatus == .localized)
        #expect(!constant.isEmpty)
        #expect(try constant.localizedString == constStr)
    }

    @Test func testLocalizable_Localized() throws {
        let localized = LocalizableString.localized(key: "test")
        #expect(localized.localizationStatus == .localizationPending)
        #expect(localized.isEmpty)
        #expect(throws: LocalizerError.self) {
            _ = try localized.localizedString
        }

        let decodedLoc: LocalizableString = try localized.toJSON(encoder: encoder()).fromJSON()

        #expect(decodedLoc.localizationStatus == .localized)
        #expect(!decodedLoc.isEmpty)
        #expect(try decodedLoc.localizedString == "Test")
    }

    // MARK: Codable Protocol

    @Test func testCodable_empty() throws {
        let empty = LocalizableString.empty
        let decodedLoc: LocalizableString = try empty.toJSON(encoder: encoder()).fromJSON()
        #expect(empty == decodedLoc)
    }

    @Test func testCodable_constant() throws {
        let constant = LocalizableString.constant("My Constant String")
        let decodedLoc: LocalizableString = try constant.toJSON(encoder: encoder()).fromJSON()
        #expect(constant == decodedLoc)
    }

    @Test func testCodable_enLocalized() throws {
        let localized = LocalizableString.localized(key: "test")
        let decodedLoc: LocalizableString = try localized.toJSON(encoder: encoder()).fromJSON()
        #expect(try decodedLoc.localizedString == "Test")
    }

    @Test func testCodable_esLocalized() throws {
        let localized = LocalizableString.localized(key: "test")
        let decodedLoc: LocalizableString = try localized.toJSON(encoder: encoder(locale: es)).fromJSON()
        #expect(try decodedLoc.localizedString == "Prueba")
    }

    @Test func testCodable_localized_unknownKey() throws {
        let localized = LocalizableString.localized(key: "lkjoipuew")
        let decodedLoc: LocalizableString = try localized.toJSON(encoder: encoder()).fromJSON()
        #expect(try decodedLoc.localizedString == "")
    }

    // MARK: Identifiable Protocol

    @Test func testIdentifiable_empty() {
        let empty = LocalizableString.empty
        #expect(empty.id == empty.id)
    }

    @Test func testIdentifiable_constant() {
        let constant1 = LocalizableString.constant("foo1")
        let constant2 = LocalizableString.constant("foo2")

        #expect(constant1.id == constant1.id)
        #expect(constant1.id != constant2.id)
    }

    @Test func testIdentifiable_localized() {
        let localized1 = LocalizableString.localized(key: "foo1")
        let localized2 = LocalizableString.localized(key: "foo2")

        #expect(localized1.id == localized1.id)
        #expect(localized1.id != localized2.id)
    }

    // MARK: Equatable Protocol

    @Test func testEquatable_empty() {
        let empty = LocalizableString.empty
        #expect(empty == empty)
        #expect(empty != .constant("foo"))
    }

    @Test func testEquatable_constant() {
        let constant = LocalizableString.constant("My Constant String")
        #expect(constant == constant)
        #expect(constant != .empty)
    }

    @Test func testEquatable_localized() {
        let localized = LocalizableString.localized(key: "test")
        #expect(localized == localized)
        #expect(localized != .empty)
    }

    // MARK: Hashable Protocol

    @Test func testHashable_empty() throws {
        let empty = LocalizableString.empty
        let const = LocalizableString.constant("42")

        var dict = [LocalizableString: Int]()
        dict[empty] = 42
        dict[const] = 43

        #expect(dict[empty] == 42)
    }

    @Test func testHashable_constant() throws {
        let empty = LocalizableString.empty
        let const = LocalizableString.constant("42")

        var dict = [LocalizableString: Int]()
        dict[empty] = 42
        dict[const] = 43

        #expect(dict[const] == 43)
    }

    @Test func testHashable_localized() throws {
        let localized = LocalizableString.localized(key: "test")
        let const = LocalizableString.constant("42")

        var dict = [LocalizableString: Int]()
        dict[localized] = 42
        dict[const] = 43

        #expect(dict[localized] == 42)
    }

    // MARK: Stubbable Protocol

    @Test func testStubbable_noArg() throws {
        #expect(try !(LocalizableString.stub().localizedString).isEmpty)
    }

    @Test func testStubbable_arg() throws {
        #expect(try LocalizableString.stub(str: "42").localizedString == "42")
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore()
    }
}
