import Foundation
@testable import FOSMVVMBootstrap
import Testing

@Suite struct FOSPlatformFloorTests {
    @Test func atFloorPasses() throws {
        try FOSPlatformFloor.validate(platforms: [.macOS: "14.0", .iOS: "17.0"])
    }

    @Test func aboveFloorPasses() throws {
        try FOSPlatformFloor.validate(platforms: [.macOS: "26.0"])
    }

    @Test func belowFloorThrows() {
        #expect(throws: BootstrapConfigError.belowFOSFloor(platform: .macOS, asked: "13.0", floor: "14.0")) {
            try FOSPlatformFloor.validate(platforms: [.macOS: "13.0"])
        }
    }

    @Test func minorVersionComparesNumerically() {
        // "10.4" < "10.15" numerically even though it sorts *after* lexically —
        // this is the case a lexical-compare regression would get wrong.
        #expect(FOSPlatformFloor.compareVersions("10.4", "10.15") == .orderedAscending)
        // A missing component defaults to 0, so "14" and "14.0" are equal.
        #expect(FOSPlatformFloor.compareVersions("14", "14.0") == .orderedSame)
    }
}
