// LocalizationStoreDispatchTests.swift
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

import FOSMVVM
import Foundation
import Testing

/// The index-less conveniences (`keyExists(_:locale:)`, `t()`) must dispatch their
/// protocol requirement, not re-derive the answer from `value()` — a store that
/// customizes `keyExists`/`translate` is otherwise silently bypassed.
struct LocalizationStoreDispatchTests {
    private let en = Locale(identifier: "en")

    @Test func keyExistsConvenienceDispatchesCustomWitness() {
        let store = CustomizingStore()

        // value() answers every key; the custom keyExists denies every key —
        // the convenience must report the witness's answer
        #expect(store.v("any.key", locale: en) != nil)
        #expect(!store.keyExists("any.key", locale: en))
    }

    @Test func tDispatchesCustomTranslateWitness() {
        let store = CustomizingStore()

        #expect(store.t("any.key", locale: en) == "from translate")
    }

    @Test func vDispatchesValueWitness() {
        let store = CustomizingStore()

        #expect(store.v("any.key", locale: en) as? String == "from value")
    }
}

private struct CustomizingStore: LocalizationStore {
    func keyExists(_ key: String, locale: Locale, index: Int?) -> Bool {
        false
    }

    func translate(_ key: String, locale: Locale, default: String?, index: Int?) -> String? {
        "from translate"
    }

    func value(_ key: String, locale: Locale, default: Any?, index: Int?) -> Any? {
        "from value"
    }
}
