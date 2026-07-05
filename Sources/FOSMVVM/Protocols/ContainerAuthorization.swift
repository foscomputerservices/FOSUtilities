// ContainerAuthorization.swift
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

import Foundation

/// Declares that your authorization value can answer "may this subject touch these records?" —
/// conform a value type your persisted grant row projects, so the framework can scope every container
/// load with it.
///
/// ```swift
/// // A Sendable snapshot of one grant row (persisted Fluent classes aren't Sendable — project a value):
/// struct DockGrant: ContainerAuthorization {
///     let authorizedContainer: ModelIdentity   // decoded from the stored identity column
///     let operations: [ContainerOperation]
///     let recordTypes: [ModelNamespace]        // the stored, decodable form of "which record types"
///
///     func authorizes(_ operation: ContainerOperation,
///                     ofType recordType: any FOSMVVM.Model.Type,   // qualify: FluentKit also declares `Model`
///                     in container: ModelIdentity) -> Bool {
///         container == authorizedContainer
///             && operations.authorizes(operation)                   // honors the wildcard — never `contains`
///             && recordTypes.contains(recordType.modelIdentityNamespace)
///     }
/// }
/// ```
///
/// The framework never sees your role or user types — it only asks each authorization whether it covers
/// the requested container, operation, and record type. A subject with no covering authorization simply
/// loads an empty set; routes are never the place to enforce data access.
public protocol ContainerAuthorization: Sendable {
    /// The container this authorization grants access within (persist it as a stored ``ModelIdentity``).
    var authorizedContainer: ModelIdentity { get }
    /// Whether `operation` on records of `recordType` inside `container` is granted.
    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any Model.Type,
        in container: ModelIdentity
    ) -> Bool
}
