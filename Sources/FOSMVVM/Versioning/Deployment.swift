// Deployment.swift
//
// Created by David Hunt on 9/11/24
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

/// An enumeration representing different deployment configurations for the application
///
/// The deployment value is used to determine the environment that the application should
/// use to provide its services.  Typically the environment would include which web service
/// URL to use, or which database server to connect to.
///
/// The ``Deployment/current`` property should be consulted to determine the
/// current deployment.
///
/// ## Example
///
/// ```swift
/// static func baseURL() async {
///   switch await Deployment.current {
///   case .production: return "https://production.webservice"
///   case .staging: return "https://staging.webservice"
///   case .debug: return "http://localhost:8080"
///   case .custom(let name): return "https://\(name).webservice"
///   }
/// }
/// ```
public enum Deployment: Codable, Identifiable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The deployment configuration for a production release
    ///
    /// The **production** deployment indicates that the application is configured for end-user
    /// access.  Client applications will connect to the production
    /// web service and server applications will connect to the production database.
    case production

    /// The deployment configuration for a staging release
    ///
    /// The **staging** deployment indicates that the application is configured for
    /// testing access.  Client applications will connect to the staging
    /// web service and server applications will connect to the staging database.
    case staging

    /// The deployment configuration for a debug release
    ///
    /// The **debug** deployment indicates that the application is configured for
    /// development access.  Client applications will connect to a development
    /// web service, which is typically on the local machine.  Server applications will
    /// connect to a development database, which is typically on the local machine.
    case debug

    /// A custom deployment configuration with a user-specified name
    ///
    /// **Custom** deployments are defined by the application implementer and
    /// cannot be generally reasoned on other than in a per-application context.
    ///
    /// - Parameter name: A `String` representing the custom deployment release's name.
    case custom(name: String)

    /// The system environment key that is consulted for deployment information
    ///
    /// The value is always: FOS-DEPLOYMENT
    ///
    /// ## Example
    ///
    /// ```bash
    ///
    /// # Set deployment to production
    /// export FOS-DEPLOYMENT=production
    ///
    /// # Set a custom deployment
    /// export FOS-DEPLOYMENT=my_custom_deployment
    /// ```
    public static var envKey: String { "FOS-DEPLOYMENT" }

    /// The current deployment
    ///
    /// By default the process attempts to detect which deployment to use:
    ///
    /// | Order | Detection | Deployment |
    /// | ----- | -------------- | -------------- |
    /// | 1) | Overridden Deployment | *overridden value* |
    /// | 2) | Shell Environment Specification | *shell env value* |
    /// | 3) | Bundle.isTestFlightInstall | staging |
    /// | 4) | #if DEBUG is true | debug |
    /// | 5) | default | production |
    public static var current: Self {
        get async {
            if let override = await getDeploymentOverride() {
                return override
            } else if let envSpecified = ProcessInfo.processInfo.deployment {
                return envSpecified
            }

            if Bundle.main.isTestFlightInstall {
                return .staging
            }

            #if DEBUG
            return .debug
            #else
            return .production
            #endif
        }
    }

    /// Forcefully override the deployment
    ///
    /// At times the deployment might be able to be overridden by the user or
    /// the application.  This can come in handy during testing of the application
    /// as you can manually change the application to connect to different server
    /// deployments.
    ///
    /// - Parameter deployment: The deployment to set
    public static func overrideDeployment(to deployment: Self) async {
        await setDeploymentOverride(to: deployment)
    }

    /// A function to reset the Deployment back to startup default
    static func testingReset() async {
        await setDeploymentOverride(to: nil)
    }

    // MARK: Identifiable Protocol

    /// The stable identity of the deployment configuration
    public var id: String {
        switch self {
        case .production: "production"
        case .staging: "staging"
        case .debug: "debug"
        case .custom(let name): name
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: CustomDebugStringConvertible, CustomDebugStringConvertible

    public var description: String { id }
    public var debugDescription: String { id }

    fileprivate init(string: String) {
        switch string {
        case "production":
            self = .production
        case "staging":
            self = .staging
        case "debug":
            self = .debug
        default:
            self = .custom(name: string)
        }
    }
}

private extension Deployment {
    static func getDeploymentOverride() async -> Self? {
        guard let value =
            await GlobalStringStore.default.getValue(key: key)?.lowercased()
        else {
            return nil
        }

        return .init(string: value)
    }

    static func setDeploymentOverride(to newValue: Self?) async {
        if let newValue {
            await GlobalStringStore.default.setValue(key: key, value: newValue.id)
        } else {
            await GlobalStringStore.default.removeValue(key: key)
        }
    }

    private static var key: String {
        "__FOS.DEPLOYMENT.OVERRIDE__"
    }
}

private extension ProcessInfo {
    var deployment: Deployment? {
        guard let deployment = environment[Deployment.envKey], !deployment.isEmpty else {
            return nil
        }

        return .init(string: deployment)
    }
}
