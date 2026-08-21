// KeyEchoLocalizationStoreTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS) || os(visionOS)
import FOSFoundation
import FOSMVVM
@testable import FOSTestingUI
import Foundation
import Testing

struct KeyEchoLocalizationStoreTests {
    private let en = Locale(identifier: "en")

    @Test func missEchoesSelfIdentifyingText() {
        let store = KeyEchoLocalizationStore(wrapping: nil)

        let result = store.t("MyViewModel.title", locale: en)

        #expect(result != nil)
        #expect(!(result ?? "").isEmpty)
        #expect(result?.contains("MyViewModel.title") == true)
    }

    @Test func hitPassesThroughWrappedStore() {
        let store = KeyEchoLocalizationStore(
            wrapping: DictionaryStore(storage: [
                "en": ["MyViewModel.title": "Real Title"]
            ])
        )

        #expect(store.t("MyViewModel.title", locale: en) == "Real Title")
    }

    @Test func keyExistsStaysHonestOnMiss() {
        let store = KeyEchoLocalizationStore(
            wrapping: DictionaryStore(storage: [
                "en": ["Known.key": "Known"]
            ])
        )

        #expect(store.keyExists("Known.key", locale: en))
        #expect(!store.keyExists("Unknown.key", locale: en))
        // ... even though the same missed key still echoes as a string
        #expect(store.t("Unknown.key", locale: en)?.isEmpty == false)
    }

    @Test func explicitDefaultWinsOverEcho() {
        let store = KeyEchoLocalizationStore(wrapping: nil)

        #expect(store.t("Unknown.key", locale: en, default: "Fallback") == "Fallback")
    }

    @Test func typedMissRemainsAMiss() {
        let store = KeyEchoLocalizationStore(wrapping: nil)

        // Non-string consumers cast the result; the echoed String must not satisfy them
        #expect(store.v("Unknown.key", locale: en) as? Int == nil)
        #expect(store.v("Unknown.key", locale: en) as? [String] == nil)
    }

    @Test func localizingEncoderResolvesMissedKeyNonEmpty() throws {
        let store = KeyEchoLocalizationStore(wrapping: nil)
        let encoder = JSONEncoder.localizingEncoder(
            locale: en,
            localizationStore: store
        )

        let localized: LocalizableString = try LocalizableString
            .localized(key: "Server.onlyKey")
            .toJSON(encoder: encoder)
            .fromJSON()

        #expect(!localized.isEmpty)
        #expect(try localized.localizedString.contains("Server.onlyKey"))
    }

    @Test func localizingEncoderStillResolvesRealTranslations() throws {
        let store = KeyEchoLocalizationStore(
            wrapping: DictionaryStore(storage: [
                "en": ["Client.key": "Client Value"]
            ])
        )
        let encoder = JSONEncoder.localizingEncoder(
            locale: en,
            localizationStore: store
        )

        let localized: LocalizableString = try LocalizableString
            .localized(key: "Client.key")
            .toJSON(encoder: encoder)
            .fromJSON()

        #expect(try localized.localizedString == "Client Value")
    }
}

private struct DictionaryStore: LocalizationStore {
    /// localeIdentifier -> key -> value
    let storage: [String: [String: String]]

    func value(_ key: String, locale: Locale, default: Any?, index: Int?) -> Any? {
        storage[locale.identifier]?[key] ?? `default`
    }
}
#endif
