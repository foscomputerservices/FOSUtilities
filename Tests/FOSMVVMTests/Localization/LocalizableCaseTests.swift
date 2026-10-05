// LocalizableCaseTests.swift
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
import FOSMVVM
import FOSTesting
import Foundation
import Testing

@Suite("LocalizableCase")
struct LocalizableCaseTests: LocalizableTestCase {
    // MARK: Words

    @Test func word_resolvesPerLocale() throws {
        let priority = LocalizableCase(Priority.high)
        #expect(priority.localizationStatus == .localizationPending)
        #expect(throws: LocalizerError.self) { try priority.localizedString }

        let english: LocalizableCase<Priority> = try priority.toJSON(encoder: encoder(locale: Self.en)).fromJSON()
        let spanish: LocalizableCase<Priority> = try priority.toJSON(encoder: encoder(locale: Self.es)).fromJSON()

        #expect(english.localizationStatus == .localized)
        #expect(try english.localizedString == "High")
        #expect(try spanish.localizedString == "Alta")
    }

    @Test func nestedEnum_isKeyedUnderItsParentType() throws {
        let visibility: LocalizableCase<Board.Visibility> = try LocalizableCase(Board.Visibility.members)
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(try visibility.localizedString == "Board members only")
    }

    @Test func enumNestedTwoLevels_isKeyedByItsFullPath() throws {
        let english: LocalizableCase<Board.Card.Status> = try LocalizableCase(Board.Card.Status.done)
            .toJSON(encoder: encoder())
            .fromJSON()
        let spanish: LocalizableCase<Board.Card.Status> = try LocalizableCase(Board.Card.Status.done)
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()

        #expect(try english.localizedString == "Done")
        #expect(try spanish.localizedString == "Hecha")
    }

    @Test func enumNestedOneLevel_matchesTheExistingCaseRule() throws {
        let caseWord: LocalizableCase<Board.Visibility> = try LocalizableCase(Board.Visibility.workspace)
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()
        let stringWord: LocalizableString = try LocalizableString
            .localized(case: Board.Visibility.workspace, parentType: Board.self)
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()

        #expect(try caseWord.localizedString == stringWord.localizedString)
    }

    @Test func enumNestedInAGenericType_isKeyedUnderTheTypesName() throws {
        let tier: LocalizableCase<Workspace<Int>.Tier> = try LocalizableCase(Workspace<Int>.Tier.team)
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(try tier.localizedString == "Team")
    }

    @Test func enumDeclaredInAFunction_isKeyedAsTopLevel() throws {
        enum CardEstimate: CaseIterable, Codable, Hashable {
            case small
            case large
        }

        let estimate: LocalizableCase<CardEstimate> = try LocalizableCase(CardEstimate.large)
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()

        #expect(try estimate.localizedString == "Grande")
    }

    // MARK: Choices

    @Test func includingAllCases_yieldsEveryWordInOrder() throws {
        let visibility: LocalizableCase<Board.Visibility> = try LocalizableCase(Board.Visibility.members, includingAllCases: true)
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(visibility.choices.map(\.value) == Board.Visibility.allCases)
        #expect(visibility.choices.map(\.localizedString) == ["Everyone in the workspace", "Board members only"])
    }

    @Test func withoutTheOption_choicesIsEmpty() throws {
        let priority = LocalizableCase(Priority.low)
        #expect(priority.choices.isEmpty)

        let localized: LocalizableCase<Priority> = try priority.toJSON(encoder: encoder()).fromJSON()
        #expect(localized.choices.isEmpty)
    }

    @Test func includingAllCases_beforeLocalization_choicesIsEmpty() {
        #expect(LocalizableCase(Priority.low, includingAllCases: true).choices.isEmpty)
    }

    // MARK: Codable

    @Test func roundTrip_keepsValueAndWord() throws {
        let localized: LocalizableCase<Priority> = try LocalizableCase(Priority.high, includingAllCases: true)
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()
        let again: LocalizableCase<Priority> = try localized
            .toJSON(encoder: encoder(locale: Self.en))
            .fromJSON()

        #expect(again.value == .high)
        #expect(try again.localizedString == "Alta")
        #expect(again.choices.map(\.localizedString) == ["Baja", "Alta"])
        #expect(again == localized)
    }

