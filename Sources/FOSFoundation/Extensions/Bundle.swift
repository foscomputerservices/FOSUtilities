// Bundle.swift
//
// Created by David Hunt on 9/11/24
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

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS) || os(visionOS)
public extension Bundle {
    /// Returns **true** if the Application *Bundle* is running in a simulator
    ///
    /// ## Example
    ///
    /// ```
    /// print("Application is \(Bundle.main.isSimulator ? "" : "NOT ")running in the simulator.")
    /// ```
    ///
    /// - See: [Stack Overflow](https://stackoverflow.com/a/26113597/608569)
    var isSimulator: Bool {
        appStoreReceiptURL?.path.contains("CoreSimulator") ?? false
    }

    /// Returns **true** if the Application *Bundle* was installed on the current device through *TestFlight*
    ///
    /// ## Example
    ///
    /// ```
    /// print("Application is \(Bundle.main.isTestFlightInstall ? "" : "NOT ")a Test Flight install.")
    /// ```
    ///
    /// - See: [Stack Overflow](https://stackoverflow.com/a/26113597/608569)
    var isTestFlightInstall: Bool {
        appStoreReceiptURL?.path.contains("sandboxReceipt") ?? false
    }

    /// Returns a ``SystemVersion`` instance that is initialized from the Application's Bundle
    ///
    /// The *major* and *minor* version numbers are from the *CFBundleShortVersionString* and
    /// the patch number is from the *CFBundleVersion*.  These specifications are usually found
    /// in the application's .xcodeproj in the General tab in the Identity section and the *Version*
    /// and *Build* fields, respectively.
    ///
    /// - NOTE: Generally the ``SystemVersion`` for the application is not configured from
    ///     these values.  However, this is where Apple defines the version of the application and
    ///     how the version will appear to the user in the App Store.  Thus, access is provided
    ///     here to Apple's version so that it can be compared with *SystemVersion.current*
    ///     to ensure that they are equal.
    ///
    /// - Throws: ``SystemVersionError``
    var appleOSVersion: SystemVersion {
        get throws {
            guard let versionStr = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                throw SystemVersionError.invalidSystemVersionString("<missing>")
            }

            let fields = versionStr.split(separator: ".").compactMap { Int($0) }
            guard fields.count >= 2, fields.count <= 3 else {
                throw SystemVersionError.incompatibleApplicationVersionString(versionStr)
            }

            return try .init(major: fields[0], minor: fields[1], patch: bundleBuildNumber)
        }
    }

    private var bundleBuildNumber: Int {
        get throws {
            guard
                let bundleVersionStr = object(forInfoDictionaryKey: "CFBundleVersion") as? String
            else {
                throw SystemVersionError.incompatibleBundleVersionString("<missing>")
            }

            guard let buildNum = Int(bundleVersionStr) else {
                throw SystemVersionError.incompatibleBundleVersionString(bundleVersionStr)
            }

            return buildNum
        }
    }
}
#endif
