// ModelRegistryTests.swift
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

/// Tests for ModelRegistry path resolution behavior (tested indirectly through encoding)
///
/// The ModelRegistry tracks ViewModel instances by their path in the object graph,
/// enabling correct model lookup during nested encoding when multiple instances
/// of the same ViewModel type exist.
@Suite("Model Registry Path Resolution Tests")
struct ModelRegistryTests: LocalizableTestCase {
    // MARK: - Direct Property Lookup Tests

    @Test func directProperty_singleViewModel() throws {
        try expectFullViewModelTests(SingleSubsViewModel.self)

        // Tests that a single ViewModel at the root level is correctly registered and found
        let vm: SingleSubsViewModel = try .stub(value: 42)
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(try vm.label.localizedString == "Value: 42")
    }

    // MARK: - Array Element Lookup Tests

    @Test func arrayElement_indexedLookup() throws {
        try expectFullViewModelTests(ArrayContainerViewModel.self)

        // Tests that array elements are registered with correct numeric indices
        let vm: ArrayContainerViewModel = try .stub(values: [10, 20, 30])
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(try vm.items[0].label.localizedString == "Value: 10")
        #expect(try vm.items[1].label.localizedString == "Value: 20")
        #expect(try vm.items[2].label.localizedString == "Value: 30")
    }

    @Test func arrayElement_multipleArrays() throws {
        try expectFullViewModelTests(MultipleArraysViewModel.self)

        // Tests that multiple arrays in the same ViewModel have independent paths
        let vm: MultipleArraysViewModel = try .stub()
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        // First array
        #expect(try vm.firstArray[0].label.localizedString == "Value: 100")
        #expect(try vm.firstArray[1].label.localizedString == "Value: 101")
        // Second array - should NOT get values from first array
        #expect(try vm.secondArray[0].label.localizedString == "Value: 200")
        #expect(try vm.secondArray[1].label.localizedString == "Value: 201")
    }

    // MARK: - Nested Path Lookup Tests

    @Test func nestedPath_twoLevels() throws {
        try expectFullViewModelTests(TwoLevelNestingViewModel.self)

        // Tests parent > child path resolution
        let vm: TwoLevelNestingViewModel = try .stub(innerValue: 55)
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(try vm.child.label.localizedString == "Value: 55")
    }

    @Test func nestedPath_threeLevels() throws {
        try expectFullViewModelTests(ThreeLevelNestingViewModel.self)

        // Tests parent > child > grandchild path resolution
        let vm: ThreeLevelNestingViewModel = try .stub(deepValue: 777)
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        #expect(try vm.level2.level3.label.localizedString == "Value: 777")
    }

    @Test func nestedPath_mixedArrayAndDirect() throws {
        try expectFullViewModelTests(MixedNestingViewModel.self)

        // Tests path resolution with both array and direct property access
        let vm: MixedNestingViewModel = try .stub()
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        // Direct child
        #expect(try vm.directChild.label.localizedString == "Value: 1")
        // Array children
        #expect(try vm.arrayChildren[0].label.localizedString == "Value: 2")
        #expect(try vm.arrayChildren[1].label.localizedString == "Value: 3")
    }

    // MARK: - Multiple Instances of Same Type Tests

    @Test func multipleInstances_distinctValues() throws {
        try expectFullViewModelTests(DualInstanceViewModel.self)

        // Tests that multiple instances of the same ViewModel type get their own values
        // This is the core functionality that the ModelRegistry was created to support
        let vm: DualInstanceViewModel = try .stub()
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        // Both properties are SingleSubsViewModel, but should have different substitution values
        #expect(try vm.first.label.localizedString == "Value: 111")
        #expect(try vm.second.label.localizedString == "Value: 222")
    }

    @Test func multipleInstances_inArrays() throws {
        // Tests that array elements of the same type maintain distinct values
        let vm: ArrayContainerViewModel = try .stub(values: [1, 2, 3, 4, 5])
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        // Each element should have its own substitution value
        for (index, item) in vm.items.enumerated() {
            #expect(try item.label.localizedString == "Value: \(index + 1)")
        }
    }

    // MARK: - Registry Fallback Tests

