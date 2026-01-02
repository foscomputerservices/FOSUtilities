// LocalizablePropertyTests.swift
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
@testable import FOSMVVM
import FOSTesting
import Foundation
import Testing

@Suite("Localizable Property Tests")
struct LocalizablePropertyTests: LocalizableTestCase {
    @Test func localizedString_basic() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedString.localizedString == "Some Text")
    }

    @Test func localizedString_parentKey() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.title.localizedString == "Title")
        let aFieldTitle = try vm.aFieldTitle.localizedString
        #expect(try vm.title.localizedString == aFieldTitle)
        #expect(try vm.error1.localizedString == "Error #1")
        #expect(try vm.error2.localizedString == "Error #2")
    }

    @Test func localizedString_index() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm1: TestViewModel = .init()
        let json = try vm1.toJSON(encoder: vmEncoder)
        let vm: TestViewModel = try json.fromJSON()

        #expect(try vm.firstPiece.localizedString == "Piece #1")
    }

    @Test func localizedInt() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedInt.localizedString == "42")
    }

    @Test func localizedPieces() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.pieces.localizedArray.count == 2)
        #expect(try vm.pieces.localizedArray[safe: 0] == "Piece #1")
        #expect(try vm.pieces.localizedArray[safe: 1] == "Piece #2")
    }

    @Test func localizedCompoundString_noSep() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedCompoundNoSep.localizedString == "Piece #1Piece #2")
    }

    @Test func localizedCompoundString_sep() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: TestViewModel = try .init().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.aLocalizedCompoundSep.localizedString == "Piece #1*Piece #2")
    }

    @Test func localizedPropertyWrapperKeyMissing() async throws {
        // Unable to retrieve the current ViewModel for property name lookup
        let wrapper = _LocalizedProperty<TestViewModel, LocalizableString>(
            parentKey: "missing"
        )

        #expect(throws: LocalizedPropertyError.self) {
            try JSONEncoder().encode(wrapper)
        }
    }

    // MARK: - Error Path Tests

    @Test func encode_withPlainEncoder_throwsLocalizationStoreMissing() throws {
        // Using plain JSONEncoder without localization configuration should throw
        let locString = LocalizableString.localized(key: "TestViewModel.aLocalizedString")

        #expect(throws: LocalizerError.self) {
            _ = try locString.toJSON(encoder: JSONEncoder())
        }
    }

    @Test func encode_localizableDate_withPlainEncoder_throwsLocalizationStoreMissing() throws {
        let locDate = LocalizableDate(value: Date())

        #expect(throws: LocalizerError.self) {
            _ = try locDate.toJSON(encoder: JSONEncoder())
        }
    }

    @Test func encode_localizableInt_withPlainEncoder_throwsLocalizationStoreMissing() throws {
        let locInt = LocalizableInt(value: 42)

        #expect(throws: LocalizerError.self) {
            _ = try locInt.toJSON(encoder: JSONEncoder())
        }
    }

    // MARK: - Encoder State Management Tests

    @Test func encoderReuse_multipleViewModels_freshEncoders() throws {
        // Using fresh encoders for each ViewModel should work correctly
        let vmEncoder1 = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vmEncoder2 = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)

        // Each encode with its own fresh encoder
        let vm1: ErrorPathTestViewModel = try .stub(value: 100)
            .toJSON(encoder: vmEncoder1)
            .fromJSON()

        let vm2: ErrorPathTestViewModel = try .stub(value: 200)
            .toJSON(encoder: vmEncoder2)
            .fromJSON()

        // Each should have its own value
        #expect(try vm1.label.localizedString == "Value: 100")
        #expect(try vm2.label.localizedString == "Value: 200")
    }

    @Test func nestedEncode_propertyNamesRestored() throws {
        // After encoding a nested ViewModel, the parent's property names should be restored
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)

        // Parent with nested children
        let parent: NestedPropertyTestViewModel = try .stub()
            .toJSON(encoder: vmEncoder)
            .fromJSON()

        // Parent's own localized property should still work after nested encoding
        #expect(try parent.parentLabel.localizedString == "Parent Label")
        // Nested child's property should also work
        #expect(try parent.child.label.localizedString == "Value: 42")
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

extension String {
    static var localized: String {
        ""
    }
}

// MARK: - Test ViewModels for Error Path Tests

private struct ErrorPathTestViewModel: ViewModel {
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

    func propertyNames() -> [LocalizableId: String] {
        [_label.localizationId: "label"]
    }
}

private struct NestedPropertyTestViewModel: ViewModel {
    @LocalizedString var parentLabel
    let child: ErrorPathTestViewModel

    var vmId: ViewModelId

    static func stub() -> Self {
        .init(child: .stub(value: 42), vmId: .init())
    }

    func propertyNames() -> [LocalizableId: String] {
        [_parentLabel.localizationId: "parentLabel"]
    }
}
