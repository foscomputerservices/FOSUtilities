// Verifier.swift
import Foundation

public enum VerifyStep: String, Sendable, CaseIterable {
    case swiftBuild
    case swiftTest
    case xcodegenGenerate
    case xcodebuildBuild

    /// The command to run for this step. `xcodebuildBuild` names the
    /// generated project and scheme, so it needs the project name; a nil
    /// name renders as the `<project>` placeholder (used by the error
    /// description, which must never crash).
    func command(projectName: String?, destination: String = "platform=macOS") -> [String] {
        switch self {
        case .swiftBuild: return ["swift", "build"]
        case .swiftTest: return ["swift", "test"]
        case .xcodegenGenerate: return ["xcodegen", "generate", "--spec", "project.yml"]
        case .xcodebuildBuild:
            let name = projectName ?? "<project>"
            return [
                "xcodebuild",
                "-project", "\(name).xcodeproj",
                "-scheme", name,
                "-destination", destination,
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        }
    }

    /// A CLI tool this step depends on that isn't part of the toolchain,
    /// paired with how to install it. When set, `verify` probes for the
    /// tool before running the step and throws `.toolMissing` on absence.
    var requiredTool: (tool: String, installHint: String)? {
        switch self {
        case .xcodegenGenerate: return ("xcodegen", "brew install xcodegen")
        case .swiftBuild, .swiftTest, .xcodebuildBuild: return nil
        }
    }
}

public enum VerifierError: Error {
    case stepFailed(step: VerifyStep, output: String)
    case toolMissing(tool: String, installHint: String)
}

extension VerifierError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .stepFailed(step, output):
            // Render with a nil project name (`<project>` placeholder) so
            // the description can never crash on a name it doesn't carry.
            return "verification step '\(step.command(projectName: nil).joined(separator: " "))' failed:\n\(output)"
        case let .toolMissing(tool, installHint):
            return "required tool '\(tool)' not found on PATH — install it with: \(installHint)"
        }
    }
}

/// Runs the shape's verification steps inside the generated project.
/// A failure is fatal and carries the tool output — the scaffolder
/// never hands over a broken skeleton.
public enum Verifier {
    /// The xcodebuild destination for a config's verify door: macOS when the
    /// project has it, else the first simulator platform the config asked for.
    public static func buildDestination(for config: BootstrapConfig) -> String {
        if config.platforms[.macOS] != nil { return "platform=macOS" }
        if config.platforms[.iOS] != nil { return "generic/platform=iOS Simulator" }
        if config.platforms[.tvOS] != nil { return "generic/platform=tvOS Simulator" }
        if config.platforms[.visionOS] != nil { return "generic/platform=visionOS Simulator" }
        return "platform=macOS"
    }

    /// Steps that PRODUCE part of the project. `xcodegen` writes the
    /// `.xcodeproj` from the emitted `project.yml` — it is generation, not
    /// verification, so it runs even under `--skip-verify` (a skipped
    /// verification must never mean a missing deliverable; found live
    /// 2026-08-22 when `--skip-verify` produced a project with no
    /// `.xcodeproj`).
    public static func generationSteps(for shape: ProjectShape) -> [VerifyStep] {
        switch shape {
        case .sharedLibrary: []
        case .localOnly, .clientServer: [.xcodegenGenerate]
        case .hybrid: []
        }
    }

    /// Steps that CHECK the produced project. shared-library: build + test
    /// is the entire finish line. local-only builds the generated Xcode
    /// project. client-server checks both doors: the package (server boots +
    /// serves the route headlessly under `swift test`) and the app
    /// (xcodebuild). hybrid keeps the placeholder until Plan 4.
    public static func steps(for shape: ProjectShape) -> [VerifyStep] {
        switch shape {
        case .sharedLibrary: [.swiftBuild, .swiftTest]
        case .localOnly: [.xcodebuildBuild]
        case .clientServer: [.swiftBuild, .swiftTest, .xcodebuildBuild]
        case .hybrid: [.swiftBuild, .swiftTest] // extended in Plan 4
        }
    }

