// SystemContainer.swift
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

import FOSFoundation
import FOSMVVM
import Foundation

/// A container with one instance and no table: the owner of every row of the types it lists, so a
/// model that no other container owns has a container to hang a grant on and to be created into.
///
/// Declare it once, list what it owns with ``ContainmentRelation/all(_:)``, and register it:
///
/// ```swift
/// enum Suite: SystemContainer {
///     static var containment: [ContainmentRelation] {
///         [.all(Workspace.self), .all(SystemStatus.self)]     // every Workspace; every SystemStatus
///     }
/// }
///
/// // configure(_:)
/// try app.register(Suite.self)
/// ```
///
/// A grant on ``identity`` then extends to those rows like any container grant — `readRecords`
/// of type `Workspace` reads them all, `createRecords` of type `Workspace` creates one at the
/// top — and a plan reaches them `within: .application`: with exactly one system container
/// registered and no `useApplicationScope(_:)`, the application scope binds to it by itself.
/// A model the system container owns must be registered too (`register(_:migration:)`).
///
/// It is a sibling of `Container`, not a refinement: it has no rows, no migration, and no
/// lifecycle of its own. A write to an owned row marks ``identity`` stale, so every list within
/// the application scope refreshes on a create or destroy at the top.
public protocol SystemContainer {
    /// What this container owns — only ``ContainmentRelation/all(_:)`` relations, one per type.
    static var containment: [ContainmentRelation] { get }

    /// How a grant on this container reaches deeper rows; `.inherits` unless declared.
    static var authorityFlow: AuthorityFlow { get }
}

public extension SystemContainer {
    static var authorityFlow: AuthorityFlow {
        .inherits
    }

    /// The container's one identity — minted from the type, stable across launches and hosts,
    /// so a grant row stores it as it stores any identity:
    ///
    /// ```swift
    /// Grant(authorizedModel: Suite.identity, modelOperations: [],
    ///       memberOperations: [.readRecords, .createRecords], memberTypes: [Workspace.modelIdentityNamespace])
    /// ```
    static var identity: ModelIdentity {
        .systemContainer(for: Self.self)
    }
}
