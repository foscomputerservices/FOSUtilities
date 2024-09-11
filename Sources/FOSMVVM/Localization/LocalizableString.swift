// LocalizableString.swift
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
import Foundation

/// ``LocalizableString`` provides various mechanisms to specify and localize **String**s
///
/// The *empty* and *constant* forms allow for passing **String**s directly through the localization
/// mechanisms.  The *localized* variant is the main form of ``LocalizableString`` that allows
/// strings to be localized according to the **Locale**.
public enum LocalizableString: Codable, Hashable, Localizable, Identifiable, Stubbable {
    /// Represents an empty string
    case empty

    /// The string is fixed across all locales
    ///
    /// Constants are used to store strings that do no change when the `Locale` changes.
    /// They are very handy during testing and for `Stubbable` implementations.
    case constant(_ string: String)

    /// A reference to a localized string
    case localized(_ id: LocalizableRef)

    /// A short-cut overload for creating ``LocalizableString``
    ///
    /// This overload short-cuts the following code:
    ///
    /// ```swift
    ///  LocalizedString.localized(.value(key: key))
    /// ```
    ///
    /// - Parameter key: A location in the YAML hierarchy that contains a **String**
    public static func localized(key: String) -> Self {
        .localized(.value(key: key))
    }
}

public extension LocalizableString {
    // MARK: Localizable Protocol

    /// Returns **true** if *localizedString* is empty **or** if the value
    /// has not yet been localized
    var isEmpty: Bool {
        (try? localizedString.isEmpty) ?? true
    }

    var localizationStatus: LocalizableStatus {
        switch self {
        case .localized: .localizationPending
        case .empty, .constant: .localized
        }
    }

    /// Returns the fully localized **String**
    ///
    /// - Throws: **LocalizerError.localizationUnbound** if the localized
    ///  version of the string has not yet been realized via **Codable**
    var localizedString: String {
        get throws {
            switch self {
            case .empty:
                return ""

            case .constant(let string):
                return string

            case .localized:
                throw LocalizerError.localizationUnbound
            }
        }
    }

    // MARK: Codable Protocol

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedStr = try container.decode(String.self)
        self = decodedStr.isEmpty ? .empty : .constant(decodedStr)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        let localizedString: String = switch self {
        case .empty:
            ""
        case .constant(let string):
            string
        case .localized:
            try encoder.localizeString(self) ?? ""
        }
        try container.encode(localizedString)
    }

    // MARK: Identifiable Protocol

    var id: String {
        switch self {
        case .constant(let string): string
        case .empty: "_empty_"
        case .localized(let key): key.id
        }
    }

    // MARK: Hashable Protocol

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Equatable Protocol

    /// Returns **true** when the localization *id* strings are the same regardless of the `Locale`
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Stubbable Protocol

    static func stub() -> Self {
        .stub(str: "Hello World!")
    }

    static func stub(str: String) -> Self {
        .constant(str)
    }
}
