// LocalizableCase.swift
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

import FOSFoundation
import Foundation

/// ``LocalizableCase`` carries an enum case and the localized word that names it
///
/// A ViewModel stores the case; the view switches on ``value`` and shows the word:
///
/// ```swift
/// public enum Priority: CaseIterable, Codable, Hashable, Sendable {
///     case low
///     case high
/// }
///
/// @ViewModel
/// public struct CardRowViewModel {
///     public let priority: LocalizableCase<Priority>
///
///     public init(card: Card) {
///         self.priority = LocalizableCase(card.priority)
///     }
/// }
/// ```
///
/// ```swift
/// Text(viewModel.priority)
///     .foregroundStyle(viewModel.priority.value == .high ? .red : .primary)
/// ```
///
/// Each case's word lives in the YAML under the enum's type name, keyed by the case name:
///
/// ```yaml
/// en:
///   Priority:
///     low: "Low"
///     high: "High"
/// ```
///
/// An enum nested in another type sits under that type's key, as it does for
/// ``LocalizableString/localized(case:parentType:parentKeys:index:)``. For `Board.Visibility`:
///
/// ```yaml
/// en:
///   Board:
///     Visibility:
///       workspace: "Everyone in the workspace"
///       members: "Board members only"
/// ```
///
/// ## Pickers
///
/// Built with `includingAllCases: true`, the value also carries the word of every case, in
/// `allCases` order, as ``choices``:
///
/// ```swift
/// self.visibility = LocalizableCase(board.visibility, includingAllCases: true)
/// ```
///
/// ```swift
/// Picker(selection: $selection) {
///     ForEach(viewModel.visibility.choices, id: \.value) { choice in
///         Text(choice.localizedString).tag(choice.value)
///     }
/// } label: { Text(viewModel.visibilityTitle) }
/// ```
///
/// > The enum must be `CaseIterable` and its cases must carry no associated values: each case is
/// > one word in the YAML.
///
/// > `expectFullViewModelTests()` proves that every case of the enum has a word in every locale,
/// > not only the case a stub holds.
public struct LocalizableCase<Case: CaseIterable & Codable & Hashable & Sendable>: LocalizableValue, Stubbable {
    /// The enum case
    ///
    /// ```swift
    /// if viewModel.priority.value == .high {
    ///     Image(systemName: "exclamationmark")
    /// }
    /// ```
    public let value: Case

    private let includesAllCases: Bool
    private let word: String?
    private let caseWords: [CaseWord]?

    /// The word of every case of `Case`, in `allCases` order
    ///
    /// ```swift
    /// ForEach(viewModel.visibility.choices, id: \.value) { choice in
    ///     Text(choice.localizedString).tag(choice.value)
    /// }
    /// ```
    ///
    /// > Empty unless the value was created with `includingAllCases: true`, and until it has
    /// > been localized.
    public var choices: [(value: Case, localizedString: String)] {
        (caseWords ?? []).map { (value: $0.value, localizedString: $0.word) }
    }

    // MARK: Initialization Methods

    /// Creates a ``LocalizableCase`` for *value*
    ///
    /// ```swift
    /// LocalizableCase(card.priority)
    /// LocalizableCase(board.visibility, includingAllCases: true)
    /// ```
    ///
    /// - Parameters:
    ///   - value: The enum case
    ///   - includingAllCases: When **true**, the localized value also carries the word of every
    ///     case of `Case` in ``choices`` (default: **false**)
    public init(_ value: Case, includingAllCases: Bool = false) {
        self.init(value: value, includesAllCases: includingAllCases, word: nil, caseWords: nil)
    }
}

public extension LocalizableCase {
    // MARK: Localizable Protocol

    var isEmpty: Bool {
        word?.isEmpty ?? true
    }

    var localizationStatus: LocalizableStatus {
        word == nil ? .localizationPending : .localized
    }

    var localizedString: String {
        get throws {
            guard let word else {
                throw LocalizerError.localizationUnbound
            }

            return word
        }
    }

