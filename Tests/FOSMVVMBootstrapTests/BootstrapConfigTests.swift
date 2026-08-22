import FOSMVVMBootstrap
import Foundation
import Testing

@Suite struct BootstrapConfigTests {
    @Test func decodesSharedLibraryConfig() throws {
        let json = """
        {
          "projectName": "PalettePress",
          "shape": "sharedLibrary",
          "platforms": { "macOS": "14.0", "iOS": "17.0" }
        }
        """
        let config = try JSONDecoder().decode(BootstrapConfig.self, from: Data(json.utf8))
        #expect(config.projectName == "PalettePress")
        #expect(config.shape == .sharedLibrary)
        #expect(config.platforms[.macOS] == "14.0")
    }

    @Test func rejectsInvalidProjectName() throws {
        let config = BootstrapConfig(
            projectName: "Palette Press!",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        #expect(throws: BootstrapConfigError.invalidProjectName("Palette Press!")) {
            try config.validate()
        }
    }

    @Test func validSharedLibraryConfigPasses() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .sharedLibrary,
            platforms: [.macOS: "14.0"]
        )
        try config.validate()
    }

    @Test func localOnlyRequiresBundleIdRootAndTeam() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"]
        )
        #expect(throws: BootstrapConfigError.missingBundleIdRoot) {
            try config.validate()
        }
    }

    @Test func validLocalOnlyConfigPasses() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try config.validate()
    }

    @Test func rejectsMalformedTeamId() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .localOnly,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "abc"
        )
        #expect(throws: BootstrapConfigError.invalidTeamId("abc")) {
            try config.validate()
        }
    }

    @Test func appShapesRequireAtLeastOneAppDestination() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.watchOS: "10.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        #expect(throws: BootstrapConfigError.noAppDestinations) {
            try config.validate()
        }
    }

    @Test func validClientServerConfigPasses() throws {
        let config = BootstrapConfig(
            projectName: "PalettePress",
            shape: .clientServer,
            platforms: [.macOS: "14.0"],
            bundleIdRoot: "com.example.palettepress",
            teamId: "ABCDE12345"
        )
        try config.validate()
    }
}
