// NewCommand.swift
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

// NewCommand.swift
import ArgumentParser
import FOSMVVMBootstrap
import Foundation

struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scaffold a new FOSMVVM project from a config file."
    )

    @Option(name: .shortAndLong, help: "Path to a BootstrapConfig JSON file. Omit to answer a short interview instead.")
    var config: String?

    @Option(name: .shortAndLong, help: "Output directory for the new project: absent, empty, or an existing repository with no project in it yet. Nothing already there is overwritten.")
    var output: String

    @Flag(help: "After generating, build the project and run its tests (swift build / swift test / xcodebuild). CI verifies every release the same way; use this to prove the skeleton on THIS machine.")
    var verify = false

    @Flag(help: "Extra output, including the interview's equivalent --config JSON.")
    var verbose = false

    @Option(name: .customLong("fos-utilities-path"), help: ArgumentHelp(
        "Resolve FOSUtilities from this local checkout instead of the released pin.",
        discussion: "For developing FOSUtilities itself: the generated project builds against the framework in that checkout, unreleased changes included. Omit it for a shippable project, which pins the release this scaffolder shipped with."
    ))
    var fosUtilitiesPath: String?

    func run() throws {
        let outputURL = URL(fileURLWithPath: output)

        let bootstrapConfig: BootstrapConfig
        if let config {
            bootstrapConfig = try JSONDecoder().decode(
                BootstrapConfig.self,
                from: Data(contentsOf: URL(fileURLWithPath: config))
            )
        } else {
            bootstrapConfig = try Interview.conduct(outputDir: outputURL)
            if verbose {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let json = try? String(data: encoder.encode(bootstrapConfig), encoding: .utf8) {
                    print("\nEquivalent --config file (save to rerun without the interview):")
                    print(json + "\n")
                }
            }
        }

        let fosUtilities: FOSUtilitiesSource = if let fosUtilitiesPath {
            .localCheckout(URL(fileURLWithPath: fosUtilitiesPath))
        } else {
            .release
        }

        print("Scaffolding \(bootstrapConfig.projectName) (\(bootstrapConfig.shape.rawValue)) …")
        let emitted = try Emitter.emit(config: bootstrapConfig, into: outputURL, fosUtilities: fosUtilities)
        print("Emitted \(emitted.count) files.")

        // Project generation (the .xcodeproj from project.yml) is part of the
        // deliverable — it runs regardless of --skip-verify.
        let generationSteps = Verifier.generationSteps(for: bootstrapConfig.shape)
        if !generationSteps.isEmpty {
            print("Generating Xcode project …")
            try Verifier.verify(
                projectDir: outputURL,
                steps: generationSteps,
                projectName: bootstrapConfig.projectName
            )
        }

        if verify {
            let steps = Verifier.steps(for: bootstrapConfig.shape)
            print("Verifying (\(steps.map(\.rawValue).joined(separator: " / "))) …")
            try Verifier.verify(
                projectDir: outputURL,
                steps: steps,
                projectName: bootstrapConfig.projectName,
                destination: Verifier.buildDestination(for: bootstrapConfig)
            )
            print("✅ Walking skeleton verified green.")
        }

        print(HandoffChecklist.text(for: bootstrapConfig.shape, projectName: bootstrapConfig.projectName))
    }
}
