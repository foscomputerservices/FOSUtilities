// LocalizableDateTests.swift
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

@Suite("Localizable Date Tests")
struct LocalizableDateTests: LocalizableTestCase {
    // Fixed date for consistent testing: 2024-07-15 14:30:00 UTC
    let testDate = Date(timeIntervalSince1970: 1721054400)

    // MARK: - Default Style Tests

    @Test func defaultStyle_usesMediumDate() throws {
        // When no style is specified, default is medium dateStyle
        let locDate = LocalizableDate(value: testDate)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        // Default style is medium - exact format varies by locale, but should contain month name
        #expect(encoded.localizationStatus == .localized)
        let result = try encoded.localizedString
        // Medium format typically includes abbreviated month like "Jul 15, 2024"
        #expect(result.contains("Jul") || result.contains("2024"))
    }

    // MARK: - Date Style Variation Tests

    @Test func dateStyle_short() throws {
        let locDate = LocalizableDate(value: testDate, dateStyle: .short)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: enUS, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Short style is typically numeric like "7/15/24"
        #expect(result.contains("7") && result.contains("15"))
    }

    @Test func dateStyle_long() throws {
        let locDate = LocalizableDate(value: testDate, dateStyle: .long)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Long style includes full month name like "July 15, 2024"
        #expect(result.contains("July"))
    }

    @Test func dateStyle_full() throws {
        let locDate = LocalizableDate(value: testDate, dateStyle: .full)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Full style includes day of week like "Monday, July 15, 2024"
        #expect(result.contains("Monday") || result.contains("July"))
    }

    // MARK: - Time Style Tests

    @Test func timeStyle_short() throws {
        let locDate = LocalizableDate(value: testDate, timeStyle: .short)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: enUS, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Short time style shows hours:minutes
        #expect(result.contains(":"))
    }

    @Test func timeStyle_medium() throws {
        let locDate = LocalizableDate(value: testDate, timeStyle: .medium)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: enUS, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Medium time includes seconds
        #expect(result.contains(":"))
    }

    // MARK: - Combined Style Tests

    @Test func combinedStyles_dateAndTime() throws {
        let locDate = LocalizableDate(value: testDate, dateStyle: .medium, timeStyle: .short)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: enUS, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Should contain both date and time elements
        #expect(result.contains("Jul") || result.contains("2024"))
        #expect(result.contains(":")) // Time component
    }

    // MARK: - Custom Format Tests

    @Test func customFormat_isoStyle() throws {
        let locDate = LocalizableDate(value: testDate, dateFormat: "yyyy-MM-dd")
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        #expect(result == "2024-07-15")
    }

    @Test func customFormat_dateTimeStyle() throws {
        let locDate = LocalizableDate(value: testDate, dateFormat: "yyyy-MM-dd HH:mm")
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Note: exact hour depends on encoder's timezone setting
        #expect(result.starts(with: "2024-07-15"))
    }

    @Test func customFormat_overridesStyles() throws {
        // When dateFormat is set, it should override dateStyle/timeStyle
        let locDate = LocalizableDate(
            value: testDate,
            dateStyle: .full, // Should be ignored
            timeStyle: .full, // Should be ignored
            dateFormat: "dd/MM/yy"
        )
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        #expect(result == "15/07/24")
    }

    // MARK: - Locale Variation Tests

    @Test func locale_germanFormat() throws {
        let de = Locale(identifier: "de_DE")
        let locDate = LocalizableDate(value: testDate, dateStyle: .medium)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: de, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // German format typically uses "15. Juli 2024" or similar
        #expect(result.contains("Juli") || result.contains("15"))
    }

    @Test func locale_japaneseFormat() throws {
        let ja = Locale(identifier: "ja_JP")
        let locDate = LocalizableDate(value: testDate, dateStyle: .medium)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: ja, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        let result = try encoded.localizedString
        // Japanese format uses year/month/day order
        #expect(result.contains("2024"))
    }

    // MARK: - Codable Round-Trip Tests

    @Test func codable_preservesValue() throws {
        let locDate = LocalizableDate(value: testDate, dateStyle: .long)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        // The value should be preserved through encoding
        #expect(encoded.value == testDate)
    }

    @Test func codable_preservesStyles() throws {
        let locDate = LocalizableDate(value: testDate, dateStyle: .short, timeStyle: .medium)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        #expect(encoded.dateStyle == .short)
        #expect(encoded.timeStyle == .medium)
    }

    @Test func codable_preservesCustomFormat() throws {
        let locDate = LocalizableDate(value: testDate, dateFormat: "EEEE, MMMM d")
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        #expect(encoded.dateFormat == "EEEE, MMMM d")
    }

    // MARK: - Localization Status Tests

    @Test func localizationStatus_pendingBeforeEncode() throws {
        let locDate = LocalizableDate(value: testDate)
        #expect(locDate.localizationStatus == .localizationPending)
    }

    @Test func localizationStatus_localizedAfterEncode() throws {
        let locDate = LocalizableDate(value: testDate)
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let encoded: LocalizableDate = try locDate.toJSON(encoder: vmEncoder).fromJSON()

        #expect(encoded.localizationStatus == .localized)
    }

    @Test func localizedString_throwsWhenPending() throws {
        let locDate = LocalizableDate(value: testDate)

        #expect(throws: LocalizerError.self) {
            _ = try locDate.localizedString
        }
    }

    // MARK: - Comparable Tests

    @Test func comparable_earlierDateIsLess() throws {
        let earlier = LocalizableDate(value: Date(timeIntervalSince1970: 1000))
        let later = LocalizableDate(value: Date(timeIntervalSince1970: 2000))

        #expect(earlier < later)
        #expect(!(later < earlier))
    }

    @Test func comparable_equalDates() throws {
        let date1 = LocalizableDate(value: testDate)
        let date2 = LocalizableDate(value: testDate)

        #expect(date1 == date2)
        #expect(!(date1 < date2))
        #expect(!(date2 < date1))
    }

    // MARK: - Hashable Tests

    @Test func hashable_sameDatesSameHash() throws {
        let date1 = LocalizableDate(value: testDate)
        let date2 = LocalizableDate(value: testDate)

        #expect(date1.hashValue == date2.hashValue)
    }

    @Test func hashable_canBeUsedInSet() throws {
        let date1 = LocalizableDate(value: testDate)
        let date2 = LocalizableDate(value: testDate)
        let date3 = LocalizableDate(value: Date(timeIntervalSince1970: 0))

        var set = Set<LocalizableDate>()
        set.insert(date1)
        set.insert(date2) // Duplicate, should not increase count
        set.insert(date3)

        #expect(set.count == 2)
    }

    // MARK: - isEmpty Tests

    @Test func isEmpty_alwaysFalse() throws {
        let locDate = LocalizableDate(value: testDate)
        #expect(!locDate.isEmpty)

        let epoch = LocalizableDate(value: Date(timeIntervalSince1970: 0))
        #expect(!epoch.isEmpty)
    }

    // MARK: - Stubbable Tests

    @Test func stubbable_createsValidStub() throws {
        let stub = LocalizableDate.stub()

        // Stub should be localized already (has localizedString)
        #expect(stub.localizationStatus == .localized)
        #expect(!stub.isEmpty)
    }

    @Test func stubbable_withValue() throws {
        let specificDate = Date(timeIntervalSince1970: 12345)
        let stub = LocalizableDate.stub(value: specificDate)

        #expect(stub.value == specificDate)
        #expect(stub.localizationStatus == .localized)
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
