// YamlLocalizationStoreTests.swift
//
// Created by David Hunt on 9/4/24
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
import FOSTesting
import Foundation
import Testing

@Suite("YAML Localization Store Tests")
struct YamlLocalizationStoreTests: LocalizableTestCase {
    #if !os(macOS)
    // TODO: This crashes the Swift compiler on GitHub 🤷‍♂️
    @Test func testKeyExists() {
        #expect(locStore.keyExists("test", locale: en))
        #expect(locStore.keyExists("test", locale: es))
    }
    #endif

    @Test func testTranslate() {
        #expect(locStore.t("test", locale: en) == "Test")
        #expect(locStore.t("test", locale: es) == "Prueba")
        #expect(locStore.t("nested.inner", locale: en) == "inner")
        #expect(locStore.t("nested.inner", locale: es) == "interior")
    }

    @Test func testTranslateArray() {
        #expect(locStore.t("stringArray", locale: en, index: 2) == "Three")
        #expect(locStore.t("stringArray", locale: es, index: 0) == "Uno")
    }

    @Test func testValue() {
        #expect(locStore.v("int", locale: en) as? Int == 42)
        #expect(locStore.v("int", locale: es) as? Int == 42)
        #expect(locStore.v("double", locale: en) as? Double == 42.2)
        #expect(locStore.v("boolTrue", locale: en) as? Bool == true)
        #expect(locStore.v("boolFalse", locale: en) as? Bool == false)
    }

    @Test func testValueArray() {
        #expect(locStore.value("intArray", locale: en, default: nil, index: 1) as? Int == 2)
        #expect(locStore.value("intArray", locale: es, default: nil, index: 1) as? Int == 2)
        #expect(locStore.value("doubleArray", locale: en, default: nil, index: 1) as? Double == 2.2)
        #expect(locStore.value("boolArray", locale: en, default: nil, index: 1) as? Bool == false)
    }

    @Test func testRegionalTranslation() {
        #expect(locStore.t("carHood", locale: enUS) == "Hood")
        #expect(locStore.t("carHood", locale: enGB) == "Bonnet")
    }

    @Test func testFallbackTranslation() {
        #expect(locStore.t("test", locale: enGB) == "Test")
        #expect(locStore.t("test", locale: Locale(identifier: "en_gb")) == "Test")
    }

    @Test func testCaseSensitiveKeyTranslation() {
        #expect(locStore.t("carHood", locale: enUS) == "Hood")
        #expect(locStore.t("carhood", locale: enUS) == nil)
    }

    @Test func testDefaultTranslation() {
        #expect(locStore.t("carhood", locale: enUS, default: "fred") == "fred")
        #expect(locStore.t("stringArray", locale: en, default: "wilma", index: 999) == "wilma")
    }

    @Test func testDefaultValue() {
        #expect(locStore.v("_number", locale: en, default: -41, index: 0) as? Int == -41)
        #expect(locStore.v("intArray", locale: en, default: -42, index: 99) as? Int == -42)
    }

    @Test func testUnknownLocale() {
        #expect(locStore.t("carHood", locale: Locale(identifier: "fred")) == nil)
        #expect(locStore.v("int", locale: Locale(identifier: "fred")) == nil)
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
