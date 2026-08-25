// ProjectRule+SharedModule.swift
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

// ProjectRule+SharedModule.swift
import Foundation

extension ProjectRule {
    /// R13 — every `@ViewModel` declaration lives in the shared ViewModels
    /// module. Types shared by name instead of by module drift apart; the
    /// shared module is the agreement mechanism between client and server,
    /// and it is where the scaffolder puts them in every shape.
    static var sharedModuleHome: ProjectRule {
        ProjectRule(
            summary: "ViewModels live in a shared ViewModels module",
            requiresXcodeProject: false
        ) { project, _ in
            let homeless = project.swiftSources
                .filter(\.declaresViewModel)
                .map(\.relativePath)
                .filter { path in
                    !project.sharedModuleRoots.contains { path.hasPrefix($0 + "/") }
                }
            guard !homeless.isEmpty else { return [] }

            // One omission, one remedy, one finding — a legacy project with
            // forty embedded ViewModels is not forty problems.
            let shown = homeless.prefix(3).joined(separator: ", ")
            let overflow = homeless.count > 3 ? " and \(homeless.count - 3) more" : ""
            return [
                Finding(
                    severity: .error,
                    summary: "\(homeless.count) ViewModel declaration\(homeless.count == 1 ? " lives" : "s live") outside a shared ViewModels module: \(shown)\(overflow).",
                    remedy: "Create a shared module — Sources/<Name>ViewModels, its own framework or library target — holding the ViewModels, ServerRequests, and Fields, and have every other target import it."
                )
            ]
        }
    }

    /// R14 — no server code inside the shared module. The dependency points
    /// one way: the server imports the shared module, never the reverse. The
    /// Factory — server-side — is the one place that sees both worlds.
    static var sharedModuleImports: ProjectRule {
        ProjectRule(
            summary: "the shared ViewModels module imports no server code",
            requiresXcodeProject: false
        ) { project, _ in
            project.swiftSources
                .filter { source in
                    project.sharedModuleRoots.contains { source.relativePath.hasPrefix($0 + "/") }
                }
                .compactMap { source in
                    let offending = source.imports.filter(isServerModule)
                    guard !offending.isEmpty else { return nil }
                    return Finding(
                        severity: .error,
                        summary: "\(source.relativePath) imports \(offending.joined(separator: ", ")) — server code inside the shared module.",
                        remedy: "Move the server-touching code into the server target; the shared module imports FOSFoundation and FOSMVVM only."
                    )
                }
        }
    }

    private static func isServerModule(_ module: String) -> Bool {
        module == "Vapor"
            || module == "FOSMVVMVapor"
            || module == "FOSTestingVapor"
            || module == "VaporTesting"
            || module == "XCTVapor"
            || module == "Leaf"
            || module == "LeafKit"
            || module.hasPrefix("Fluent")
    }
}
