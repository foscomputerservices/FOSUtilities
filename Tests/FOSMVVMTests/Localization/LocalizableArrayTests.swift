// LocalizableArrayTests.swift
//
// Created by David Hunt on 1/13/25
// Copyright 2025 FOS Computer Services, LLC
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
import FOSTesting
import Foundation
import Testing

@Suite("Localizable Array Tests")
struct LocalizableArrayTests: LocalizableTestCase {
    // MARK: Initialization Methods

    @Test func testInit_Localized() {
        let key = "stringArray"
        let localized = LocalizableArray<LocalizableString>.localized(key: key)
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

    @Test(arguments: [
        LocalizableArray<LocalizableString>.empty,
        // Apple Issue: https://forums.swift.org/t/fatal-error-internal-inconsistency-no-test-reporter-for-test-case-argumentids/75666
//        .constant([])
    ]) func testLocalizable_Empty(empty: LocalizableArray<LocalizableString>) throws {
        #expect(empty.localizationStatus == .localized)
        #expect(empty.isEmpty)
        #expect(try empty.localizedArray.count == 0)
        #expect(try empty.localizedString == "")
    }

    @Test func testLocalizable_Constant() throws {
        let constant = LocalizableArray<LocalizableString>.constant([
            LocalizableString.constant("string")
        ])
        #expect(constant.localizationStatus == .localized)
        #expect(!constant.isEmpty)
        #expect(try constant.localizedArray.count == 1)
        #expect(try constant.localizedArray.first == "string")
    }

    @Test func testLocalizable_Localized() throws {
        let localized = LocalizableArray<LocalizableString>.localized(key: "stringArray")
        #expect(localized.localizationStatus == .localizationPending)
        #expect(localized.isEmpty)
        #expect(throws: LocalizerError.self) {
            _ = try localized.localizedString
        }

        let decodedLoc: LocalizableArray<LocalizableString> = try localized.toJSON(encoder: encoder()).fromJSON()

        #expect(decodedLoc.localizationStatus == .localized)
        #expect(!decodedLoc.isEmpty)
        #expect(try decodedLoc.localizedArray.count == 3)
        #expect(try decodedLoc.localizedArray.first == "One")
        #expect(try decodedLoc.localizedArray.last == "Three")
    }

    // MARK: Codable Protocol

    @Test func testCodable_empty() throws {
        let empty = LocalizableArray<LocalizableString>.empty
        let decodedLoc: LocalizableArray<LocalizableString> = try empty.toJSON(encoder: encoder()).fromJSON()
        #expect(empty == decodedLoc)
    }

    @Test func testCodable_constant() throws {
        let constant = LocalizableArray<LocalizableString>.constant([.constant("My Constant String")])
        let decodedLoc: LocalizableArray<LocalizableString> = try constant.toJSON(encoder: encoder()).fromJSON()
        #expect(constant == decodedLoc)
    }

    @Test func testCodable_enLocalized() throws {
        let localized = LocalizableArray<LocalizableString>.localized(key: "stringArray")
        let decodedLoc: LocalizableArray<LocalizableString> = try localized.toJSON(encoder: encoder()).fromJSON()
        #expect(try decodedLoc.localizedArray.first == "One")
    }

    @Test func testCodable_esLocalized() throws {
        let localized = LocalizableArray<LocalizableString>.localized(key: "stringArray")
        let decodedLoc: LocalizableArray<LocalizableString> = try localized.toJSON(encoder: encoder(locale: es)).fromJSON()
        #expect(try decodedLoc.localizedArray.first == "Uno")
    }

    @Test func testCodable_localized_unknownKey() throws {
        let localized = LocalizableArray<LocalizableString>.localized(key: "lkjoipuew")
        let decodedLoc: LocalizableArray<LocalizableString> = try localized.toJSON(encoder: encoder()).fromJSON()
        #expect(try decodedLoc.localizedString == "")
    }

    // MARK: Identifiable Protocol

    @Test func testIdentifiable_empty() {
        let empty = LocalizableArray<LocalizableString>.empty
        #expect(empty.id == empty.id)
    }

    @Test func testIdentifiable_constant() {
        let constant1 = LocalizableArray<LocalizableString>.constant([.constant("foo1")])
        let constant2 = LocalizableArray<LocalizableString>.constant([.constant("foo2")])

        #expect(constant1.id == constant1.id)
        #expect(constant1.id != constant2.id)
    }

    @Test func testIdentifiable_localized() {
        let localized1 = LocalizableArray<LocalizableString>.localized(key: "foo1")
        let localized2 = LocalizableArray<LocalizableString>.localized(key: "foo2")

        #expect(localized1.id == localized1.id)
        #expect(localized1.id != localized2.id)
    }

    // MARK: Equatable Protocol

    @Test func testEquatable_empty() {
        let empty = LocalizableArray<LocalizableString>.empty
        #expect(empty == empty)
        #expect(empty != .constant([.constant("foo1")]))
    }

    @Test func testEquatable_constant() {
        let constant = LocalizableArray<LocalizableString>.constant([.constant("foo1")])
        #expect(constant == constant)
        #expect(constant != .empty)
    }

    @Test func testEquatable_localized() {
        let localized = LocalizableArray<LocalizableString>.localized(key: "stringArray")
        #expect(localized == localized)
        #expect(localized != .empty)
    }

    // MARK: Hashable Protocol

    @Test func testHashable_empty() throws {
        let empty = LocalizableArray<LocalizableString>.empty
        let const = LocalizableArray<LocalizableString>.constant([.constant("42")])

        var dict = [LocalizableArray<LocalizableString>: Int]()
        dict[empty] = 42
        dict[const] = 43

        #expect(dict[empty] == 42)
    }

    @Test func testHashable_constant() throws {
        let empty = LocalizableArray<LocalizableString>.empty
        let const = LocalizableArray<LocalizableString>.constant([.constant("42")])

        var dict = [LocalizableArray<LocalizableString>: Int]()
        dict[empty] = 42
        dict[const] = 43

        #expect(dict[const] == 43)
    }

    @Test func testHashable_localized() throws {
        let localized = LocalizableArray<LocalizableString>.localized(key: "stringArray")
        let const = LocalizableArray<LocalizableString>.constant([.constant("42")])

        var dict = [LocalizableArray<LocalizableString>: Int]()
        dict[localized] = 42
        dict[const] = 43

        #expect(dict[localized] == 42)
    }

    // MARK: Stubbable Protocol

    @Test func testStubbable_noArg() throws {
        #expect(try !(LocalizableArray<LocalizableString>.stub().localizedArray).isEmpty)
        #expect(try !(LocalizableArray<LocalizableString>.stub().localizedString).isEmpty)
    }

    @Test func testStubbable_arg() throws {
        #expect(try LocalizableArray<LocalizableString>.stub(elements: [.constant("42")]).localizedString == "42")
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
