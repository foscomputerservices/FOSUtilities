// SystemVersion.swift
//
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

import FOSFoundation
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension URLRequest {
    /// Adds an HTTPHeader that includes the given *systemVersion*
    mutating func addSystemVersioningHeader(systemVersion: SystemVersion) {
        setValue("\"\(systemVersion.versionString)\"", forHTTPHeaderField: SystemVersion.httpHeader)
    }
}

public extension SystemVersion {
    static let httpHeader = "X-FOS-Version"

    /// Returns HTTP headers include the given *systemVersion*
    ///
    /// These headers can be applied to a URL.fetch() request.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let url: URL
    /// try await url.fetch(headers: SystemVersion.current.versioningHeaders)
    /// ```
    var versioningHeaders: [(field: String, value: String)] { [
        (field: SystemVersion.httpHeader, value: jsonVersionString)
    ] }
}

public extension HTTPURLResponse {
    /// - Returns:  the *SystemVersion* specified in the HTTPHeader
    ///
    /// - Throws: *SystemVersionError* if the ``HTTPURLResponse`` does not specify a version
    var systemVersion: SystemVersion {
        get throws {
            guard let str = value(forHTTPHeaderField: SystemVersion.httpHeader) else {
                throw SystemVersionError.missingSystemVersion
            }

            guard let version = SystemVersion(str) else {
                throw SystemVersionError.invalidVersionString(str)
            }

            return version
        }
    }

    /// Checks to see if the HTTPHeader contains a version specification and if it
    /// is compatible with the current *SystemVersion*
    ///
    /// - Throws: *SystemVersionError* If the specification is missing or is not compatible
    func requireCompatibleSystemVersion() throws {
        let sv = try systemVersion

        guard sv.isCompatible(with: SystemVersion.current) else {
            throw SystemVersionError.incompatibleVersion(
                requested: sv,
                required: SystemVersion.current
            )
        }
    }
}
