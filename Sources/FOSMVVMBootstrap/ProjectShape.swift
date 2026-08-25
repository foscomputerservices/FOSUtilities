// ProjectShape.swift
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

/// The four canonical FOSMVVM project shapes.
public enum ProjectShape: String, Codable, CaseIterable, Sendable {
    case localOnly
    case clientServer
    case hybrid
    case sharedLibrary
}

/// Platforms a generated project may declare.
///
/// `CodingKeyRepresentable` makes `[TargetPlatform: String]` encode and
/// decode as a JSON *object* (`{ "macOS": "14.0" }`). Without it,
/// Foundation codes enum-keyed dictionaries as an array of alternating
/// pairs and the config-file decode fails. For a String-raw enum the
/// stdlib synthesizes the conformance — no custom Codable glue.
public enum TargetPlatform: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case iOS, macOS, macCatalyst, tvOS, watchOS, visionOS
}
