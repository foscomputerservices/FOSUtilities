// KeyEchoLocalizationStore.swift
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
import FOSMVVM
import Foundation

/// A ``LocalizationStore`` decorator that answers missed string lookups with
/// placeholder text derived from the lookup key
///
/// View tests exercise view behavior, not localization completeness (that is
/// ``LocalizableTestCase``'s job).  A key that has no YAML backing — a server-hosted
/// *ViewModel*'s key, for example — would otherwise resolve to an empty string, and
/// SwiftUI collapses empty-labeled elements to zero surface area, making them
/// unreachable by XCUI even when a *uiTestingIdentifier* is present.  Echoing the key
/// keeps every element tappable and makes any placeholder that leaks into a screenshot
/// self-identifying.
struct KeyEchoLocalizationStore: LocalizationStore {
    private let wrapped: LocalizationStore?

    /// - Parameter wrapped: The real store to consult first; `nil` when the test
    ///    harness has no YAML at all (every string lookup echoes)
    init(wrapping wrapped: LocalizationStore?) {
        self.wrapped = wrapped
    }

    /// Honest by design: the echo must never make a key look translated.
    func keyExists(_ key: String, locale: Locale, index: Int?) -> Bool {
        wrapped?.keyExists(key, locale: locale, index: index) ?? false
    }

    func translate(_ key: String, locale: Locale, default: String?, index: Int?) -> String? {
        value(key, locale: locale, default: `default`, index: index) as? String
    }

    /// Strings-only fallback falls out of the type system: every string lookup
    /// funnels through here via t()/translate(), while typed consumers cast the
    /// result (as? Element / as? [String]) and reject the echoed String, so their
    /// misses behave exactly as with the wrapped store.
    func value(_ key: String, locale: Locale, default: Any?, index: Int?) -> Any? {
        if let value = wrapped?.value(key, locale: locale, default: nil, index: index) {
            return value
        }
        if let `default` {
            return `default`
        }
        return "⟪\(key)⟫"
    }
}
#endif
