// LocalizableInt.swift
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

/// ``LocalizableInt`` stores an integer value and converts it to a **String** using the **Locale**'s
/// localization settings
///
/// Localization settings are controlled via a **NumberFormatter** that is derived from the **Locale**.
public struct LocalizableInt: Codable, Hashable, Comparable, LocalizableValue, Stubbable {
    public let value: Int
    public let showGroupingSeparator: Bool
    public let groupingSize: Int
    private let _localizedString: String?

    // MARK: Initialization Methods

    public init(value: Int, showGroupingSeparator: Bool = true, groupingSize: Int = 3) {
        self.init(
            value: value,
            showGroupingSeparator: showGroupingSeparator,
            groupingSize: groupingSize,
            localizedString: nil
        )
    }
}

public extension LocalizableInt {
    // MARK: Localizable Protocol

    var isEmpty: Bool { false }

    var localizationStatus: LocalizableStatus {
        _localizedString == nil ? .localizationPending : .localized
    }

    var localizedString: String {
        get throws {
            guard let localizedString = _localizedString else {
                throw LocalizerError.localizationUnbound
            }

            return localizedString
        }
    }

    // MARK: Codable Protocol

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.value = try container.decode(Int.self, forKey: .value)
        self.showGroupingSeparator = try container.decode(Bool.self, forKey: .showGroupingSeparator)
        self.groupingSize = try container.decode(Int.self, forKey: .groupingSize)
        self._localizedString = try container.decode(String.self, forKey: .localizedString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(showGroupingSeparator, forKey: .showGroupingSeparator)
        try container.encode(groupingSize, forKey: .groupingSize)

        // If we've already been localized, just send that
        if let _localizedString {
            try container.encode(_localizedString, forKey: .localizedString)
        } else {
            // REVIEWED: DGH - The RHS of this ternary will never be executed, so a block
            //   will never be covered
            try container.encode(encoder.localizeString(self) ?? "", forKey: .localizedString)
        }
    }

    // MARK: Identifiable Protocol

    var id: String { "\(value)" }

    // MARK: Hashable Protocol

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Equatable Protocol

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Comparable Protocol

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    // MARK: Stubbable Protocol

    static func stub() -> Self {
        .stub(value: nil)
    }

    static func stub(value: Int?) -> Self {
        let value = value ?? 42

        return .init(
            value: value,
            localizedString: "\(value)"
        )
    }
}

private extension LocalizableInt {
    init(value: Int, showGroupingSeparator: Bool = true, groupingSize: Int = 3, localizedString: String?) {
        self.value = value
        self.showGroupingSeparator = showGroupingSeparator
        self.groupingSize = groupingSize
        self._localizedString = localizedString
    }

    enum CodingKeys: String, CodingKey {
        case value = "v"
        case localizedString = "ls"
        case showGroupingSeparator = "sgep"
        case groupingSize = "gsepsz"
    }
}
