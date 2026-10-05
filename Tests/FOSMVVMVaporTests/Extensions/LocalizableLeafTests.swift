// LocalizableLeafTests.swift
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
import FOSMVVMVapor
import FOSTesting
import FOSTestingVapor
import Foundation
import Testing
import Vapor

struct LocalizableLeafTests: LocalizableTestCase {
    @Test func localizableCase_rendersItsWord() async throws {
        let app = try await vaporApplication()
        defer { Task {
            try await app.asyncShutdown()
        }}
        let encoder = try await vaporRequest(application: app, locale: Self.es).localizingEncoder

        let localized: LocalizableCase<Priority> = try LocalizableCase(Priority.high)
            .toJSON(encoder: encoder)
            .fromJSON()

        #expect(localized.leafData.string == "Alta")
    }

    @Test func localizableCase_unlocalized_rendersEmpty() {
        #expect(LocalizableCase(Priority.high).leafData.string == "")
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private enum Priority: CaseIterable, Codable, Hashable {
    case low
    case high
}