    @Test func roundTrip_throughAPlainDecoder_keepsTheWord() throws {
        let localized: LocalizableCase<Priority> = try LocalizableCase(Priority.low)
            .toJSON(encoder: encoder())
            .fromJSON(decoder: JSONDecoder())

        #expect(localized.value == .low)
        #expect(try localized.localizedString == "Low")
    }

    // MARK: Missing translations

    @Test func missingTranslation_failsAStrictEncode() {
        #expect(throws: LocalizerError.self) {
            _ = try LocalizableCase(Assignment.Role.reviewer).toJSON(encoder: encoder(locale: Self.es))
        }
    }

    @Test func missingTranslation_ofAnotherCase_failsAStrictEncodeOfChoices() {
        #expect(throws: LocalizerError.self) {
            _ = try LocalizableCase(Assignment.Role.owner, includingAllCases: true).toJSON(encoder: encoder(locale: Self.es))
        }
    }

    @Test func missingTranslation_encodesEmptyWhenLenient() throws {
        let lenient = JSONEncoder.localizingEncoder(in: Self.es, store: locStore)
        let role: LocalizableCase<Assignment.Role> = try LocalizableCase(Assignment.Role.reviewer)
            .toJSON(encoder: lenient)
            .fromJSON()

        #expect(role.isEmpty)
    }

    // MARK: Translation walk

    @Test func translationWalk_passesWhenEveryCaseIsTranslated() throws {
        try expectTranslations(PriorityRowViewModel.self)
    }

    @Test func translationWalk_failsWhenACaseTheStubDoesNotHoldIsUntranslated() throws {
        // The stub holds .owner, which is translated in every locale; .reviewer is not in es
        do {
            try expectTranslations(RoleRowViewModel.self)
            Issue.record("Expected the untranslated case to fail the walk")
        } catch FOSLocalizableError.error(let message) {
            #expect(message.contains("role"))
            #expect(message.contains("reviewer"))
            #expect(message.contains("es"))
        }
    }

    @Test func translationWalk_ofALocalizableCaseValue_provesEveryCase() {
        #expect(throws: FOSLocalizableError.self) {
            try expectTranslations(LocalizableCase(Assignment.Role.owner))
        }
    }

    // MARK: Stubbable

    @Test func stub_defaultsToTheFirstCase() {
        #expect(LocalizableCase<Priority>.stub().value == .low)
        #expect(LocalizableCase<Priority>.stub(value: .high).value == .high)
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private enum Priority: CaseIterable, Codable, Hashable {
    case low
    case high
}

private struct Board {
    let visibility: Visibility

    enum Visibility: CaseIterable, Codable, Hashable {
        case workspace
        case members
    }

    enum Card {
        enum Status: CaseIterable, Codable, Hashable {
            case open
            case done
        }
    }
}

private struct Workspace<T> {
    let tier: Tier
    let owner: T

    enum Tier: CaseIterable, Codable, Hashable {
        case free
        case team
    }
}

private struct Assignment {
    let role: Role

    enum Role: CaseIterable, Codable, Hashable {
        case owner
        case reviewer
    }
}

@ViewModel
private struct PriorityRowViewModel {
    @LocalizedString var title
    let priority: LocalizableCase<Priority>
    var vmId: ViewModelId

    static func stub(priority: Priority = .high) -> Self {
        .init(priority: .init(priority), vmId: .init())
    }

    static func stub() -> Self {
        .stub(priority: .high)
    }
}

@ViewModel
private struct RoleRowViewModel {
    @LocalizedString var title
    let role: LocalizableCase<Assignment.Role>
    var vmId: ViewModelId

    static func stub(role: Assignment.Role = .owner) -> Self {
        .init(role: .init(role), vmId: .init())
    }

    static func stub() -> Self {
        .stub(role: .owner)
    }
}
