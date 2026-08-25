// plugin.swift
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

// plugin.swift
import Foundation
import PackagePlugin

/// `swift package fosmvvm-doctor` — audits the package it is invoked from.
///
/// This is the zero-installation door: a project already depending on
/// FOSUtilities runs the audit without cloning or building anything by hand.
/// It runs read-only, which is also what the plugin sandbox permits.
@main
struct FOSMVVMDoctorPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "fosmvvm-doctor-tool")

        // The package directory is the project root unless the caller names
        // another. Anything the user passes (notably --shape) rides through.
        var forwarded: [String] = []
        if !arguments.contains("--project"), !arguments.contains("-p") {
            forwarded += ["--project", context.package.directoryURL.path]
        }
        forwarded += arguments

        let process = Process()
        process.executableURL = tool.url
        process.arguments = forwarded
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // The audit found errors, or could not read the project. It has
            // already printed why; exit with the same code so a CI step fails.
            throw DoctorFoundProblems(status: process.terminationStatus)
        }
    }
}

struct DoctorFoundProblems: Error, CustomStringConvertible {
    let status: Int32
    var description: String {
        "fosmvvm-doctor found problems (exit \(status))."
    }
}
