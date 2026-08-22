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

    @Test func destinationsFollowThePlatformsMap() throws {
        // macOS-only: the Xcode surface stays Mac-only.
        let macOnly = try TokenSet.derive(from: BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        ))
        #expect(macOnly["SUPPORTED_DESTINATIONS"] == "[macOS]")
        #expect(macOnly["DEPLOYMENT_TARGETS"] == "\n    macOS: \"14.0\"")
        #expect(macOnly["DEVICE_FAMILY_OVERRIDE"] == "")
        #expect(macOnly["XR_COMPAT_OVERRIDE"] == "")

        // Asking for iOS adds the iPhone destinations and its deployment floor.
        let withIOS = try TokenSet.derive(from: BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0", .iOS: "17.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        ))
        #expect(withIOS["SUPPORTED_DESTINATIONS"] == "[macOS, iOS]")
        #expect(withIOS["DEPLOYMENT_TARGETS"] == "\n    macOS: \"14.0\"\n    iOS: \"17.0\"")
        #expect(withIOS["DEVICE_FAMILY_OVERRIDE"] == "\n        TARGETED_DEVICE_FAMILY: \"1,2\"")
        #expect(withIOS["XR_COMPAT_OVERRIDE"] == "")

        // iPhone-only, with TV and Vision: families compose; XR compat stands.
        let kitchenSink = try TokenSet.derive(from: BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0", .iOS: "17.0", .tvOS: "17.0", .visionOS: "1.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345",
            iosDevices: ["iPhone"]
        ))
        #expect(kitchenSink["SUPPORTED_DESTINATIONS"] == "[macOS, iOS, tvOS, visionOS]")
        #expect(kitchenSink["DEVICE_FAMILY_OVERRIDE"] == "\n        TARGETED_DEVICE_FAMILY: \"1,3,7\"")
        #expect(kitchenSink["XR_COMPAT_OVERRIDE"] == "")

        // Explicit declines emit the compat opt-outs; omitted means allowed.
        let declined = try TokenSet.derive(from: BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.iOS: "17.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345",
            macDesignedForIPad: false,
            visionDesignedForIPad: false
        ))
        #expect(declined["XR_COMPAT_OVERRIDE"] ==
            "\n        SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO"
            + "\n        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO")

        // No Mac, no explicit compat answers: iOS-only destinations, and the
        // compat modes stay at Apple's default (allowed — no overrides).
        let noMac = try TokenSet.derive(from: BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.iOS: "17.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        ))
        #expect(noMac["SUPPORTED_DESTINATIONS"] == "[iOS]")
        #expect(noMac["XR_COMPAT_OVERRIDE"] == "")

        // Watch: frameworks gain the destination; the app target does NOT
        // (separate watch target instead, emitted via WATCH_TARGET).
        let withWatch = try TokenSet.derive(from: BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0", .iOS: "17.0", .watchOS: "10.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        ))
        #expect(withWatch["SUPPORTED_DESTINATIONS"] == "[macOS, iOS]")
        #expect(withWatch["FRAMEWORK_DESTINATIONS"] == "[macOS, iOS, watchOS]")
        #expect(withWatch["WATCH_TARGET"]?.contains("PalettePressWatch:") == true)
        #expect(withWatch["WATCH_SCHEME"]?.contains("PalettePressWatch:") == true)
        #expect(withWatch["DEPLOYMENT_TARGETS"]?.contains("watchOS: \"10.0\"") == true)
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
