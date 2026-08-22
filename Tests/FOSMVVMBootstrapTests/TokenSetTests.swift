import FOSMVVMBootstrap
import Testing

@Suite struct TokenSetTests {
    @Test func derivesSharedLibraryTokens() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0", .iOS: "17.0"]
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["PROJECT_NAME"] == "PalettePress")
        #expect(tokens["FOS_VERSION"] == FOSPlatformFloor.pinnedFOSVersion)
        // platforms render deterministically (alphabetical by platform name)
        #expect(tokens["PLATFORMS"] == ".iOS(\"17.0\"),\n        .macOS(\"14.0\")")
    }

    @Test func defaultLicenseHeaderIsEmpty() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["LICENSE_HEADER"] == "")
    }

    @Test func derivesLocalOnlyTokens() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["BUNDLE_ID_ROOT"] == "com.example.palettepress")
        #expect(tokens["TEAM_ID"] == "ABCDE12345")
        #expect(tokens["MACOS_DEPLOYMENT"] == "14.0")
    }

    @Test func derivesClientServerTokens() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["BUNDLE_ID_ROOT"] == "com.example.palettepress")
        #expect(tokens["TEAM_ID"] == "ABCDE12345")
        #expect(tokens["MACOS_DEPLOYMENT"] == "14.0")
    }

    @Test func sharedLibraryTokensUnchanged() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        let tokens = try TokenSet.derive(from: config)
        #expect(tokens["BUNDLE_ID_ROOT"] == nil)
        #expect(tokens.count == 4)
    }
}
