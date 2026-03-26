// LocalizableDouble.swift
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

/// ``LocalizableDouble`` stores a double-precision floating-point value and converts it to a **String** using the **Locale**'s
/// localization settings
///
/// Localization settings are controlled via a **NumberFormatter** that is derived from the **Locale**.
public struct LocalizableDouble: Codable, Hashable, Comparable, LocalizableValue, Stubbable {
    public let value: Double
    public let showGroupingSeparator: Bool
    public let groupingSize: Int
    public let minimumFractionDigits: Int
    public let maximumFractionDigits: Int
    private let _localizedString: String?

    // MARK: Initialization Methods

    public init(value: Double, showGroupingSeparator: Bool = true, groupingSize: Int = 3, minimumFractionDigits: Int = 0, maximumFractionDigits: Int = 2) {
        self.init(
            value: value,
            showGroupingSeparator: showGroupingSeparator,
            groupingSize: groupingSize,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits,
            localizedString: nil
        )
    }
}

public extension LocalizableDouble {
    // MARK: Localizable Protocol

    var isEmpty: Bool {
        false
    }

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

        self.value = try container.decode(Double.self, forKey: .value)
        self.showGroupingSeparator = try container.decode(Bool.self, forKey: .showGroupingSeparator)
        self.groupingSize = try container.decode(Int.self, forKey: .groupingSize)
        self.minimumFractionDigits = try container.decode(Int.self, forKey: .minimumFractionDigits)
        self.maximumFractionDigits = try container.decode(Int.self, forKey: .maximumFractionDigits)
        self._localizedString = try container.decode(String.self, forKey: .localizedString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(showGroupingSeparator, forKey: .showGroupingSeparator)
        try container.encode(groupingSize, forKey: .groupingSize)
        try container.encode(minimumFractionDigits, forKey: .minimumFractionDigits)
        try container.encode(maximumFractionDigits, forKey: .maximumFractionDigits)

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

    var id: String {
        "\(value)"
    }

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

    static func stub(value: Double?) -> Self {
        let value = value ?? 3.14159

        return .init(
            value: value,
            localizedString: "\(value)"
        )
    }
}

private extension LocalizableDouble {
    init(value: Double, showGroupingSeparator: Bool = true, groupingSize: Int = 3, minimumFractionDigits: Int = 0, maximumFractionDigits: Int = 2, localizedString: String?) {
        self.value = value
        self.showGroupingSeparator = showGroupingSeparator
        self.groupingSize = groupingSize
        self.minimumFractionDigits = minimumFractionDigits
        self.maximumFractionDigits = maximumFractionDigits
        self._localizedString = localizedString
    }

    enum CodingKeys: String, CodingKey {
        case value = "v"
        case localizedString = "ls"
        case showGroupingSeparator = "sgsep"
        case groupingSize = "gsepsz"
        case minimumFractionDigits = "minfd"
        case maximumFractionDigits = "maxfd"
    }
}
