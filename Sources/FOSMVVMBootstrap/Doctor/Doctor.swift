// Doctor.swift
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

// Doctor.swift
import Foundation

/// Audits an existing project against the rules the scaffolder generates by,
/// and reports what has drifted — without changing anything.
///
/// ```swift
/// let report = try Doctor.examine(projectAt: URL(filePath: "/Users/me/MyApp"))
/// print(report.text)
/// if report.hasErrors { throw ExitCode.failure }
/// ```
///
/// Reach for this after adding a framework target by hand, or when adopting
/// FOSUtilities in a project the scaffolder never touched — the settings that
/// go wrong (the misspelled distribution flag, a second direct FOS link, a
/// missing team id) fail at runtime, far from their cause.
public enum Doctor {
    /// Reads the project at `root` and returns everything wrong with it.
    ///
    /// ```swift
    /// let report = try Doctor.examine(projectAt: projectDir, shape: .clientServer)
    /// ```
    ///
    /// Nothing is written, ever — the report names the remedy and leaves the
    /// change to you.
    ///
    /// > Note: Pass `shape` when you know it. Entitlements posture and
    /// > localization YAML layout can only be judged against a known shape;
    /// > without one they are listed in ``Report/unchecked`` rather than
    /// > guessed at.
    ///
    /// - Parameters:
    ///   - root: The project directory — the one holding the `.xcodeproj`,
    ///     the `Package.swift`, or both.
    ///   - shape: The project shape, when known.
    /// - Throws: ``AuditedProjectError`` when `root` does not exist or its
    ///   Xcode project cannot be read.
    public static func examine(projectAt root: URL, shape: ProjectShape? = nil) throws -> Report {
        let project = try AuditedProject.read(from: root)

        var findings: [Finding] = []
        var unchecked: [String] = []

        for rule in ProjectRule.all {
            if rule.requiresShape, shape == nil {
                unchecked.append("\(rule.summary) (needs --shape)")
                continue
            }
            if rule.requiresXcodeProject, !project.hasXcodeProject {
                continue
            }
            findings += rule.evaluate(project, shape)
        }

        return Report(findings: findings, unchecked: unchecked)
    }
}

public extension Doctor {
    /// What ``Doctor/examine(projectAt:shape:)`` found.
    ///
    /// ```swift
    /// let report = try Doctor.examine(projectAt: projectDir)
    /// print(report.text)
    /// ```
    struct Report: Sendable, Equatable {
        /// Everything wrong, worst first.
        public let findings: [Finding]

        /// Rules that could not run, and why — each one a sentence to print.
        /// A rule listed here was neither passed nor failed.
        public let unchecked: [String]

        init(findings: [Finding], unchecked: [String]) {
            self.findings = findings.sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity == .error
                }
                return (lhs.target ?? "") < (rhs.target ?? "")
            }
            self.unchecked = unchecked
        }

        /// True when at least one finding is an error — the signal to fail a
        /// build step or a generator skill's gate.
        public var hasErrors: Bool {
            findings.contains { $0.severity == .error }
        }

        /// The whole report as JSON, for tooling that parses rather than reads.
        ///
        /// ```swift
        /// print(try Doctor.examine(projectAt: projectDir).json)
        /// ```
        ///
        /// Both front ends print exactly this under `--json`. The shape is part
        /// of the contract: `findings` (each with `severity` — `error` or
        /// `warning` — an optional `target`, `summary`, and `remedy`),
        /// `unchecked`, and `hasErrors`. Keys are sorted, so output is stable
        /// across runs for diffing and CI.
        public var json: String {
            get throws {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                // swiftlint:disable:next optional_data_string_conversion
                return try String(decoding: encoder.encode(self), as: UTF8.self)
            }
        }

        /// The whole report as text, ready to print.
        ///
        /// ```swift
        /// print(try Doctor.examine(projectAt: projectDir).text)
        /// ```
        ///
        /// Both `fosmvvm-bootstrap doctor` and the `fosmvvm-doctor` package
        /// plugin print exactly this.
        public var text: String {
            guard !findings.isEmpty || !unchecked.isEmpty else {
                return "✅ No findings — the project matches the generated structure."
            }

            var lines: [String] = []
            for severity in Severity.allCases {
                let matching = findings.filter { $0.severity == severity }
                guard !matching.isEmpty else { continue }
                lines.append("")
                lines.append("\(severity == .error ? "❌" : "⚠️") \(matching.count) \(severity.rawValue)\(matching.count == 1 ? "" : "s")")
                for finding in matching {
                    lines.append("")
                    lines.append("  \(finding.target ?? "(project)")")
                    lines.append("    \(finding.summary)")
                    lines.append("    → \(finding.remedy)")
                }
            }

            if !unchecked.isEmpty {
                lines.append("")
                lines.append("• Not checked")
                for entry in unchecked {
                    lines.append("    \(entry)")
                }
            }

            return lines.joined(separator: "\n") + "\n"
        }
    }
}

extension Doctor.Report: Encodable {
    private enum CodingKeys: String, CodingKey {
        case findings
        case unchecked
        case hasErrors
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(findings, forKey: .findings)
        try container.encode(unchecked, forKey: .unchecked)
        // hasErrors is derivable from findings, but a JSON consumer gating a
        // step should not have to re-derive the verdict the type already holds.
        try container.encode(hasErrors, forKey: .hasErrors)
    }
}
