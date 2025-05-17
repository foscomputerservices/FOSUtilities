// LocalizationStore.swift
//
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

import Foundation

/// ``LocalizationStore`` defines a mechanism for retrieving localized values from a
/// pre-populated store
///
/// The general concept of the ``LocalizationStore`` is that it represents a dictionary of dictionaries.
/// The primary dictionary is keyed by **Locale** and each value of the primary dictionary is a dictionary
/// containing key/value pairs storing the values for that **Locale**.
///
/// While this API can be used directly, this API is considered a low-level API that is used by other
/// higher-level mechanisms.  Thus, the focus is on simplicity and speed.
///
/// Shortened overloads of *translate()* and *value()* (*t()* and *v()*, respectively) are provided that
/// provide default values for the *default* and *index* parameters that are typically nil.
///
/// > Implementers of ``LocalizationStore`` need only implement the *value()* function
/// > as there are default implementations for the other functions provided.  Of course, these
/// > default implementations may be replaced if the store's implementation would be
/// > more optimal.
///
/// > It is by design that there is no default **Locale** at this level.  Such a concept is
/// > only interesting to the application and user, but not to the underlying store itself.
/// > Thus, APIs closer to the user's View-Model should employ 'default' if it makes
/// > sense at that level.
public protocol LocalizationStore: Sendable {
    /// Provides information on whether a translation is available for  given key in a given locale
    ///
    /// - Parameters:
    ///   - key: The translation key to look up
    ///   - locale: The **Locale** context in which to resolve *key*
    ///   - index: If `storage[locale][key]` is an **Array**, the index in that array to return
    /// - Returns: **true** if the key is known in the given *locale*
    func keyExists(_ key: String, locale: Locale, index: Int?) -> Bool

    /// Look up a translation
    ///
    /// - Parameters:
    ///   - key: The key to look up in the locale's store
    ///   - locale: The **Locale** context in which to resolve *key*
    ///   - default: A default value to return if *key* cannot be found in *locale*, or if *locale* does not exist
    ///   - index: If `storage[locale][key]` is an **Array**, the index in that array to return
    /// - Returns: A **String** if the lookup succeeds or *default* if the lookup fails
    func translate(_ key: String, locale: Locale, default: String?, index: Int?) -> String?

    /// Look up a value
    ///
    /// - Parameters:
    ///   - key: The key to look up in the locale's store
    ///   - locale: The **Locale** context in which to resolve *key*
    ///   - default: A default value to return if *key* cannot be found in *locale*, or if *locale* does not exist
    ///   - index: If `storage[locale][key]` is an **Array**, the index in that array to return
    /// - Returns: An **Any** value if the lookup succeeds or *default* if the lookup fails
    func value(_ key: String, locale: Locale, default: Any?, index: Int?) -> Any?
}

public extension LocalizationStore {
    func keyExists(_ key: String, locale: Locale, index: Int? = nil) -> Bool {
        value(key, locale: locale, default: nil, index: index) != nil
    }

    func translate(_ key: String, locale: Locale, default: String?, index: Int?) -> String? {
        value(key, locale: locale, default: `default`, index: index) as? String
    }

    func t(_ key: String, locale: Locale, default: String? = nil, index: Int? = nil) -> String? {
        value(key, locale: locale, default: `default`, index: index) as? String
    }

    func v(_ key: String, locale: Locale, default: Any? = nil, index: Int? = nil) -> Any? {
        value(key, locale: locale, default: `default`, index: index)
    }
}
