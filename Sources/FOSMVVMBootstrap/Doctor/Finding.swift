// Finding.swift
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

// Finding.swift
import Foundation

/// How much a finding matters, and whether it fails the run.
///
/// ```swift
/// let report = try Doctor.examine(projectAt: projectDir)
/// for finding in report.findings where finding.severity == .error {
///     print(finding.summary)
/// }
/// ```
///
/// Only `error` sets `Doctor.Report.hasErrors`, so a build step or generator
/// skill can stop on errors while still showing warnings.
public enum Severity: String, Sendable, Equatable, CaseIterable, Codable {
    /// The project is wrong in a way that breaks at build or run time.
    case error

    /// Worth a look, but a project can legitimately differ here.
    case warning
}

/// One thing `Doctor` found wrong, and what to do about it.
///
/// ```swift
/// for finding in try Doctor.examine(projectAt: projectDir).findings {
///     print("\(finding.target ?? "project"): \(finding.summary)")
///     print("  → \(finding.remedy)")
/// }
/// ```
///
/// Every finding carries a `remedy` naming the exact setting, value, or action,
/// because `Doctor` never changes anything itself — knowing what is wrong is
/// only useful alongside knowing what to type.
public struct Finding: Sendable, Equatable, Codable {
    public let severity: Severity

    /// The target the finding is about, or nil when it is about the project as
    /// a whole.
    public let target: String?

    /// What is wrong, in one sentence.
    public let summary: String

    /// What to do about it — the setting and value, or the action to take.
    public let remedy: String

    public init(severity: Severity, target: String? = nil, summary: String, remedy: String) {
        self.severity = severity
        self.target = target
        self.summary = summary
        self.remedy = remedy
    }
}
