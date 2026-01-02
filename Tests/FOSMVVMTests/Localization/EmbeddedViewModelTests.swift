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
        try expectFullViewModelTests(MainViewModel.self)

        // Check the exact strings in English to make sure that the substitutions are correct
        let vm: MainViewModel = try .stub().toJSON(encoder: encoder(locale: en)).fromJSON()
        #expect(try vm.innerViewModels[0].innerString.localizedString == "Inner String")
        #expect(try vm.innerViewModels[0].innerSubs.localizedString == "SubInt: 42")

        #expect(try vm.innerViewModels[1].innerString.localizedString == "Inner String")
        #expect(try vm.innerViewModels[1].innerSubs.localizedString == "SubInt: 43")
    }

    @Test func embeddedLocalization_nonRetrievablePropertyNamesParent() throws {
        let parent: NonRetrievablePropertyNamesParent = try .stub()
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(try parent.innerViewModel.innerString.localizedString == "Inner String")
    }

    @Test func multipleEmbeddedViewModelsOfSameType() throws {
        try expectFullViewModelTests(MultipleInnerViewModel.self)

        // Check the exact strings in English to make sure that the substitutions are correct
        let vm: MultipleInnerViewModel = try .stub().toJSON(encoder: encoder(locale: en)).fromJSON()

        // innerViewModel1 should have subInt: 42
        #expect(try vm.innerViewModel1.innerSubs.localizedString == "SubInt: 42")
        // innerViewModel2 should have subInt: 43 (NOT 42!)
        #expect(try vm.innerViewModel2.innerSubs.localizedString == "SubInt: 43")
    }

    // MARK: - Optional ViewModel Tests

    @Test func optionalEmbeddedViewModel_present() throws {
        try expectFullViewModelTests(OptionalInnerViewModel.self)

        let vm: OptionalInnerViewModel = try .stub(inner: .stub(subInt: 99))
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(vm.inner != nil)
        #expect(try vm.inner?.innerSubs.localizedString == "SubInt: 99")
    }

    @Test func optionalEmbeddedViewModel_nil() throws {
        let vm: OptionalInnerViewModel = try .stub(inner: nil)
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(vm.inner == nil)
    }

    @Test func arrayOfOptionalViewModels() throws {
        try expectFullViewModelTests(ArrayOfOptionalsViewModel.self)

        let vm: ArrayOfOptionalsViewModel = try .stub(items: [
            .stub(subInt: 10),
            nil,
            .stub(subInt: 30)
        ]).toJSON(encoder: encoder(locale: en)).fromJSON()

        #expect(vm.items.count == 3)
        #expect(try vm.items[0]?.innerSubs.localizedString == "SubInt: 10")
        #expect(vm.items[1] == nil)
        #expect(try vm.items[2]?.innerSubs.localizedString == "SubInt: 30")
    }

    @Test func optionalArrayOfViewModels_present() throws {
        try expectFullViewModelTests(OptionalArrayViewModel.self)

        let vm: OptionalArrayViewModel = try .stub(items: [.stub(subInt: 55)])
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(vm.items != nil)
        #expect(try vm.items?[0].innerSubs.localizedString == "SubInt: 55")
    }

    @Test func optionalArrayOfViewModels_nil() throws {
        let vm: OptionalArrayViewModel = try .stub(items: nil)
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(vm.items == nil)
    }

    // MARK: - Deep Nesting Tests

    @Test func deeplyNestedViewModels() throws {
        try expectFullViewModelTests(DeepLevel1ViewModel.self)

        // Tests 3 levels of nesting: DeepLevel1 > DeepLevel2 > InnerViewModel
        let vm: DeepLevel1ViewModel = try .stub(deepValue: 777)
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(try vm.level2.inner.innerSubs.localizedString == "SubInt: 777")
    }

    @Test func nestedArraysOfViewModels() throws {
        try expectFullViewModelTests(NestedArraysViewModel.self)

        let vm: NestedArraysViewModel = try .stub()
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        // First outer array element, first inner array element
        #expect(try vm.outer[0].inner[0].innerSubs.localizedString == "SubInt: 100")
        // First outer array element, second inner array element
        #expect(try vm.outer[0].inner[1].innerSubs.localizedString == "SubInt: 101")
        // Second outer array element, first inner array element
        #expect(try vm.outer[1].inner[0].innerSubs.localizedString == "SubInt: 200")
    }

    // MARK: - Empty/Single Collection Tests

    @Test func emptyArrayOfViewModels() throws {
        let vm: MainViewModel = try .init(innerViewModels: [], vmId: .init())
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(vm.innerViewModels.isEmpty)
    }

    @Test func singleElementArray() throws {
        let vm: MainViewModel = try .init(innerViewModels: [.stub(subInt: 42)], vmId: .init())
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(vm.innerViewModels.count == 1)
        #expect(try vm.innerViewModels[0].innerSubs.localizedString == "SubInt: 42")
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

private struct MultipleInnerViewModel: ViewModel {
    @LocalizedString var mainString

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

// MARK: - Optional ViewModel Test Structs

private struct OptionalInnerViewModel: ViewModel {
    @LocalizedString var title
    let inner: InnerViewModel?

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self { stub(inner: .stub()) }

    static func stub(inner: InnerViewModel?) -> Self {
        .init(inner: inner, vmId: .init())
    }
}

private struct ArrayOfOptionalsViewModel: ViewModel {
    @LocalizedString var title
    let items: [InnerViewModel?]

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self { stub(items: [.stub()]) }

    static func stub(items: [InnerViewModel?]) -> Self {
        .init(items: items, vmId: .init())
    }
}

private struct OptionalArrayViewModel: ViewModel {
    @LocalizedString var title
    let items: [InnerViewModel]?

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self { stub(items: [.stub()]) }

    static func stub(items: [InnerViewModel]?) -> Self {
        .init(items: items, vmId: .init())
    }
}

// MARK: - Deep Nesting Test Structs (reuses InnerViewModel which has YAML entries)

private struct DeepLevel1ViewModel: ViewModel {
    @LocalizedString var mainString
    let level2: DeepLevel2ViewModel

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self { stub(deepValue: 42) }

    static func stub(deepValue: Int) -> Self {
        .init(level2: .stub(deepValue: deepValue), vmId: .init())
    }
}

private struct DeepLevel2ViewModel: ViewModel {
    @LocalizedString var mainString
    let inner: InnerViewModel

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self { stub(deepValue: 42) }

    static func stub(deepValue: Int) -> Self {
        .init(inner: .stub(subInt: deepValue), vmId: .init())
    }
}

// MARK: - Nested Arrays Test Structs

private struct NestedArraysViewModel: ViewModel {
    @LocalizedString var title
    let outer: [MiddleViewModel]

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self {
        .init(
            outer: [
                .stub(innerValues: [100, 101]),
                .stub(innerValues: [200])
            ],
            vmId: .init()
        )
    }
}

private struct MiddleViewModel: ViewModel {
    @LocalizedString var middleString
    let inner: [InnerViewModel]

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self { stub(innerValues: [42]) }

    static func stub(innerValues: [Int]) -> Self {
        .init(
            inner: innerValues.map { .stub(subInt: $0) },
            vmId: .init()
        )
    }
}
