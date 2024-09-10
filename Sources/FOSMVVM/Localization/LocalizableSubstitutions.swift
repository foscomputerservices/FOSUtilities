// LocalizableSubstitutions.swift
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

/// Maps substitution points in an `LocalizableString`
///
/// `LocalizableSubstitutions` binds for substitution points in an `LocalizableString` to `Localizable`s.
/// The substitution points are indicated in the string with **%{key}**, where **key** is the name of the binding
///  and the **%{}** wrapper indicates the substitution point.
///
/// ## Example
///
/// ```swift
/// let boundString = LocalizableString.constant("There are %{count} apples.")
///       .bind(substitutions: ["count": LocalizableInt(25)])
/// ```
///
/// - Note: If the substations come from a YAML file, the **@LocalizeSubs** property wrapper can
///   be used.
public struct LocalizableSubstitutions: Localizable {
    public let baseString: LocalizableString
    public let substitutions: [String: any Localizable]

    // MARK: Initialization Methods

    public init(baseString: LocalizableString, substitutions: [String: any Localizable]) {
        self.baseString = baseString
        self.substitutions = substitutions
    }
}

public extension LocalizableSubstitutions {
    // MARK: Localizable Protocol

    var isEmpty: Bool {
        baseString.isEmpty || ((try? localizedString.isEmpty) ?? true)
    }

    var localizationStatus: LocalizableStatus {
        guard baseString.localizationStatus == .localized else {
            return .localizationPending
        }

        return substitutions.values.allSatisfy { $0.localizationStatus == .localized }
            ? .localized
            : .localizationPending
    }

    var localizedString: String {
        get throws {
            do {
                // This supports the case where all values are constants, which works before codable
                return try substitutions.reduce(baseString.localizedString) { result, tuple in
                    try result.replacingOccurrences(of: "%{\(tuple.key)}", with: tuple.value.localizedString)
                }
            } catch let e {
                throw LocalizerError.processUnknown(error: e)
            }
        }
    }

    // MARK: Codable Protocol

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.baseString = try .constant(container.decode(String.self))
        self.substitutions = [:]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoder.localizeString(self))
    }

    // MARK: Identifiable Protocol

    var id: String {
        baseString.id + "." + substitutions.keys.sorted().joined(separator: ".")
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
        .init(baseString: LocalizableString.stub(), substitutions: ["": LocalizableString.stub()])
    }
}

public extension LocalizableString {
    /// Binds the substitution points of an `LocalizableString`
    ///
    /// - Parameter substitutions: The values to substitute
    /// - Returns: A ``LocalizableSubstitutions`` that will substitute all
    ///  substitution points in the ``LocalizableString`` upon localization
    func bind(substitutions: [String: any Localizable]) -> LocalizableSubstitutions {
        .init(baseString: self, substitutions: substitutions)
    }
}
