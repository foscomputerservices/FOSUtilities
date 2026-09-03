// TranslationWalkTests.swift
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
@testable import FOSMVVM
import FOSTesting
import Foundation
import Testing

/// `expectTranslations` descends into stored child ViewModels and collections, and the
/// test encoder is strict — a missing key on a child fails the parent's pass.
@Suite("Translation walk", .serialized)
struct TranslationWalkTests: LocalizableTestCase {
    @Test("A fully translated parent with children passes")
    func fullyTranslatedPasses() throws {
        try expectTranslations(WalkParentViewModel.self, locales: [Self.en])
    }

    @Test("A child whose key is missing in a locale fails the parent's pass at encode")
    func missingChildKeyFails() {
        #expect(throws: LocalizerError.self) {
            try expectTranslations(WalkParentViewModel.self, locales: [Self.es])
        }
    }

    @Test("A child whose translation is blank fails the parent's pass, naming the row")
    func blankChildTranslationFails() throws {
        do {
            try expectTranslations(BlankParentViewModel.self, locales: [Self.es])
            Issue.record("Expected the blank child translation to fail")
        } catch FOSLocalizableError.error(let message) {
            #expect(message.contains("rows[0].label"))
            #expect(message.contains("es"))
        }
    }

    @Test("The strict encoder throws on a missing key; the plain encoder encodes an empty string")
    func strictEncoderThrows() throws {
        let child = WalkChildViewModel.stub()
        #expect(throws: LocalizerError.self) {
            _ = try child.toJSON(encoder: encoder(locale: Self.es))
        }

        let lenient = JSONEncoder.localizingEncoder(locale: Self.es, localizationStore: locStore)
        let decoded: WalkChildViewModel = try child.toJSON(encoder: lenient).fromJSON()
        #expect(decoded.label.isEmpty)
    }

    let locStore: LocalizationStore
    var locales: Set<Locale> {
        [Self.en, Self.es]
    }

    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private struct WalkParentViewModel: ViewModel {
    @LocalizedString var title
    let child: WalkChildViewModel
    let rows: [WalkChildViewModel]
    let optionalChild: WalkChildViewModel?

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> WalkParentViewModel {
        .init(child: .stub(), rows: [.stub(), .stub()], optionalChild: .stub(), vmId: .init())
    }
}

private struct WalkChildViewModel: ViewModel {
    @LocalizedString var label
    var vmId: FOSMVVM.ViewModelId

    static func stub() -> WalkChildViewModel {
        .init(vmId: .init())
    }
}

private struct BlankParentViewModel: ViewModel {
    @LocalizedString var title
    let rows: [BlankChildViewModel]

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> BlankParentViewModel {
        .init(rows: [.stub()], vmId: .init())
    }
}

private struct BlankChildViewModel: ViewModel {
    @LocalizedString var label
    var vmId: FOSMVVM.ViewModelId

    static func stub() -> BlankChildViewModel {
        .init(vmId: .init())
    }
}
