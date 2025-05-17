// JSONEncoderTests.swift
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

@Suite("JSON Encoder Error Tests")
struct JSONEncoderTests: LocalizableTestCase {
    // NOTE: These methods are internal methods to the JSONEncoder implementation.
    //   The tests here validate that the internal implementation is working as expected.
    //   These tests are not testing public APIs.

    // MARK: Simple Tests

    @Test func localizeString() async throws {
        let encoder = JSONEncoder.localizingEncoder(locale: Self.en, localizationStore: locStore)
        let localizableString = LocalizableString.localized(.value(key: "test"))
        let string: LocalizableString = try localizableString.toJSON(encoder: encoder).fromJSON()

        #expect(try string.localizedString == "Test")
    }

    @Test func localizeArray() async throws {
        let encoder = JSONEncoder.localizingEncoder(locale: Self.en, localizationStore: locStore)
        let localizableArray = LocalizableArray<LocalizableString>.localized(.value(key: "stringArray"))
        let array: LocalizableArray<LocalizableString> = try localizableArray.toJSON(encoder: encoder).fromJSON()

        #expect(!array.isEmpty)
        #expect(try array.localizedArray[0] == "One")
    }

    // MARK: Error Tests

    @Test func localizeStringLocaleMissing() async throws {
        let string = LocalizableString.localized(.value(key: "missing"))

        #expect(throws: LocalizerError.self) {
            try JSONEncoder().encode(string)
        }
    }

    @Test func localizeArrayLocaleMissing() async throws {
        let array = LocalizableArray<LocalizableString>.localized(.value(key: "missing"))

        #expect(throws: LocalizerError.self) {
            try JSONEncoder().encode(array)
        }
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
