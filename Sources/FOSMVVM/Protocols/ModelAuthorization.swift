// ModelAuthorization.swift
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

/// Declares that your grant value can answer "may this subject touch this model, and what it
/// contains?" — conform a value type your persisted grant row projects, so the framework can
/// scope every load with it.
///
/// ```swift
/// // A Sendable snapshot of one grant row (persisted Fluent classes aren't Sendable — project a value):
/// struct Grant: ModelAuthorization {
///     let authorizedModel: ModelIdentity         // the model this grant names — a Workspace, a Board, a Card
///     let modelOperations: [ModelOperation]      // what the holder may do to it
///     let memberOperations: [ContainerOperation] // what it extends to the models it contains
///     let memberTypes: [ModelNamespace]          // the stored, decodable form of "which contained types"
///
///     func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
///         model == authorizedModel && modelOperations.authorizes(operation)
///     }
///     func authorizes(_ operation: ContainerOperation,
///                     ofType recordType: any FOSMVVM.Model.Type,   // qualify: FluentKit also declares `Model`
///                     in container: ModelIdentity) -> Bool {
///         container == authorizedModel
///             && memberOperations.authorizes(operation)            // honors the wildcard — never `contains`
///             && memberTypes.contains(recordType.modelIdentityNamespace)
///     }
/// }
/// ```
///
/// A grant on a container answers both questions; a grant on a leaf answers the first. The
/// framework never sees your role or user types — it only asks each grant whether it covers the
/// model, or the operation and type inside the container. A subject with no covering grant simply
/// loads an empty set; routes are never the place to enforce data access.
public protocol ModelAuthorization: Sendable {
    /// The model this grant names (persist it as a stored ``ModelIdentity``). For a grant on a
    /// container, the container.
    var authorizedModel: ModelIdentity { get }

    /// Whether `operation` on `model` itself is granted.
    ///
    /// Answer it for the model your grant names — a container's own row included — so the
    /// framework can load that model on its own authority, without a parent:
    ///
    /// ```swift
    /// func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
    ///     model == authorizedModel && modelOperations.authorizes(operation)
    /// }
    /// ```
    ///
    /// The default answers `false`: a grant that does not implement this authorizes only the
    /// models its container extends to, as before.
    func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool

    /// Whether `operation` on records of `recordType` inside `container` is granted.
    func authorizes(
        _ operation: ContainerOperation,
        ofType recordType: any Model.Type,
        in container: ModelIdentity
    ) -> Bool

    /// The grant's model, under its former name. Conform with ``authorizedModel`` instead.
    @available(*, deprecated, renamed: "authorizedModel")
    var authorizedContainer: ModelIdentity { get }
}

public extension ModelAuthorization {
    func authorizes(_: ModelOperation, on _: ModelIdentity) -> Bool {
        false
    }

    /// Declare ``authorizedModel``. A conformer still declaring the former `authorizedContainer`
    /// answers through it; one declaring neither fails at its first use, by name.
    @available(*, deprecated, message: "declare authorizedModel; this default forwards from the former authorizedContainer")
    var authorizedModel: ModelIdentity {
        authorizedContainer
    }

    @available(*, deprecated, renamed: "authorizedModel")
    var authorizedContainer: ModelIdentity {
        // Reached only by a conformer declaring neither spelling. A protocol cannot require "one of
        // two", so this trap is the compile error the language cannot give.
        preconditionFailure("\(Self.self) declares neither authorizedModel nor authorizedContainer — declare authorizedModel")
    }
}

/// The former name of ``ModelAuthorization``: a grant names a model, container or not, and
/// answers both axes.
@available(*, deprecated, renamed: "ModelAuthorization")
public typealias ContainerAuthorization = ModelAuthorization
