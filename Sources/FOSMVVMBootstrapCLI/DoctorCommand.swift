// DoctorCommand.swift
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

// DoctorCommand.swift
import ArgumentParser
import FOSMVVMBootstrap
import Foundation

/// Named DoctorCommand rather than Doctor: the type it calls is
/// FOSMVVMBootstrap.Doctor, and a same-named type here would shadow it in this
/// file. The user-facing verb is set explicitly below and is unaffected.
struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Audit an existing project against the rules the scaffolder generates by.",
        discussion: """
        Reports what has drifted and never changes anything. Exits non-zero when \
        there is at least one error, so a script or generator skill can gate on it.
        """
    )

    @Option(name: .shortAndLong, help: "Project directory to audit. Defaults to the current directory.")
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "Project shape (localOnly, clientServer, sharedLibrary). Two rules need it; without it they report as unchecked."
    )
    var shape: ProjectShape?

    @Flag(name: .long, help: "Emit the report as JSON instead of text, for tooling.")
    var json = false

    func run() throws {
        let root = URL(fileURLWithPath: project ?? FileManager.default.currentDirectoryPath)

        let report = try Doctor.examine(projectAt: root, shape: shape)
        try print(json ? report.json : report.text)

        if report.hasErrors {
            throw ExitCode.failure
        }
    }
}

/// Lets `--shape clientServer` parse straight into the typed shape, so an
/// unknown value is rejected by the parser with the valid list rather than
/// reaching the audit.
extension ProjectShape: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }

    public static var allValueStrings: [String] {
        // hybrid has no template tree, so it is not offered.
        ProjectShape.allCases.filter { $0 != .hybrid }.map(\.rawValue)
    }
}
