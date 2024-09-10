// SystemVersion.swift
//
// Created by David Hunt on 9/4/24
// Copyright 2024 FOS Services, LLC
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

import FOSFoundation
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Vapor)
import Vapor
#endif

public enum SystemVersionError: Error {
    case invalidSystemVersionString(_ str: String)
    case missingSystemVersion
    case incompatibleSystemAPIVersion(_ version: String)
}

/// Represents the version of the API
///
/// - See also: [Semantic Versioning](https://semver.org/)
public protocol SystemVersion: Codable, Hashable, LosslessStringConvertible, Stubbable {
    /// The major version number is incremented when breaking API changes are made
    var majorVersion: Int { get }

    /// The minor version number is incremented when new functionality is added,
    /// but in a backwards-compatible way
    var minorVersion: Int { get }

    /// The patch version number is incremented when a bug fix is made
    var patchVersion: Int { get }

    /// Returns the current version of the system
    static var currentVersion: Self { get }

    /// Initializes the ``SystemVersion``
    init(majorVersion: Int, minorVersion: Int, patchVersion: Int)
}

public extension SystemVersion {
    /// Returns a '.' separated string representing the ``SystemVersion``
    var versionString: String {
        "\(majorVersion).\(minorVersion).\(patchVersion)"
    }

    /// Returns **true** if *rhs* is the same version as *self*
    func isSameVersion(as rhs: any SystemVersion) -> Bool {
        majorVersion == rhs.majorVersion &&
            minorVersion == rhs.minorVersion &&
            patchVersion == rhs.patchVersion
    }

    /// Returns **true** if *self* is compatible with *rhs*
    func isCompatible(with rhs: any SystemVersion) -> Bool {
        majorVersion == rhs.majorVersion && minorVersion <= rhs.minorVersion
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
        currentVersion
    }
}

private extension SystemVersion {
    init(string: String) throws {
        let fields = Array(string.split(separator: ".").compactMap { Int($0) })
        if fields.count != 3 {
            throw SystemVersionError.invalidSystemVersionString(string)
        }

        self.init(
            majorVersion: fields[0],
            minorVersion: fields[1],
            patchVersion: fields[2]
        )
    }
}

public extension URLRequest {
    /// The custom HTTPHeader to use to store the
    static var systemVersioningHeader: String {
        "X-FOS-System-Version"
    }

    /// Adds an HTTPHeader that includes the given *systemVersion*
    mutating func addSystemVersioningHeader(systemVersion: some SystemVersion) {
        setValue(systemVersion.versionString, forHTTPHeaderField: Self.systemVersioningHeader)
    }
}

public extension HTTPURLResponse {
    /// - Returns:  the ``SystemVersion`` specified in the HTTPHeader
    ///
    /// - Throws: ``SystemVersionError`` if the ``HTTPURLResponse`` does not specify a version
    var systemVersion: some SystemVersion {
        get throws {
            guard let str = value(forHTTPHeaderField: URLRequest.systemVersioningHeader) else {
                throw SystemVersionError.missingSystemVersion
            }

            return try DefaultSystemVersion(string: str)
        }
    }

    /// Checks to see if the HTTPHeader contains a version specification and if it
    /// is compatible with the current ``SystemVersion``
    ///
    /// - Parameter type: The type of the ``SystemVersion`` that defines the *currentVersion*
    ///
    /// - Throws: ``SystemVersionError`` If the specification is missing or is not compatible
    func requireCompatibleSystemVersion<SV: SystemVersion>(_ type: SV.Type) throws {
        let sv = try systemVersion

        guard sv.isCompatible(with: SV.currentVersion) else {
            throw SystemVersionError.incompatibleSystemAPIVersion(sv.versionString)
        }
    }
}

#if canImport(Vapor)
public extension Vapor.Request {
    /// - Returns: the ``SystemVersion`` specified in the HTTPHeader
    ///
    /// - Throws: ``SystemVersionError`` if the **HTTPURLResponse**
    ///    does not specify a version
    var systemVersion: some SystemVersion {
        get throws {
            guard let str = headers[URLRequest.systemVersioningHeader].first else {
                throw SystemVersionError.missingSystemVersion
            }

            return try DefaultSystemVersion(string: str)
        }
    }

    /// Checks to see if the HTTPHeader contains a version specification and if it
    /// is compatible with the current ``SystemVersion``
    ///
    /// - Parameter type: The type of the ``SystemVersion`` that defines the *currentVersion*
    ///
    /// - Throws: ``SystemVersionError`` If the specification is missing or is not compatible
    func requireCompatibleSystemVersion<SV: SystemVersion>(_ type: SV.Type) throws {
        let sv = try systemVersion

        guard sv.isCompatible(with: SV.currentVersion) else {
            throw SystemVersionError.incompatibleSystemAPIVersion(sv.versionString)
        }
    }
}
#endif

private struct DefaultSystemVersion: SystemVersion {
    static let currentVersion = Self(majorVersion: 1, minorVersion: 2, patchVersion: 3)

    let majorVersion: Int
    let minorVersion: Int
    let patchVersion: Int
}
