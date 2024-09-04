// LocalizableIntTests.swift
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

@Suite("Localizable Int Tests")
struct LocalizableIntTests: LocalizableTestCase {
    // MARK: Initialization Methods

    @Test func testInit() {
        let val = 42
        let showGroupSep = false
        let groupingSize = 42
        let locInt = LocalizableInt(value: val, showGroupingSeparator: showGroupSep, groupingSize: groupingSize)

        #expect(locInt.value == val)
        #expect(locInt.showGroupingSeparator == showGroupSep)
        #expect(locInt.groupingSize == groupingSize)
    }

    // MARK: Localizable Protocol

    @Test func testIsEmpty() {
        #expect(!LocalizableInt(value: 42).isEmpty)
    }

    @Test func testLocalizationStatus() throws {
        let locInt = LocalizableInt(value: 42)

        #expect(locInt.localizationStatus == .localizationPending)

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()
        #expect(localized.localizationStatus == .localized)
    }

    @Test func testLocalizedString() throws {
        let locInt = LocalizableInt(value: 42)

        #expect(locInt.localizationStatus == .localizationPending)

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()
        #expect(try localized.localizedString == "42")
    }

    // MARK: Codable Protocol

    @Test func testCodable_values() throws {
        let val = 42
        let showGroupSep = false
        let groupingSize = 42
        let locInt = LocalizableInt(value: val, showGroupingSeparator: showGroupSep, groupingSize: groupingSize)

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()

        #expect(localized.value == val)
        #expect(localized.showGroupingSeparator == showGroupSep)
        #expect(localized.groupingSize == groupingSize)
    }

    @Test func testCodable_correctStatus() throws {
        let locInt = LocalizableInt(value: 42)

        #expect(throws: LocalizerError.self) {
            try locInt.localizedString
        }

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()

        #expect(try !(localized.localizedString).isEmpty)
    }

    @Test func testCodable_valueLocalized() throws {
        let val = 42
        let showGroupSep = false
        let locInt = LocalizableInt(value: val, showGroupingSeparator: showGroupSep)

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()

        #expect(try localized.localizedString == "42")
    }

    @Test func testCodable_valueFormattedNoGroupSep() throws {
        let val = 123456789
        let showGroupSep = false
        let locInt = LocalizableInt(value: val, showGroupingSeparator: showGroupSep)

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()

        #expect(try localized.localizedString == "123456789")
    }

    @Test func testCodable_valueFormattedGroupSep() throws {
        let val = 123456789
        let showGroupSep = true
        let groupingSize = 4
        let locInt = LocalizableInt(value: val, showGroupingSeparator: showGroupSep, groupingSize: groupingSize)

        let localized: LocalizableInt = try locInt.toJSON(encoder: encoder()).fromJSON()

        #expect(try localized.localizedString == "1,2345,6789")
    }

    // MARK: Identifiable Protocol

    @Test func testIdentifiable() {
        let locInt1 = LocalizableInt(value: 42)
        let locInt2 = LocalizableInt(value: 43)

        #expect(locInt1.id != locInt2.id)
    }

    // MARK: Equatable Protocol

    @Test func testEquatable_beforeCoding() {
        let locInt1 = LocalizableInt(value: 42)
        let locInt2 = LocalizableInt(value: 43)

        #expect(locInt1 == locInt1)
        #expect(locInt1 != locInt2)
    }

    @Test func testEquatable_afterCoding() throws {
        let locInt1 = LocalizableInt(value: 42)
        let locInt2 = LocalizableInt(value: 43)

        let localized1: LocalizableInt = try locInt1.toJSON(encoder: encoder()).fromJSON()
        let localized2: LocalizableInt = try locInt2.toJSON(encoder: encoder()).fromJSON()

        #expect(localized1 == locInt1)
        #expect(localized1 == localized1)
        #expect(localized1 != locInt2)
        #expect(localized1 != localized2)
    }

    @Test func testEquatable_styling() {
        let locInt1 = LocalizableInt(value: 42, showGroupingSeparator: true, groupingSize: 2)
        let locInt2 = LocalizableInt(value: 42, showGroupingSeparator: false)

        // Styling is not taken into account for equatable
        #expect(locInt1 == locInt2)
    }

    // MARK: Hashable Protocol

    @Test func testHashable() {
        let locInt1 = LocalizableInt(value: 42)
        let locInt2 = LocalizableInt(value: 43)

        var dict = [LocalizableInt: String]()
        dict[locInt1] = "fred"
        dict[locInt2] = "wilma"

        #expect(dict[locInt1] == "fred")
        #expect(dict[locInt2] != "fred")
    }

    // MARK: Comparable Protocol

    @Test func testComparable_beforeCoding() {
        let locInt1 = LocalizableInt(value: 42)
        let locInt2 = LocalizableInt(value: 43)

        #expect(locInt1 < locInt2)
    }

    @Test func testComparable_afterCoding() throws {
        let locInt1 = LocalizableInt(value: 42)
        let locInt2 = LocalizableInt(value: 43)

        let localized1: LocalizableInt = try locInt1.toJSON(encoder: encoder()).fromJSON()
        let localized2: LocalizableInt = try locInt2.toJSON(encoder: encoder()).fromJSON()

        #expect(localized1 < localized2)
    }

    // MARK: Stubbable Protocol

    @Test func testStubbable_noArg() throws {
        #expect(try !(LocalizableInt.stub().localizedString).isEmpty)
    }

    @Test func testStubbable_arg() throws {
        #expect(try LocalizableInt.stub(value: 42).localizedString == "42")
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore()
    }
}
