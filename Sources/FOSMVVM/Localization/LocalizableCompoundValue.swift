// LocalizableCompoundValue.swift
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

/// A `LocalizableCompoundValue` provides a mechanism to combine multiple
/// ``Localizable`` instances int a single ``Localizable``
///
/// ``LocalizableCompoundValue`` works much the same as **Collection**'s
/// *joined()* operator.  That is, multiple ``Localizable``-conforming instances can
/// be combined together into a single ``Localizable`` and each piece can be optionally
/// separated by a given ``LocalizableString``.
///
/// The combining of the pieces is performed according to the **Locale**'s semantics.
/// So right-to-left and left-to-right orderings are automatically taken into consideration;
/// there is no need to re-order the pieces.
public struct LocalizableCompoundValue<Value: Localizable>: Localizable {
    public let pieces: LocalizableArray<Value>
    public let separator: LocalizableString?

    // MARK: Initialization Methods

    /// Initializes the `LocalizableCompoundValue`
    ///
    /// > ``init(pieces:separator:)`` is publicly available, but
    /// > it is generally better to use the **Collection**.joined() operator instead.
    ///
    /// - Parameters:
    ///   - pieces: The `Localizable` values to combine together
    ///   - separator: An optional separator that will be placed
    ///   between each of the localized items
    public init(pieces: [Value], separator: LocalizableString? = nil) {
        self.init(
            pieces: LocalizableArray.constant(pieces),
            separator: separator
        )
    }

    /// Initializes the `LocalizableCompoundValue`
    ///
    /// > ``LocalizableCompoundValue``.init() is publicly available, but
    /// > it is generally better to use the **Collection**.joined() operator instead.
    ///
    /// - Parameters:
    ///   - pieces: The `Localizable` values to combine together
    ///   - separator: An optional separator that will be placed
    ///   between each of the localized items
    public init(pieces: LocalizableArray<Value>, separator: LocalizableString? = nil) {
        self.pieces = pieces
        self.separator = separator
    }
}

public extension LocalizableCompoundValue {
    // MARK: Localizable Protocol

    var isEmpty: Bool {
        pieces.isEmpty || ((try? localizedString.isEmpty) ?? true)
    }

    var localizationStatus: LocalizableStatus {
        let fullyLocalized = pieces.localizationStatus == .localized
            && (separator?.localizationStatus ?? .localized) == .localized

        return fullyLocalized ? .localized : .localizationPending
    }

    var localizedString: String {
        get throws {
            try pieces.localizedArray
                .joined(separator: separator?.localizedString ?? "")
        }
    }

    // MARK: Codable Protocol

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pieces = try container.decode(LocalizableArray<Value>.self, forKey: .pieces)
        self.separator = try container.decodeIfPresent(LocalizableString.self, forKey: .separator)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pieces, forKey: .pieces)
        try container.encodeIfPresent(separator, forKey: .separator)
    }

    // MARK: Identifiable Protocol

    var id: String {
        pieces.id + (separator?.id ?? "")
    }

    // MARK: Hashable Protocol

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Equatable Protocol

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Stubbable Protocol

    static func stub() -> Self {
        .init(pieces: LocalizableArray.stub(elements: [.stub(), .stub()]), separator: LocalizableString.constant("."))
    }
}

private extension LocalizableCompoundValue {
    enum CodingKeys: String, CodingKey {
        case pieces
        case separator
    }
}

public extension Collection where Element: Localizable {
    /// Combines the `Localizable` items into an `LocalizableCompoundValue`
    ///
    /// > The order of the collection should be in left-to-right order.  If the **Locale**
    /// > is right-to-left, localization will handle it automatically.
    ///
    /// - Parameter separator: An optional separator that will be placed
    ///   between each of the provided items
    func joined(separator: LocalizableString? = nil) -> LocalizableCompoundValue<Element> {
        .init(pieces: LocalizableArray.constant(Array(self)), separator: separator)
    }
}
