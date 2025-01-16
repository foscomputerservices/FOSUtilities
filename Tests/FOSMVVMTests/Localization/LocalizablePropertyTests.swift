// LocalizablePropertyTests.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Computer Services, LLC
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
import FOSTesting
import Foundation
import Testing

@Suite("Localizable Property Tests")
struct LocalizablePropertyTests: LocalizableTestCase {
    @Test func testLocalizedString_basic() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedString.localizedString == "Some Text")
    }

    @Test func testLocalizedString_parentKey() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.title.localizedString == "Title")
        let aFieldTitle = try vm.aFieldTitle.localizedString
        #expect(try vm.title.localizedString == aFieldTitle)
        #expect(try vm.error1.localizedString == "Error #1")
        #expect(try vm.error2.localizedString == "Error #2")
    }

    @Test func testLocalizedString_index() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm1: TestViewModel = .init()
        let json = try vm1.toJSON(encoder: vmEncoder)
        let vm: TestViewModel = try json.fromJSON()

        #expect(try vm.firstPiece.localizedString == "Piece #1")
    }

    @Test func testLocalizedInt() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedInt.localizedString == "42")
    }

    @Test func testLocalizedPieces() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.pieces.localizedArray.count == 2)
        #expect(try vm.pieces.localizedArray[safe: 0] == "Piece #1")
        #expect(try vm.pieces.localizedArray[safe: 1] == "Piece #2")
    }

    @Test func testLocalizedCompoundString_noSep() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedCompoundNoSep.localizedString == "Piece #1Piece #2")
    }

    @Test func testLocalizedCompoundString_sep() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedCompoundSep.localizedString == "Piece #1*Piece #2")
    }

    @Test func localizedPropertyWrapperKeyMissing() async throws {
        // Unable to retrieve the current ViewModel for property name lookup
        let wrapper = _LocalizedProperty<TestViewModel, LocalizableString>(
            parentKey: "missing"
        )

        #expect(throws: LocalizedPropertyError.self) {
            try JSONEncoder().encode(wrapper)
        }
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

extension String {
    static var localized: String {
        ""
    }
}
