// LocalizableDate.swift
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
import Foundation

/// ``LocalizableDate`` stores a Date value and converts it to a **String** using the **Locale**'s
/// localization settings
///
/// Localization settings are controlled via a **DateFormatter** that is derived from the **Locale**.
public struct LocalizableDate: Codable, Hashable, Comparable, LocalizableValue, Stubbable {
    public let value: Date
    public let dateStyle: DateFormatter.Style?
    public let timeStyle: DateFormatter.Style?
    public let dateFormat: String?
    private let _localizedString: String?

    // MARK: Initialization Methods

    public init(
        value: Date,
        dateStyle: DateFormatter.Style? = nil,
        timeStyle: DateFormatter.Style? = nil,
        dateFormat: String? = nil
    ) {
        self.init(
            value: value,
            dateStyle: dateStyle,
            timeStyle: timeStyle,
            dateFormat: dateFormat,
            localizedString: nil
        )
    }
}

public extension LocalizableDate {
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

        let timeInterval = try container.decode(TimeInterval.self, forKey: .value)
        self.value = Date(timeIntervalSince1970: timeInterval)

        let dateStyleRaw = try container.decodeIfPresent(UInt.self, forKey: .dateStyle)
        self.dateStyle = dateStyleRaw != nil ? DateFormatter.Style(rawValue: dateStyleRaw!) : nil

        let timeStyleRaw = try container.decodeIfPresent(UInt.self, forKey: .timeStyle)
        self.timeStyle = timeStyleRaw != nil ? DateFormatter.Style(rawValue: timeStyleRaw!) : nil

        self.dateFormat = try container.decodeIfPresent(String.self, forKey: .dateFormat)
        self._localizedString = try container.decode(String.self, forKey: .localizedString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.timeIntervalSince1970, forKey: .value)

        try container.encodeIfPresent(dateStyle?.rawValue, forKey: .dateStyle)
        try container.encodeIfPresent(timeStyle?.rawValue, forKey: .timeStyle)
        try container.encodeIfPresent(dateFormat, forKey: .dateFormat)

        // REVIEWED: DGH - The RHS of this ternary will never be executed, so a block
        //   will never be covered
        try container.encode(encoder.localizeString(self) ?? "", forKey: .localizedString)
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

    static func stub(value: Date?) -> Self {
        let value = value ?? .now

        return .init(
            value: value,
            localizedString: "\(value)"
        )
    }
}

private extension LocalizableDate {
    init(
        value: Date,
        dateStyle: DateFormatter.Style? = nil,
        timeStyle: DateFormatter.Style? = nil,
        dateFormat: String? = nil,
        localizedString: String?
    ) {
        self.value = value
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
        self.dateFormat = dateFormat
        self._localizedString = localizedString
    }

    enum CodingKeys: String, CodingKey {
        case value = "v"
        case dateStyle = "ds"
        case timeStyle = "ts"
        case dateFormat = "df"
        case localizedString = "ls"
    }
}