    @Test func registryFallback_rootModel() throws {
        try expectFullViewModelTests(FallbackTestViewModel.self)

        // Tests that when a nested path isn't found, the registry falls back to parent paths
        // This happens when encoding @LocalizedSubs in a model that uses RetrievablePropertyNames
        let vm: FallbackTestViewModel = try .stub()
            .toJSON(encoder: encoder(locale: en))
            .fromJSON()

        // The inner model should still resolve even if the registry traverses up
        #expect(try vm.child.label.localizedString == "Value: 42")
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

// MARK: - Test ViewModels

/// Simple ViewModel with a localized substitution
private struct SingleSubsViewModel: ViewModel {
    @LocalizedSubs(substitutions: \.subs) var label

    var subs: [String: any Localizable] { [
        "value": LocalizableInt(value: value)
    ] }

    var vmId: ViewModelId

    private let value: Int

    static func stub() -> Self { stub(value: 42) }

    static func stub(value: Int) -> Self {
        .init(vmId: .init(type: Self.self), value: value)
    }
}

/// Container with an array of ViewModels
private struct ArrayContainerViewModel: ViewModel {
    @LocalizedString var title
    let items: [SingleSubsViewModel]

    var vmId: ViewModelId

    static func stub() -> Self { stub(values: [1, 2, 3]) }

    static func stub(values: [Int]) -> Self {
        .init(
            items: values.map { .stub(value: $0) },
            vmId: .init()
        )
    }
}

/// Container with multiple arrays
private struct MultipleArraysViewModel: ViewModel {
    @LocalizedString var title
    let firstArray: [SingleSubsViewModel]
    let secondArray: [SingleSubsViewModel]

    var vmId: ViewModelId

    static func stub() -> Self {
        .init(
            firstArray: [.stub(value: 100), .stub(value: 101)],
            secondArray: [.stub(value: 200), .stub(value: 201)],
            vmId: .init()
        )
    }
}

/// Two levels of nesting
private struct TwoLevelNestingViewModel: ViewModel {
    @LocalizedString var title
    let child: SingleSubsViewModel

    var vmId: ViewModelId

    static func stub() -> Self { stub(innerValue: 42) }

    static func stub(innerValue: Int) -> Self {
        .init(child: .stub(value: innerValue), vmId: .init())
    }
}

/// Level 3 of nesting
private struct Level3ViewModel: ViewModel {
    @LocalizedSubs(substitutions: \.subs) var label

    var subs: [String: any Localizable] { [
        "value": LocalizableInt(value: value)
    ] }

    var vmId: ViewModelId

    private let value: Int

    static func stub() -> Self { stub(value: 42) }

    static func stub(value: Int) -> Self {
        .init(vmId: .init(type: Self.self), value: value)
    }
}

/// Level 2 of nesting
private struct Level2ViewModel: ViewModel {
    @LocalizedString var middleTitle
    let level3: Level3ViewModel

    var vmId: ViewModelId

    static func stub() -> Self { stub(deepValue: 42) }

    static func stub(deepValue: Int) -> Self {
        .init(level3: .stub(value: deepValue), vmId: .init())
    }
}

/// Three levels of nesting
private struct ThreeLevelNestingViewModel: ViewModel {
    @LocalizedString var title
    let level2: Level2ViewModel

    var vmId: ViewModelId

    static func stub() -> Self { stub(deepValue: 42) }

    static func stub(deepValue: Int) -> Self {
        .init(level2: .stub(deepValue: deepValue), vmId: .init())
    }
}

/// Mixed direct and array children
private struct MixedNestingViewModel: ViewModel {
    @LocalizedString var title
    let directChild: SingleSubsViewModel
    let arrayChildren: [SingleSubsViewModel]

    var vmId: ViewModelId

    static func stub() -> Self {
        .init(
            directChild: .stub(value: 1),
            arrayChildren: [.stub(value: 2), .stub(value: 3)],
            vmId: .init()
        )
    }
}

/// Two instances of the same ViewModel type as distinct properties
private struct DualInstanceViewModel: ViewModel {
    @LocalizedString var title
    let first: SingleSubsViewModel
    let second: SingleSubsViewModel

    var vmId: ViewModelId

    static func stub() -> Self {
        .init(
            first: .stub(value: 111),
            second: .stub(value: 222),
            vmId: .init()
        )
    }
}

/// For testing fallback behavior
private struct FallbackTestViewModel: ViewModel {
    @LocalizedString var title
    let child: SingleSubsViewModel

    var vmId: ViewModelId

    static func stub() -> Self {
        .init(child: .stub(value: 42), vmId: .init())
    }
}
