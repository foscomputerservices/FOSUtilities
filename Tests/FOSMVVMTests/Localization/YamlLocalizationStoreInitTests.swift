// YamlLocalizationStoreInitTests.swift
//
// Created by David Hunt on 6/21/24
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
@testable import FOSMVVM
import Foundation
import Testing
import Vapor

@Suite("YamlLocalizationStore Initialization Tests")
struct YamlLocalizationStoreInitTests {
    @Test func testYamlStoreConfig() {
        let paths = paths
        let config = YamlStoreConfig(searchPaths: paths)
        #expect(config.searchPaths.count == paths.count)
    }

    @Test func testYamlStoreInit() {
        let app = Application()
        app.initYamlLocalization(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
        app.shutdown()
    }
}

private extension YamlLocalizationStoreInitTests {
    var paths: Set<URL> {
        let paths = Bundle.module.paths(forResourcesOfType: "yml", inDirectory: "TestYAML").map {
            URL(fileURLWithPath: $0).deletingLastPathComponent()
        }

        return Set(paths)
    }
}
