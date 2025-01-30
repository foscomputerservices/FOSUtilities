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

#if canImport(Vapor)
import FOSFoundation
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor

public extension Vapor.Request {
    /// - Returns: the *SystemVersion* specified in the HTTPHeader
    ///
    /// - Throws: **SystemVersionError.missingSystemVersion** if there is no value for URLRequest.systemVersioningHeader in Request's headers
    ///    does not specify a version
    var systemVersion: SystemVersion {
        get throws {
            guard let str = headers[URLRequest.systemVersioningHeader].first else {
                throw SystemVersionError.missingSystemVersion
            }

            guard let version = SystemVersion(str) else {
                throw SystemVersionError.invalidSystemVersionString(str)
            }

            return version
        }
    }

    /// Checks to see if the HTTPHeader contains a version specification and if it
    /// is compatible with the current *SystemVersion*
    ///
    /// - Throws: **SystemVersionError.incompatibleSystemAPIVersion** If the specification is missing or is not compatible
    func requireCompatibleSystemVersion() throws {
        let sv = try systemVersion

        guard sv.isCompatible(with: SystemVersion.current) else {
            throw SystemVersionError.incompatibleSystemAPIVersion(sv.versionString)
        }
    }
}
#endif
