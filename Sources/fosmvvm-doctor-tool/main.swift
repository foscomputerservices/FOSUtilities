// main.swift
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

// main.swift
import FOSMVVMBootstrap
import Foundation

// Plugin-only entry point. SwiftPM resolves a command plugin's tool by
// executable TARGET name, and FOSMVVMBootstrapCLI is vended under the renamed
// `fosmvvm-bootstrap` product — which the plugin machinery cannot address
// ("Could not find target named 'FOSMVVMBootstrapCLI-product'"). Renaming the
// documented command to satisfy the plugin would be the tail wagging the dog,
// so the plugin gets its own thin entry instead.
//
// This is a door, not a second implementation: it parses two flags and calls
// the same Doctor.examine that `fosmvvm-bootstrap doctor` calls.

var projectPath = FileManager.default.currentDirectoryPath
var shape: ProjectShape?
var emitJSON = false

var arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    index += 1

    func nextValue(_ flag: String) -> String {
        guard index < arguments.count else {
            FileHandle.standardError.write(Data("fosmvvm-doctor: \(flag) needs a value\n".utf8))
            exit(2)
        }
        defer { index += 1 }
        return arguments[index]
    }

    switch argument {
    case "--project", "-p":
        projectPath = nextValue(argument)
    case "--shape", "-s":
        let raw = nextValue(argument)
        guard let parsed = ProjectShape(rawValue: raw), parsed != .hybrid else {
            let valid = ProjectShape.allCases.filter { $0 != .hybrid }.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(Data("fosmvvm-doctor: unknown shape '\(raw)'. Valid shapes: \(valid)\n".utf8))
            exit(2)
        }
        shape = parsed
    case "--json":
        emitJSON = true
    case "--help", "-h":
        print("""
        USAGE: swift package fosmvvm-doctor [--project <path>] [--shape <shape>]

          Audits a project against the rules the FOSMVVM scaffolder generates by.
          Reports what has drifted and never changes anything. Exits non-zero
          when there is at least one error.

          --project <path>   Directory to audit. Defaults to the package root.
          --shape <shape>    localOnly, clientServer, or sharedLibrary. Two rules
                             need it; without it they report as unchecked.
          --json             Emit the report as JSON instead of text, for tooling.
        """)
        exit(0)
    default:
        FileHandle.standardError.write(Data("fosmvvm-doctor: unknown argument '\(argument)'\n".utf8))
        exit(2)
    }
}

do {
    let report = try Doctor.examine(projectAt: URL(fileURLWithPath: projectPath), shape: shape)
    try print(emitJSON ? report.json : report.text)
    exit(report.hasErrors ? 1 : 0)
} catch {
    FileHandle.standardError.write(Data("fosmvvm-doctor: \(error)\n".utf8))
    exit(2)
}
