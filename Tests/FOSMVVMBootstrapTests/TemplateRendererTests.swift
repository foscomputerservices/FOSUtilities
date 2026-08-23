import FOSMVVMBootstrap
import Foundation
import Testing

@Suite struct TemplateRendererTests {
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
