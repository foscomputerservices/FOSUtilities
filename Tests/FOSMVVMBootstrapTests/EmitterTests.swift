// EmitterTests.swift
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

struct EmitterTests {
    /// The token-scannable text of an emitted entry: a symlink's own target
    /// string (a link may point at a directory), a regular file's contents.
    func emittedText(_ out: URL, _ path: String) throws -> String {
        let full = out.appendingPathComponent(path).path
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: full) {
            return dest
        }
        return try String(contentsOf: URL(fileURLWithPath: full), encoding: .utf8)
    }

    func makeConfig() -> BootstrapConfig {
        BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .iOS: "17.0"]
        )
    }

    @Test func emitsSharedLibraryFileSet() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeConfig(), into: out)

        let expected = [
            "Package.swift",
            "CLAUDE.md",
            "README.md",
            ".swiftformat",
            "memory/MEMORY.md",
            "memory/spm-libraries-settled.md",
            "memory/stale-build-runbook.md",
            "memory/entitlement-is-a-symptom.md",
            "memory/macos-build-for-testing-faq.md",
            "memory/xcode16-dynamic-spm-packages.md",
            ".github/workflows/ci.yml",
            "Sources/PalettePressViewModels/PalettePressViewModels.swift",
            "Sources/PalettePressViewModels/ViewModels/WelcomeViewModel.swift",
            "Sources/PalettePressViewModels/ViewModels/WelcomeViewModelOperations.swift",
            "Sources/PalettePressViewModels/Resources/Localizations/ViewModels/WelcomeViewModel.yml",
            "Tests/PalettePressViewModelsTests/WelcomeViewModelTests.swift",
            "Tests/PalettePressViewModelsTests/LocalizableTestCase+PalettePress.swift"
        ]
        for path in expected {
            #expect(emitted.contains(path), "missing \(path)")
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(path).path))
        }
        #expect(Set(emitted) == Set(expected), "emitted set ≠ expected set")
    }

    @Test func emittedFilesContainNoTokens() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeConfig(), into: out)
        for path in emitted {
            let content = try emittedText(out, path)
            #expect(!content.contains("{{"), "unrendered token in \(path)")
        }
    }

    @Test func refusesNonEmptyOutputDirectory() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: out.appendingPathComponent("existing.txt").path,
            contents: Data("x".utf8)
        )
        defer { try? FileManager.default.removeItem(at: out) }

        #expect(throws: EmitterError.outputDirectoryNotEmpty(out.path)) {
            _ = try Emitter.emit(config: makeConfig(), into: out)
        }
    }

    func makeLocalOnlyConfig() -> BootstrapConfig {
        BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
    }

    @Test func emitsLocalOnlyFileSet() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeLocalOnlyConfig(), into: out)

        let expected = [
            "project.yml",
            "README.md",
            "Sources/SPMLibraries/SPMLibraries.swift",
            "Sources/ViewModels/ViewModelsResourceAccess.swift",
            "Sources/ViewModels/ViewModels/WelcomeViewModel.swift",
            "Sources/ViewModels/ViewModels/WelcomeViewModelOperations.swift",
            "Sources/ViewModels/Resources/ViewModels/WelcomeViewModel.yml",
            "Sources/ViewModels/Versioning/SystemVersion+App.swift",
            "Sources/PalettePress/App/PalettePressApp.swift",
            "Sources/PalettePress/App/TestConfiguration.swift",
            "Sources/PalettePress/Views/WelcomeView.swift",
            "Sources/PalettePress/Info.plist",
            "Sources/PalettePress/PalettePress.entitlements",
            "Tests/PalettePressUnitTests/ViewModels/WelcomeViewModelTests.swift",
            "Tests/PalettePressUnitTests/LocalizableTestCase+PalettePress.swift",
            "Tests/PalettePressUITests/Support/PalettePressViewModelViewTestCase.swift",
            "Tests/PalettePressUITests/Support/PalettePressViewModelDisplayTestCase.swift",
            "Tests/PalettePressUITests/PalettePressUITests.swift",
            "Tests/PalettePressUITests/Views/WelcomeViewTests.swift",
            "Tests/PalettePressUITests/Support/LocalizableTestCase+PalettePress.swift",
            "Tests/PalettePressUITests/Support/TestConfiguration.swift", // symlink → the app's copy
            // shared doctrine set
            "CLAUDE.md",
            ".swiftformat",
            "memory/MEMORY.md",
            "memory/spm-libraries-settled.md",
            "memory/stale-build-runbook.md",
            "memory/entitlement-is-a-symptom.md",
            "memory/macos-build-for-testing-faq.md",
            "memory/xcode16-dynamic-spm-packages.md"
        ]
        for path in expected {
            #expect(emitted.contains(path), "missing \(path)")
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(path).path))
        }
        #expect(Set(emitted) == Set(expected), "emitted set ≠ expected set")
    }

    @Test func localOnlyEmissionContainsNoTokens() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeLocalOnlyConfig(), into: out)
        for path in emitted {
            let content = try emittedText(out, path)
            #expect(!content.contains("{{"), "unrendered token in \(path)")
        }
    }

    func makeClientServerConfig() -> BootstrapConfig {
        BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
    }

    @Test func emitsClientServerFileSet() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeClientServerConfig(), into: out)

        let expected = [
            "Package.swift",
            "project.yml",
            "PalettePress.xctestplan",
            // shared contract (SPM lib + source-included into the app)
            "Sources/PalettePressViewModels/ViewModels/BoardViewModel.swift",
            "Sources/PalettePressViewModels/ViewModels/BoardViewModelOperations.swift",
            "Sources/PalettePressViewModels/ViewModels/CardViewModel.swift",
            "Sources/PalettePressViewModels/Requests/BoardRequest.swift",
            "Sources/PalettePressViewModels/Requests/CreateCardRequest.swift",
            // shared foundation — version handshake for both the app and the server
            "Sources/PalettePressFoundation/SystemVersion+App.swift",
            // server-hosted YAML
            "Sources/Resources/ViewModels/BoardViewModel.yml",
            // Vapor server (Fluent)
            "Sources/PalettePressServer/entrypoint.swift",
            "Sources/PalettePressServer/configure.swift",
            "Sources/PalettePressServer/routes.swift",
            "Sources/PalettePressServer/DataModels/Board.swift",
            "Sources/PalettePressServer/DataModels/Card.swift",
            "Sources/PalettePressServer/Migrations/Board+Schema.swift",
            "Sources/PalettePressServer/Migrations/Card+Schema.swift",
            "Sources/PalettePressServer/Factories/BoardViewModel+Factory.swift",
            "Sources/PalettePressServer/Writers/CreateCardRequest+Writer.swift",
            "Sources/PalettePressServer/Auth/SkeletonAuthProvider.swift",
            // umbrella (Xcode-only)
            "Sources/SPMLibraries/SPMLibraries.swift",
            // client-hosted framework (Xcode-only)
            "Sources/PalettePressClientViewModels/PalettePressClientViewModels.swift",
            "Sources/PalettePressClientViewModels/AboutViewModel.swift",
            "Sources/PalettePressClientViewModels/AboutViewModelOperations.swift",
            "Sources/PalettePressClientViewModels/Resources/ViewModels/AboutViewModel.yml",
            // app (Xcode-only)
            "Sources/PalettePress/App/PalettePressApp.swift",
            "Sources/PalettePress/App/TestConfiguration.swift",
            "Sources/PalettePress/Views/BoardView.swift",
            "Sources/PalettePress/Views/AboutView.swift",
            "Sources/PalettePress/Correlation.swift",
            "Sources/PalettePress/Info.plist",
            "Sources/PalettePress/PalettePress.entitlements",
            // tests
            "Tests/PalettePressViewModelsTests/BoardViewModelTests.swift",
            "Tests/PalettePressViewModelsTests/LocalizableTestCase+PalettePress.swift",
            "Tests/PalettePressServerTests/BoardServerTests.swift",
            "Tests/PalettePressUnitTests/PalettePressUnitTests.swift",
            "Tests/PalettePressClientViewModelsTests/AboutViewModelTests.swift",
            "Tests/PalettePressClientViewModelsTests/LocalizableTestCase+PalettePress.swift",
            "Tests/PalettePressUITests/Resources", // symlink → the server YAML tree (harness merged store)
            "Tests/PalettePressUITests/PalettePressUITests.swift",
            "Tests/PalettePressUITests/Support/PalettePressViewModelViewTestCase.swift",
            "Tests/PalettePressUITests/Support/PalettePressViewModelDisplayTestCase.swift",
            "Tests/PalettePressUITests/Support/LocalizableTestCase+PalettePress.swift",
            "Tests/PalettePressUITests/Support/TestConfiguration.swift", // symlink → the app's copy
            "Tests/PalettePressUITests/Views/AboutViewTests.swift",
            "Tests/PalettePressUITests/Views/BoardViewTests.swift",
            "README.md",
            // shared doctrine set
            "CLAUDE.md",
            ".swiftformat",
            "memory/MEMORY.md",
            "memory/spm-libraries-settled.md",
            "memory/stale-build-runbook.md",
            "memory/entitlement-is-a-symptom.md",
            "memory/macos-build-for-testing-faq.md",
            "memory/xcode16-dynamic-spm-packages.md"
        ]
        for path in expected {
            #expect(emitted.contains(path), "missing \(path)")
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(path).path))
        }
        #expect(Set(emitted) == Set(expected), "emitted set ≠ expected set")
    }

    @Test func clientServerEmissionContainsNoTokens() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let emitted = try Emitter.emit(config: makeClientServerConfig(), into: out)
        for path in emitted {
            let content = try emittedText(out, path)
            #expect(!content.contains("{{"), "unrendered token in \(path)")
        }
    }

    @Test func refusesShapeWithoutTemplates() throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }

        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .hybrid,
            platforms: [.macOS: "14.0"]
        )
        #expect(throws: EmitterError.shapeNotImplemented("hybrid")) {
            _ = try Emitter.emit(config: config, into: out)
        }
        // Nothing may be written before the guard fires.
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
