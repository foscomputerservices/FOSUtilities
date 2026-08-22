import FOSMVVMBootstrap
import Foundation
import Testing

@Suite struct VerifierTests {
    /// Writes a minimal valid SPM package to a temp dir.
    func writeTinyPackage(brokenSource: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Sources/Tiny"),
            withIntermediateDirectories: true
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Tiny", targets: [.target(name: "Tiny")])
        """.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try (brokenSource ? "let x: Int = \"nope\"" : "let x = 1")
            .write(to: dir.appendingPathComponent("Sources/Tiny/Tiny.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func passesOnBuildableProject() throws {
        let dir = try writeTinyPackage(brokenSource: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Verifier.verify(projectDir: dir, steps: [.swiftBuild])
    }

    @Test func failsWithCapturedOutputOnBrokenProject() throws {
        let dir = try writeTinyPackage(brokenSource: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try Verifier.verify(projectDir: dir, steps: [.swiftBuild])
            Issue.record("expected verification failure")
        } catch let error as VerifierError {
            guard case let .stepFailed(step, output) = error else {
                Issue.record("wrong error: \(error)"); return
            }
            #expect(step == .swiftBuild)
            #expect(output.contains("error:"))
            // The CustomStringConvertible rendering must name the failed
            // command, so an ArgumentParser dump reads as a legible block.
            #expect(String(describing: error).contains("swift build"))
        }
    }

    @Test func localOnlyStepsAreXcodeSteps() {
        #expect(Verifier.generationSteps(for: .localOnly) == [.xcodegenGenerate])
        #expect(Verifier.steps(for: .localOnly) == [.xcodebuildBuild])
    }

    @Test func clientServerStepsAreTheFourDoorSteps() {
        #expect(Verifier.generationSteps(for: .clientServer) == [.xcodegenGenerate])
        #expect(Verifier.steps(for: .clientServer)
            == [.swiftBuild, .swiftTest, .xcodebuildBuild])
    }

    @Test func missingToolThrowsToolMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try Verifier.verify(
                projectDir: dir,
                steps: [.xcodegenGenerate],
                environment: ["PATH": "/nonexistent"]
            )
            Issue.record("expected toolMissing")
        } catch let error as VerifierError {
            guard case let .toolMissing(tool, _) = error else {
                Issue.record("wrong error: \(error)"); return
            }
            #expect(tool == "xcodegen")
        }
    }
}
