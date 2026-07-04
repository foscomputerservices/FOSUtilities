// LocalizedDateTests.swift
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

struct LocalizedDateTests: LocalizableTestCase {
    // MARK: - Wrapper Init Tests

    @Test func wrapperInitPassesThrough() {
        let vm = DateTestViewModel()

        #expect(vm.shortStyled.value == fixedTestDate)
        #expect(vm.shortStyled.dateStyle == .short)
        #expect(vm.shortStyled.timeStyle == .short)
        #expect(vm.shortStyled.dateFormat == nil)

        // A time style alone suppresses the .medium date-style default
        #expect(vm.timeOnly.timeStyle == .short)
        #expect(vm.timeOnly.dateStyle == nil)
        #expect(vm.timeOnly.dateFormat == nil)

        #expect(vm.isoFormatted.value == fixedTestDate)
        #expect(vm.isoFormatted.dateFormat == "yyyy-MM-dd")
        // A fixed format suppresses the style default (LocalizableDate's rule)
        #expect(vm.isoFormatted.dateStyle == nil)
    }

    @Test func defaultStyle_mediumFromLocalizableDate() {
        let vm = DateTestViewModel()

        // No style args → LocalizableDate's .medium default applies
        #expect(vm.defaultStyled.dateStyle == .medium)
        #expect(vm.defaultStyled.timeStyle == nil)
        #expect(vm.defaultStyled.dateFormat == nil)
    }

    // MARK: - Codable Round-Trip Tests

    @Test func codable_localizesPerLocale() throws {
        let enEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let enVM: DateTestViewModel = try DateTestViewModel().toJSON(encoder: enEncoder).fromJSON()

        let esEncoder = JSONEncoder.localizingEncoder(locale: es, localizationStore: locStore)
        let esVM: DateTestViewModel = try DateTestViewModel().toJSON(encoder: esEncoder).fromJSON()

        // Medium style in en contains the abbreviated month "Jul"
        let enResult = try enVM.defaultStyled.localizedString
        #expect(enResult.contains("Jul"))

        // Spanish renders the month differently (lowercase "jul")
        let esResult = try esVM.defaultStyled.localizedString
        #expect(esResult.contains("jul"))
        #expect(enResult != esResult)
    }

    @Test func codable_roundTripPreservesValueAndStatus() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: DateTestViewModel = try DateTestViewModel().toJSON(encoder: vmEncoder).fromJSON()

        #expect(vm.defaultStyled.value == fixedTestDate)
        #expect(vm.defaultStyled.localizationStatus == .localized)
        #expect(try vm.isoFormatted.localizedString.starts(with: "2024-07-0"))
    }

    // MARK: - Versioning Tests

    @Test func versioning_flowsThroughToWrapper() {
        let versioned = DateTestViewModel.LocalizedDate(
            value: fixedTestDate,
            vFirst: .v2_0_0,
            vLast: .v3_0_0
        )
        #expect(versioned.vFirst == .v2_0_0)
        #expect(versioned.vLast == .v3_0_0)

        let unversioned = DateTestViewModel.LocalizedDate(value: fixedTestDate)
        #expect(unversioned.vFirst == .vInitial)
        #expect(unversioned.vLast == nil)
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

// MARK: - Test ViewModel

/// Fixed date for consistent testing: 2024-07-03 08:46:40 UTC
private let fixedTestDate = Date(timeIntervalSince1970: 1720000000)

@ViewModel
private struct DateTestViewModel {
    @LocalizedDate(value: fixedTestDate) var defaultStyled
    @LocalizedDate(value: fixedTestDate, dateStyle: .short, timeStyle: .short) var shortStyled
    @LocalizedDate(value: fixedTestDate, timeStyle: .short) var timeOnly
    @LocalizedDate(value: fixedTestDate, dateFormat: "yyyy-MM-dd") var isoFormatted

    var vmId = ViewModelId()

    static func stub() -> Self {
        .init()
    }
}
