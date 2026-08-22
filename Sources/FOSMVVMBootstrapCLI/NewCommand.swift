// NewCommand.swift
import ArgumentParser
import FOSMVVMBootstrap
import Foundation

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scaffold a new FOSMVVM project from a config file."
    )

    @Option(name: .shortAndLong, help: "Path to a BootstrapConfig JSON file.")
    var config: String

    @Option(name: .shortAndLong, help: "Output directory for the new project (must be empty or absent).")
    var output: String

    @Flag(help: "Skip the build/test verification phase (CI of this repo only — never for real use).")
    var skipVerify = false

    func run() throws {
        let configURL = URL(fileURLWithPath: config)
        let outputURL = URL(fileURLWithPath: output)

        let bootstrapConfig = try JSONDecoder().decode(
            BootstrapConfig.self,
            from: Data(contentsOf: configURL)
        )

        print("Scaffolding \(bootstrapConfig.projectName) (\(bootstrapConfig.shape.rawValue)) …")
        let emitted = try Emitter.emit(config: bootstrapConfig, into: outputURL)
        print("Emitted \(emitted.count) files.")

        if !skipVerify {
            let steps = Verifier.steps(for: bootstrapConfig.shape)
            print("Verifying (\(steps.map(\.rawValue).joined(separator: " / "))) …")
            try Verifier.verify(
                projectDir: outputURL,
                steps: steps,
                projectName: bootstrapConfig.projectName
            )
            print("✅ Walking skeleton verified green.")
        }

        print(HandoffChecklist.text(for: bootstrapConfig.shape, projectName: bootstrapConfig.projectName))
    }
}
