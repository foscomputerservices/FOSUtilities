// ProjectShape.swift

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
