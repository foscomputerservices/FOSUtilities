// TemplateRendererTests.swift
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

import FOSMVVMBootstrap
import Foundation
import Testing

struct TemplateRendererTests {
    let tokens = ["PROJECT_NAME": "PalettePress", "FOS_VERSION": "0.10.0"]

    @Test func substitutesTokensInContent() throws {
        let out = try TemplateRenderer.render(
            content: "let name = \"{{PROJECT_NAME}}\" // needs {{FOS_VERSION}}",
            tokens: tokens
        )
        #expect(out == "let name = \"PalettePress\" // needs 0.10.0")
    }

    @Test func unrenderedTokenIsFatal() {
        #expect(throws: TemplateError.unrenderedToken(token: "{{TEAM_ID}}", context: "id: {{TEAM_ID}}")) {
            _ = try TemplateRenderer.render(content: "id: {{TEAM_ID}}", tokens: tokens)
        }
    }

    @Test func rendersPathsAndStripsTmplSuffix() throws {
        let path = try TemplateRenderer.render(
            relativePath: "Sources/{{PROJECT_NAME}}ViewModels/Package.swift.tmpl",
            tokens: tokens
        )
        #expect(path == "Sources/PalettePressViewModels/Package.swift")
    }
}
