// LocalizableCompoundValueTests.swift
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

@Suite("Localizable Compound Value Tests")
struct LocalizableCompoundValueTests: LocalizableTestCase {
    // MARK: Initialization Methods

    @Test func testInit_onePiece() throws {
        let str = LocalizableString.constant("foo")
        let compVal = LocalizableCompoundValue(pieces: [str])

        #expect(try compVal.pieces.localizedArray.count == 1)
        #expect(compVal.separator == nil)
    }

    @Test func testInit_multiplePieces() throws {
        let str1 = LocalizableString.constant("foo1")
        let str2 = LocalizableString.constant("foo2")
        let compVal = LocalizableCompoundValue(pieces: [str1, str2])

        #expect(try compVal.pieces.localizedArray.count == 2)
        #expect(compVal.separator == nil)
    }

    @Test func testInit_separator() throws {
        let str = LocalizableString.constant("foo")
        let sep = LocalizableString.constant("*")
        let compVal = LocalizableCompoundValue(pieces: [str], separator: sep)

        #expect(try compVal.pieces.localizedArray.count == 1)
        #expect(compVal.separator == sep)
    }

    // MARK: Localizable Protocol

    @Test func testLocalizable_emptyConstant() {
        let str = LocalizableString.empty
        let compVal = LocalizableCompoundValue(pieces: [str])

        #expect(compVal.isEmpty)
    }

    @Test func testLocalizable_nonEmptyConstant() {
        let str = LocalizableString.constant("foo")
        let compVal = LocalizableCompoundValue(pieces: [str])

        #expect(!compVal.isEmpty)
    }

    @Test func testLocalizable_empty_notLocalized() {
        let str = LocalizableString.localized(key: "test")
        let compVal = LocalizableCompoundValue(pieces: [str])

        // Not localized is empty
        #expect(compVal.isEmpty)
    }

    @Test func testLocalizable_empty_localized() throws {
        let str = LocalizableString.localized(key: "test")
        let compVal = LocalizableCompoundValue(pieces: [str])

        let decodedLoc: LocalizableCompoundValue<LocalizableString> = try compVal.toJSON(encoder: encoder()).fromJSON()

        #expect(!decodedLoc.isEmpty)
    }

    @Test func testLocalizable_status_pending() throws {
        let str = LocalizableString.localized(key: "test")
        let compVal = LocalizableCompoundValue(pieces: [str])

        #expect(compVal.localizationStatus == .localized)
    }

    @Test func testLocalizable_status_localized() throws {
        let str = LocalizableString.localized(key: "test")
        let compVal = LocalizableCompoundValue(pieces: [str])

        let decodedLoc: LocalizableCompoundValue<LocalizableString> = try compVal.toJSON(encoder: encoder()).fromJSON()

        #expect(decodedLoc.localizationStatus == .localized)
    }

    @Test func testLocalizable_localizedString_constant_single() throws {
        let str = LocalizableString.constant("foo")
        let compVal = LocalizableCompoundValue(pieces: [str])

        #expect(try compVal.localizedString == "foo")
    }

    @Test func testLocalizable_localizedString_constant_compound() throws {
        let str1 = LocalizableString.constant("foo")
        let str2 = LocalizableString.constant("bar")
        let sep = LocalizableString.constant(".")
        let compVal = LocalizableCompoundValue(pieces: [str1, str2], separator: sep)

        #expect(try compVal.localizedString == "foo.bar")
    }

    @Test func testLocalizable_localizedString_pending() throws {
        let str = LocalizableString.localized(key: "test")
        let compVal = LocalizableCompoundValue(pieces: [str])

        #expect(throws: LocalizerError.self) {
            try compVal.localizedString
        }
    }

    @Test func testLocalizable_localizedString_localized() throws {
        let str1 = LocalizableString.localized(key: "test")
        let str2 = LocalizableString.localized(key: "carHood")
        let sep = LocalizableString.localized(key: "separator")
        let compVal = LocalizableCompoundValue(pieces: [str1, str2], separator: sep)

        let decodedLoc: LocalizableCompoundValue<LocalizableString> =
            try compVal
                .toJSON(encoder: encoder(locale: enGB))
                .fromJSON()

        #expect(try decodedLoc.localizedString == "Test.Bonnet")
    }

    // MARK: Codable Protocol

    @Test func testCodable() throws {
        let str = LocalizableString.localized(key: "test")
        let compVal = LocalizableCompoundValue(pieces: [str])

        let decodedLoc: LocalizableCompoundValue<LocalizableString> =
            try compVal
                .toJSON(encoder: encoder())
                .fromJSON()

        #expect(decodedLoc.localizationStatus == .localized)
        #expect(try decodedLoc.localizedString == "Test")
    }

    // MARK: Collection Extension

    @Test func testJoined() throws {
        let str1 = LocalizableString.localized(key: "test")
        let str2 = LocalizableString.localized(key: "carHood")
        let sep = LocalizableString.localized(key: "separator")

        let compVal = [str1, str2].joined(separator: sep)

        let decodedLoc: LocalizableCompoundValue<LocalizableString> =
            try compVal
                .toJSON(encoder: encoder(locale: enGB))
                .fromJSON()

        #expect(try decodedLoc.localizedString == "Test.Bonnet")
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore()
    }
}
