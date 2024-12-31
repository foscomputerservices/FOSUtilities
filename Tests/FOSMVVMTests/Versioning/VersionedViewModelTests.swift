// VersionedViewModelTests.swift
//
// Created by David Hunt on 12/31/24
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

import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Testing

@Suite("Versioned ViewModel Tests")
struct VersionedViewModelTests: LocalizableTestCase {
    @Test func simple() throws {
        try expectVersionedViewModel(TestVersionedViewModel.self, encoder: encoder)
    }

    let locStore: LocalizationStore
    var locales: Set<Locale> { [Self.en, Self.es] }
    var encoder: JSONEncoder {
        .localizingEncoder(locale: Self.en, localizationStore: locStore)
    }

    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
