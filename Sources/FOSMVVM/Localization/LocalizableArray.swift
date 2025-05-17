// LocalizableArray.swift
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

import FOSFoundation
import Foundation

public enum LocalizableArray<Element: Localizable>: Codable, Hashable, Localizable, Identifiable, Stubbable {
    case empty
    case constant(_ elements: [Element])
    case localized(_ ref: LocalizableRef)

    /// A short-cut overload for creating ``LocalizableArray``
    ///
    /// This overload short-cuts the following code:
    ///
    /// ```swift
    ///  LocalizableArray.localized(.value(key: key))
    /// ```
    ///
    /// - Parameter key: A location in the YAML hierarchy that contains a **String**
    public static func localized(key: String) -> Self {
        .localized(.value(key: key))
    }
}

public extension LocalizableArray {
    // MARK: Localizable Protocol

    /// Returns **true** if *localizedString* is empty **or** if the value
    /// has not yet been localized
    var isEmpty: Bool {
        (try? localizedArray.isEmpty) ?? true
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

            case .constant(let array):
                do {
                    return try array
                        .map { try $0.localizedString }
                        .joined()
                } catch let e {
                    throw LocalizerError.processUnknown(error: e)
                }

            case .localized:
                throw LocalizerError.localizationUnbound
            }
        }
    }

    var localizedArray: [String] {
        get throws {
            switch self {
            case .empty:
                return []

            case .constant(let array):
                do {
                    return try array
                        .map { try $0.localizedString }
                } catch let e {
                    throw LocalizerError.processUnknown(error: e)
                }

            case .localized:
                throw LocalizerError.localizationUnbound
            }
        }
    }

    // MARK: Codable Protocol

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedArray = try container.decode([Element].self)
        self = decodedArray.isEmpty ? .empty : .constant(decodedArray)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        let localizedArray: [Element] = switch self {
        case .empty:
            []
        case .constant(let array):
            array
        case .localized:
            try encoder.localizeArray(self) ?? []
        }
        try container.encode(localizedArray)
    }

    // MARK: Identifiable Protocol

    var id: String {
        switch self {
        case .empty:
            "_empty_"
        case .constant(let elements):
            elements.map(\.id).joined(separator: "_")
        case .localized(let key):
            key.id
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
        .stub(elements: [Element.stub()])
    }

    static func stub(elements: [Element] = []) -> Self {
        .constant(elements)
    }
}
