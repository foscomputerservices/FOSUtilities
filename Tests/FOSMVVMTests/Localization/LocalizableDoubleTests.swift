// LocalizableDoubleTests.swift
//
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

@Suite("Localizable Double Tests")
struct LocalizableDoubleTests: LocalizableTestCase {
    // MARK: Initialization Methods

    @Test func testInit() {
        let val = 3.14159
        let showGroupSep = false
        let groupingSize = 42
        let minFracDigits = 2
        let maxFracDigits = 5
        let locDouble = LocalizableDouble(value: val, showGroupingSeparator: showGroupSep, groupingSize: groupingSize, minimumFractionDigits: minFracDigits, maximumFractionDigits: maxFracDigits)

        #expect(locDouble.value == val)
        #expect(locDouble.showGroupingSeparator == showGroupSep)
        #expect(locDouble.groupingSize == groupingSize)
        #expect(locDouble.minimumFractionDigits == minFracDigits)
        #expect(locDouble.maximumFractionDigits == maxFracDigits)
    }

    // MARK: Localizable Protocol

    @Test func testIsEmpty() {
        #expect(!LocalizableDouble(value: 3.14159).isEmpty)
    }

    @Test func testLocalizationStatus() throws {
        let locDouble = LocalizableDouble(value: 3.14159)

        #expect(locDouble.localizationStatus == .localizationPending)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()
        #expect(localized.localizationStatus == .localized)
    }

    @Test func testLocalizedString() throws {
        let locDouble = LocalizableDouble(value: 42.0)

        #expect(locDouble.localizationStatus == .localizationPending)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()
        #expect(try localized.localizedString == "42")
    }

    // MARK: Codable Protocol

    @Test func codable_values() throws {
        let val = 3.14159
        let showGroupSep = false
        let groupingSize = 42
        let minFracDigits = 2
        let maxFracDigits = 5
        let locDouble = LocalizableDouble(value: val, showGroupingSeparator: showGroupSep, groupingSize: groupingSize, minimumFractionDigits: minFracDigits, maximumFractionDigits: maxFracDigits)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        #expect(localized.value == val)
        #expect(localized.showGroupingSeparator == showGroupSep)
        #expect(localized.groupingSize == groupingSize)
        #expect(localized.minimumFractionDigits == minFracDigits)
        #expect(localized.maximumFractionDigits == maxFracDigits)
    }

    @Test func codable_correctStatus() throws {
        let locDouble = LocalizableDouble(value: 3.14159)

        #expect(throws: LocalizerError.self) {
            try locDouble.localizedString
        }

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        #expect(try !(localized.localizedString).isEmpty)
    }

    @Test func codable_valueLocalized() throws {
        let val = 42.0
        let showGroupSep = false
        let locDouble = LocalizableDouble(value: val, showGroupingSeparator: showGroupSep)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        #expect(try localized.localizedString == "42")
    }

    @Test func codable_valueFormattedNoGroupSep() throws {
        let val = 1234567.89
        let showGroupSep = false
        let locDouble = LocalizableDouble(value: val, showGroupingSeparator: showGroupSep, minimumFractionDigits: 2, maximumFractionDigits: 2)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        let str = try localized.localizedString
        // Should contain the digits without grouping separator
        #expect(str.contains("1234567"))
        #expect(str.contains("89"))
        #expect(!str.contains(","))
    }

    @Test func codable_valueFormattedGroupSep() throws {
        let val = 1234567.89
        let showGroupSep = true
        let groupingSize = 4
        let locDouble = LocalizableDouble(value: val, showGroupingSeparator: showGroupSep, groupingSize: groupingSize, minimumFractionDigits: 2, maximumFractionDigits: 2)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        let str = try localized.localizedString
        // Should contain grouping separators with custom size
        #expect(str.contains(","))
        #expect(str.contains("89"))
    }

    @Test func codable_fractionDigits() throws {
        let val = 3.14159265359
        let locDouble = LocalizableDouble(value: val, minimumFractionDigits: 0, maximumFractionDigits: 5)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        #expect(try localized.localizedString == "3.14159")
    }

    @Test func codable_minimumFractionDigits() throws {
        let val = 42.0
        let locDouble = LocalizableDouble(value: val, minimumFractionDigits: 3, maximumFractionDigits: 5)

        let localized: LocalizableDouble = try locDouble.toJSON(encoder: encoder()).fromJSON()

        #expect(try localized.localizedString == "42.000")
    }

    // MARK: Identifiable Protocol

    @Test func identifiable() {
        let locDouble1 = LocalizableDouble(value: 3.14159)
        let locDouble2 = LocalizableDouble(value: 2.71828)

        #expect(locDouble1.id != locDouble2.id)
    }

    // MARK: Equatable Protocol

    @Test func equatable_beforeCoding() {
        let locDouble1 = LocalizableDouble(value: 3.14159)
        let locDouble2 = LocalizableDouble(value: 2.71828)

        #expect(locDouble1 == locDouble1)
        #expect(locDouble1 != locDouble2)
    }

    @Test func equatable_afterCoding() throws {
        let locDouble1 = LocalizableDouble(value: 3.14159)
        let locDouble2 = LocalizableDouble(value: 2.71828)

        let localized1: LocalizableDouble = try locDouble1.toJSON(encoder: encoder()).fromJSON()
        let localized2: LocalizableDouble = try locDouble2.toJSON(encoder: encoder()).fromJSON()

        #expect(localized1 == locDouble1)
        #expect(localized1 == localized1)
        #expect(localized1 != locDouble2)
        #expect(localized1 != localized2)
    }

    @Test func equatable_styling() {
        let locDouble1 = LocalizableDouble(value: 3.14159, showGroupingSeparator: true, groupingSize: 2, minimumFractionDigits: 2, maximumFractionDigits: 5)
        let locDouble2 = LocalizableDouble(value: 3.14159, showGroupingSeparator: false)

        // Styling is not taken into account for equatable
        #expect(locDouble1 == locDouble2)
    }

    // MARK: Hashable Protocol

    @Test func hashable() {
        let locDouble1 = LocalizableDouble(value: 3.14159)
        let locDouble2 = LocalizableDouble(value: 2.71828)

        var dict = [LocalizableDouble: String]()
        dict[locDouble1] = "pi"
        dict[locDouble2] = "e"

        #expect(dict[locDouble1] == "pi")
        #expect(dict[locDouble2] != "pi")
    }

    // MARK: Comparable Protocol

    @Test func comparable_beforeCoding() {
        let locDouble1 = LocalizableDouble(value: 2.71828)
        let locDouble2 = LocalizableDouble(value: 3.14159)

        #expect(locDouble1 < locDouble2)
    }

    @Test func comparable_afterCoding() throws {
        let locDouble1 = LocalizableDouble(value: 2.71828)
        let locDouble2 = LocalizableDouble(value: 3.14159)

        let localized1: LocalizableDouble = try locDouble1.toJSON(encoder: encoder()).fromJSON()
        let localized2: LocalizableDouble = try locDouble2.toJSON(encoder: encoder()).fromJSON()

        #expect(localized1 < localized2)
    }

    // MARK: Stubbable Protocol

    @Test func stubbable_noArg() throws {
        #expect(try !(LocalizableDouble.stub().localizedString).isEmpty)
    }

    @Test func stubbable_arg() throws {
        #expect(try LocalizableDouble.stub(value: 42.0).localizedString == "42.0")
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
