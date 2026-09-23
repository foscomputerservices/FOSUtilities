// EmitterAssetTests.swift
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

/// The asset catalog every app shape ships, and the icon slots that follow
/// the config's platforms.
struct EmitterAssetTests {
    private func emit(_ config: BootstrapConfig) throws -> (root: URL, paths: [String]) {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("emit-assets-\(UUID().uuidString)")
        let paths = try Emitter.emit(config: config, into: out)
        return (out, paths)
    }

    private func appConfig(shape: ProjectShape, platforms: [TargetPlatform: String]) -> BootstrapConfig {
        BootstrapConfig(
            projectName: "PalettePress",
            shape: shape,
            platforms: platforms,
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
    }

    /// The `images` entries of the emitted `AppIcon.appiconset`, decoded —
    /// the contract is a set of slots, not a byte layout.
    private func iconSlots(in root: URL) throws -> [[String: Any]] {
        let url = root.appendingPathComponent("Sources/PalettePress/Assets.xcassets/AppIcon.appiconset/Contents.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(json?["images"] as? [[String: Any]])
    }

    @Test("a macOS-only app gets the ten mac slots and nothing else")
    func macOnlySlots() throws {
        let (root, _) = try emit(appConfig(shape: .localOnly, platforms: [.macOS: "14.0"]))
        defer { try? FileManager.default.removeItem(at: root) }

        let slots = try iconSlots(in: root)
        #expect(slots.count == 10)
        #expect(slots.allSatisfy { $0["idiom"] as? String == "mac" })
    }

    @Test("iOS contributes the light, dark and tinted 1024 slots; watchOS its own")
    func iOSAndWatchSlots() throws {
        let (root, _) = try emit(appConfig(
            shape: .clientServer,
            platforms: [.macOS: "14.0", .iOS: "17.0", .watchOS: "10.0"]
        ))
        defer { try? FileManager.default.removeItem(at: root) }

        let slots = try iconSlots(in: root)
        let ios = slots.filter { $0["platform"] as? String == "ios" }
        #expect(ios.count == 3)
        #expect(ios.filter { $0["appearances"] == nil }.count == 1)
        #expect(slots.filter { $0["platform"] as? String == "watchos" }.count == 1)
        #expect(slots.count == 14)
    }

    @Test("visionOS adds the layered icon stack; without it the stack is absent")
    func visionStackFollowsThePlatform() throws {
        let stack = "Sources/PalettePress/Assets.xcassets/AppIcon.solidimagestack/Contents.json"

        let (withVision, visionPaths) = try emit(appConfig(
            shape: .localOnly,
            platforms: [.macOS: "14.0", .visionOS: "1.0"]
        ))
        defer { try? FileManager.default.removeItem(at: withVision) }
        #expect(visionPaths.contains(stack))
        #expect(visionPaths.filter { $0.contains("AppIcon.solidimagestack/") }.count == 7)

        let (without, plainPaths) = try emit(appConfig(shape: .localOnly, platforms: [.macOS: "14.0"]))
        defer { try? FileManager.default.removeItem(at: without) }
        #expect(!plainPaths.contains(stack))
    }

    @Test("a shared library declaring visionOS receives no app folder")
    func sharedLibraryHasNoCatalog() throws {
        let (root, paths) = try emit(BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .visionOS: "1.0"]
        ))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!paths.contains { $0.contains("xcassets") })
    }

    @Test("the accent colour and the catalog root ride with every app shape")
    func catalogRootAndAccent() throws {
        for shape in [ProjectShape.localOnly, .clientServer] {
            let (root, paths) = try emit(appConfig(shape: shape, platforms: [.macOS: "14.0"]))
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(paths.contains("Sources/PalettePress/Assets.xcassets/Contents.json"), "\(shape)")
            #expect(paths.contains("Sources/PalettePress/Assets.xcassets/AccentColor.colorset/Contents.json"), "\(shape)")
        }
    }
}
