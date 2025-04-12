// SystemVersion.swift
//
// Created by David Hunt on 12/21/24
// Copyright 2024 FOS Computer Services, LLC
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

import Foundation

public enum SystemVersionError: Error, CustomDebugStringConvertible {
    case invalidSystemVersionString(_ str: String)
    case missingSystemVersion
    case incompatibleSystemAPIVersion(_ version: String)

    /// The version string set in the Application's Bundle is in the incorrect format.  It is expected
    /// to be of the form 'major.minor.patch' (e.g. '2.1' or '2.1.5').  This specification is usually found
    /// in the application's .xcodeproj in the General tab in the Identity section and the Version field.
    case incompatibleApplicationVersionString(_ str: String)

    /// The build string set in the Application's bundle is is in the incorrect format.  It is expected
    /// to be an integer (e.g. '325').  This specification is usually found in the application's .xcodeproj
    /// in the General tab in the Identity section and the Build field.
    case incompatibleBundleVersionString(_ version: String)

    public var debugDescription: String {
        switch self {
        case .invalidSystemVersionString(let str):
            "SystemVersionError: Invalid system version string: \(str)"
        case .missingSystemVersion:
            "SystemVersionError: Missing system version"
        case .incompatibleSystemAPIVersion(let version):
            "SystemVersionError: Incompatible system API version: \(version)"
        case .incompatibleApplicationVersionString(let str):
            "SystemVersionError: CFBundleShortVersionString is not in expected format (or missing); expected 2 or 3 integer fields separated by '.', instead found \(str)"
        case .incompatibleBundleVersionString(let str):
            "SystemVersionError: CFBundleVersion is not in expected format (or missing); expected 2 or 3 integer fields separated by '.', instead found \(str)"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}

/// Represents the version of the Application
///
/// - See also: [Semantic Versioning](https://semver.org/)
public struct SystemVersion: Codable, Hashable, LosslessStringConvertible, Stubbable, Sendable, Comparable {
    /// The major version number is incremented when breaking API changes are made
    public let major: Int

    /// The minor version number is incremented when new functionality is added,
    /// but in a backwards-compatible way
    public let minor: Int

    /// The patch version number is incremented when a bug fix is made
    public let patch: Int

    /// Returns the current version of the application or server
    ///
    /// In **Client** applications, this value is set via *MVVMEnvironment*.  In
    /// **Server** applications, this value is set by calling ``setCurrentVersion(_:)``
    /// in the application's initialization routine.
    public private(set) nonisolated(unsafe) static var current: Self = .vInitial

    /// Returns the lowest version of the application that is supported by the server
    ///
    /// In **Client** applications, this value is *undefined*
    /// In **Server** applications, this value is set by calling ``setMinimumSupportedVersion(_:)`` in the application's initialization routine.
    public private(set) nonisolated(unsafe) static var minimumSupportedVersion: Self = .vInitial

    /// Sets the version of the application
    ///
    /// - NOTE: This should **only be called once during the initialization of the application** as this method is **not** thread-safe!
    public static func setCurrentVersion(_ version: Self) {
        current = version
    }

    /// Sets the minimum supported version of the application
    ///
    /// - NOTE: The default value is **vInitial**
    ///
    /// - NOTE: This should **only be called once during the initialization of the application** as this method is **not** thread-safe!
    public static func setMinimumSupportedVersion(_ version: Self) {
        current = version
    }

    /// Returns the first possible version number (v1.0.0)
    public static let vInitial: Self = .init(
        major: 1,
        minor: 0,
        patch: 0
    )

    /// Initializes the ``SystemVersion``
    ///
    /// - Parameters:
    ///   - major: The *major* portion of the version number (default: 0)
    ///   - minor: The *minor* portion of the version number (default: 0)
    ///   - patch: The *patch* portion of the version number (default: 0)
    public init(major: Int? = nil, minor: Int? = nil, patch: Int? = nil) {
        self.major = major ?? 0
        self.minor = minor ?? 0
        self.patch = patch ?? 0
    }
}

public extension SystemVersion {
    /// Returns a '.' separated string representing the ``SystemVersion``
    var versionString: String {
        "\(major).\(minor).\(patch)"
    }

    /// Returns **true** if *rhs* is the same version as *self*
    func isSameVersion(as rhs: SystemVersion) -> Bool {
        major == rhs.major &&
            minor == rhs.minor &&
            patch == rhs.patch
    }

    /// Returns **true** if *self* is compatible with *rhs*
    func isCompatible(with rhs: SystemVersion) -> Bool {
        major == rhs.major && minor <= rhs.minor
    }

    // MARK: Comparable Protocol

    static func < (lhs: SystemVersion, rhs: SystemVersion) -> Bool {
        if lhs.major == rhs.major, rhs.minor == lhs.minor {
            lhs.patch < rhs.patch
        } else if lhs.major == rhs.major {
            lhs.minor < rhs.minor
        } else {
            lhs.major < rhs.major
        }
    }

    // MARK: Decodable Protocol

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(string: container.decode(String.self))
    }

    // MARK: Encodable Protocol

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(versionString)
    }

    // MARK: CustomStringConvertible Protocol

    var description: String {
        versionString
    }

    // MARK: LosslessStringConvertible Protocol

    init?(_ description: String) {
        try? self.init(string: description)
    }

    // MARK: Stubbable Protocol

    static func stub() -> Self {
        current
    }
}

extension SystemVersion { // Internal for testability
    init(string: String) throws {
        let string = string.trimmingPrefix("v")
        let fields = Array(string.split(separator: ".").compactMap { Int($0) })
        if fields.count != 3 {
            throw SystemVersionError.invalidSystemVersionString(string)
        }

        self.init(
            major: fields[0],
            minor: fields[1],
            patch: fields[2]
        )
    }
}