    /// Runs each step's command in `projectDir`, throwing on the first
    /// non-zero exit with the captured combined output:
    /// `try Verifier.verify(projectDir: url, steps: [.swiftBuild, .swiftTest])`.
    ///
    /// Pass `projectName` for app-bearing shapes so `xcodebuildBuild` can
    /// name the `.xcodeproj` and scheme. Pass `environment` to overlay
    /// variables (e.g. a pinned `PATH`) onto the inherited process
    /// environment for every step and its tool probes.
    ///
    /// Throws `VerifierError.toolMissing(tool:installHint:)` when a step's
    /// required tool isn't on `PATH`, or `VerifierError.stepFailed(step:output:)`
    /// carrying the failed step and its stdout+stderr, so the caller can
    /// surface exactly why the generated project didn't build or test.
    public static func verify(
        projectDir: URL,
        steps: [VerifyStep],
        projectName: String? = nil,
        destination: String = "platform=macOS",
        environment: [String: String]? = nil
    ) throws {
        // Overlay the caller's variables onto the inherited environment.
        // Overlaying PATH REPLACES the inherited PATH for the children,
        // which the tool-missing test relies on. nil means inherit as-is.
        let resolvedEnv = environment.map { overlay in
            ProcessInfo.processInfo.environment.merging(overlay) { _, new in new }
        }

        for step in steps {
            if let required = step.requiredTool {
                // Probe via ABSOLUTE `/bin/sh` (not `sh`, which env would
                // resolve through the overlaid PATH — a /nonexistent PATH
                // then fails to even launch the shell, and a PATH missing
                // /bin yields a false toolMissing). The absolute shell is
                // PATH-independent while `command -v` still honors the
                // overlaid PATH. Plain `-c`, NOT `-lc`: a login shell sources
                // profile scripts (path_helper, brew shellenv) that can
                // restore a real PATH and defeat the overlay.
                let probe = run(
                    command: ["/bin/sh", "-c", "command -v \(required.tool)"],
                    in: projectDir,
                    environment: resolvedEnv
                )
                guard probe.status == 0 else {
                    throw VerifierError.toolMissing(
                        tool: required.tool,
                        installHint: required.installHint
                    )
                }
            }

            let result = run(
                command: step.command(projectName: projectName, destination: destination),
                in: projectDir,
                environment: resolvedEnv
            )
            guard result.status == 0 else {
                throw VerifierError.stepFailed(step: step, output: result.output)
            }
        }
    }

    /// Runs one command via `/usr/bin/env` in `dir`, draining stdout+stderr,
    /// and returns the exit status with the combined output.
    private static func run(
        command: [String],
        in dir: URL,
        environment: [String: String]?
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = dir
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Drain the pipe on a background thread BEFORE waitUntilExit().
        // A real `swift build` easily exceeds the ~64KB pipe buffer;
        // reading only after the child exits would deadlock (the child
        // blocks writing a full pipe while we block waiting for it).
        let collected = DrainBox()
        let drained = DispatchSemaphore(value: 0)
        let drain = Thread {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            collected.store(data)
            drained.signal()
        }
        drain.stackSize = 1 << 20
        drain.start()

        do {
            try process.run()
        } catch {
            // Reached only if /usr/bin/env itself cannot be spawned (it is
            // an absolute path that always exists, so this is defensive). A
            // missing *tool* surfaces as env's own non-zero exit, not here.
            // Close our write end so the drain thread sees EOF, then report.
            try? pipe.fileHandleForWriting.close()
            drained.wait()
            return (status: 127, output: "\(error)")
        }
        process.waitUntilExit()

        // Join: the read returns EOF once the child's write ends close,
        // which waitUntilExit() has already ensured has happened.
        drained.wait()

        let output = String(data: collected.data, encoding: .utf8) ?? ""
        return (status: process.terminationStatus, output: output)
    }
}

/// A locked hand-off box for the drained pipe data. The drain thread
/// writes once, then signals; the caller reads after the wait returns.
private final class DrainBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    func store(_ data: Data) {
        lock.lock()
        _data = data
        lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return _data
    }
}
