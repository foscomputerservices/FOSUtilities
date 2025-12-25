// EmbeddedViewModelTests.swift
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
@testable import FOSMVVM
import FOSTesting
import Foundation
import Testing

@Suite("Embedded View Model Tests")
struct EmbeddedViewModelTests: LocalizableTestCase {
    @Test func embeddedLocalization() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: MainViewModel = try .stub().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.innerViewModels[0].innerString.localizedString == "Inner String")
        #expect(try vm.innerViewModels[0].innerSubs.localizedString == "SubInt: 42")

        #expect(try vm.innerViewModels[1].innerString.localizedString == "Inner String")
        #expect(try vm.innerViewModels[1].innerSubs.localizedString == "SubInt: 43")
    }

    @Test func embeddedLocalization_nonRetrievablePropertyNamesParent() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let parent: NonRetrievablePropertyNamesParent = try .stub()
            .toJSON(encoder: vmEncoder)
            .fromJSON()

        #expect(try parent.innerViewModel.innerString.localizedString == "Inner String")
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private struct MainViewModel: ViewModel {
    @LocalizedString var mainString
    let innerViewModels: [InnerViewModel]

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> MainViewModel {
        .init(
            innerViewModels: [.stub(subInt: 42), .stub(subInt: 43)],
            vmId: .init()
        )
    }
}

private struct InnerViewModel: ViewModel {
    @LocalizedString var innerString
    @LocalizedSubs(substitutions: \.subs) var innerSubs

    var subs: [String: any Localizable] { [
        "subInt": LocalizableInt(value: subInt)
    ] }

    var vmId: FOSMVVM.ViewModelId

    private let subInt: Int

    static func stub() -> InnerViewModel {
        .stub(subInt: 42)
    }

    static func stub(subInt: Int = 42) -> InnerViewModel {
        .init(
            vmId: .init(type: Self.self),
            subInt: subInt
        )
    }
}

private struct NonRetrievablePropertyNamesParent: Codable, Sendable {
    let innerViewModel: InnerViewModel

    static func stub() -> Self {
        .init(innerViewModel: .stub())
    }
}

// TODO: Future

private struct BrokenViewModel: ViewModel {
    @LocalizedString var mainString

    // This doesn't work because there's no way to encode
    // the inner property values and keep them separate.
    // Current lookup is only by type.
    // See JSONEncoder.Encoder.currentModel<T>(for:)
    let innerViewModel1: InnerViewModel
    let innerViewModel2: InnerViewModel

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self {
        .init(
            innerViewModel1: .stub(subInt: 42),
            innerViewModel2: .stub(subInt: 43),
            vmId: .init()
        )
    }
}