    func localized(in locale: Locale, store: LocalizationStore) throws -> String? {
        try LocalizableString
            .localized(LocalizableRef(caseOf: value))
            .localized(in: locale, store: store)
    }

    // MARK: Codable Protocol

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.value = try container.decode(Case.self, forKey: .value)
        self.includesAllCases = try container.decode(Bool.self, forKey: .includesAllCases)
        self.word = try container.decode(String.self, forKey: .localizedString)
        self.caseWords = try container.decodeIfPresent([CaseWord].self, forKey: .caseWords)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(includesAllCases, forKey: .includesAllCases)
        try container.encode(word ?? encoder.localizeString(self) ?? "", forKey: .localizedString)

        if includesAllCases {
            let caseWords = try caseWords ?? Case.allCases.map { enumCase in
                try CaseWord(
                    value: enumCase,
                    word: encoder.localizeString(Self(enumCase)) ?? ""
                )
            }
            try container.encode(caseWords, forKey: .caseWords)
        }
    }

    // MARK: Identifiable Protocol

    var id: String {
        "\(value)"
    }

    // MARK: Hashable Protocol

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(includesAllCases)
    }

    // MARK: Equatable Protocol

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value && lhs.includesAllCases == rhs.includesAllCases
    }

    // MARK: Stubbable Protocol

    /// A ``LocalizableCase`` for tests and previews
    ///
    /// ```swift
    /// let priority: LocalizableCase<Priority> = .stub(value: .high)
    /// ```
    ///
    /// - Parameters:
    ///   - value: The enum case (default: the first of `allCases`)
    ///   - includingAllCases: See ``init(_:includingAllCases:)`` (default: **false**)
    static func stub(value: Case = firstCase, includingAllCases: Bool = false) -> Self {
        .init(value, includingAllCases: includingAllCases)
    }

    /// A ``LocalizableCase`` holding the first of `allCases`, for tests and previews
    ///
    /// ```swift
    /// let priority: LocalizableCase<Priority> = .stub()
    /// ```
    static func stub() -> Self {
        .stub(includingAllCases: false)
    }
}

// swiftformat:disable:next docComments
// package: FOSTesting's translation walk sees a LocalizableCase only as `any Localizable`
// and must prove every case of its enum; internal cannot cross into FOSTesting, and this
// is no API for apps.
package protocol EveryCaseLocalizable {
    /// The cases of the enum that have no word, or an empty one, in *locale*
    func casesMissingTranslation(in locale: Locale, store: LocalizationStore) throws -> [String]
}

extension LocalizableCase: EveryCaseLocalizable {
    package func casesMissingTranslation(in locale: Locale, store: LocalizationStore) throws -> [String] {
        try Case.allCases.compactMap { enumCase in
            let word = try Self(enumCase).localized(in: locale, store: store)
            return (word ?? "").isEmpty ? "\(enumCase)" : nil
        }
    }
}

extension LocalizableCase {
    // @usableFromInline: a public default argument (stub(value:)) may only reach it so.
    @usableFromInline static var firstCase: Case {
        guard let first = Case.allCases.first else {
            preconditionFailure("LocalizableCase<\(Case.self)>.stub(): \(Case.self) has no cases to stub")
        }
        return first
    }
}

private extension LocalizableCase {
    init(value: Case, includesAllCases: Bool, word: String?, caseWords: [CaseWord]?) {
        self.value = value
        self.includesAllCases = includesAllCases
        self.word = word
        self.caseWords = caseWords
    }

    struct CaseWord: Codable, Hashable, Sendable {
        let value: Case
        let word: String

        enum CodingKeys: String, CodingKey {
            case value = "v"
            case word = "ls"
        }
    }

    enum CodingKeys: String, CodingKey {
        case value = "v"
        case includesAllCases = "all"
        case localizedString = "ls"
        case caseWords = "cs"
    }
}
