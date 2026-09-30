// ContainerOperation.swift
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

/// What a grant lets its holder do to the models a container contains — the container-extension
/// axis of authorization, beside ``ModelOperation`` for the container itself.
///
/// A grant on a Workspace can say both: `.write` on the Workspace's own row (``ModelOperation``)
/// and `readRecords` of type `Board` inside it (this enum). A grant answers this axis per
/// contained type:
///
/// ```swift
/// func authorizes(_ operation: ContainerOperation, ofType recordType: any FOSMVVM.Model.Type, in container: ModelIdentity) -> Bool {
///     container == authorizedModel && memberOperations.authorizes(operation) && memberTypes.contains(recordType.modelIdentityNamespace)
/// }
/// ```
///
/// A loading plan never names this enum directly: `Board.loadingPlan(.read, within: .request)`
/// asks the request's container for `readRecords` of `Board`, and `Board.creationPlan(within:
/// .request)` asks it for `createRecords`. With ``AuthorityFlow/inherits`` a grant's extension
/// reaches every level beneath the container along a declared path.
///
/// Check by intent, never by comparing cases: `grantedOperations.authorizes(.readRecords)`.
public enum ContainerOperation: Hashable, CaseIterable, Sendable {
    /// Read the models the container owns. Asked by every `loadingPlan(.read, ...)` whose scope
    /// is a container, per contained type.
    case readRecords

    /// Modify the models the container owns. Asked by `loadingPlan(.write, ...)` within a
    /// container: an update request's candidates.
    case writeRecords

    /// Create new models in the container. Asked by `creationPlan(within:)` — the only way
    /// a create is authorized, since a model that does not exist has no grant of its own.
    ///
    /// ```swift
    /// static let newBoard = Board.creationPlan(within: .request)   // into the Workspace the client named
    /// ```
    case createRecords

    /// Archive the container's models: they stay, marked deleted and recoverable. Asked by
    /// `loadingPlan(.archive, ...)` within a container.
    case archiveRecords

    /// Permanently destroy the container's models. Never implied by ``anyOperation``. Asked by
    /// `loadingPlan(.destroy, ...)` within a container.
    case destroyRecords

    /// Wildcard: every operation except ``destroyRecords``, which must be granted explicitly.
    ///
    /// ```swift
    /// let memberOperations: [ContainerOperation] = [.anyOperation]   // read, write, create, archive — not destroy
    /// ```
    case anyOperation
}

public extension ContainerOperation {
    /// `true` if this operation authorizes reading the container's records.
    var authorizesReadRecords: Bool {
        self == .anyOperation || self == .readRecords
    }

    /// `true` if this operation authorizes modifying the container's records.
    var authorizesWriteRecords: Bool {
        self == .anyOperation || self == .writeRecords
    }

    /// `true` if this operation authorizes creating records in the container.
    var authorizesCreateRecords: Bool {
        self == .anyOperation || self == .createRecords
    }

    /// `true` if this operation authorizes archiving the container's records.
    var authorizesArchiveRecords: Bool {
        self == .anyOperation || self == .archiveRecords
    }

    /// `true` only for ``destroyRecords`` — the wildcard deliberately does **not** grant destroy.
    var authorizesDestroyRecords: Bool {
        self == .destroyRecords
    }
}

public extension Sequence<ContainerOperation> {
    /// `true` if **any** operation in the set authorizes reading the container's records.
    var authorizesReadRecords: Bool {
        contains(where: \.authorizesReadRecords)
    }

    /// `true` if **any** operation in the set authorizes modifying the container's records.
    var authorizesWriteRecords: Bool {
        contains(where: \.authorizesWriteRecords)
    }

    /// `true` if **any** operation in the set authorizes creating records in the container.
    var authorizesCreateRecords: Bool {
        contains(where: \.authorizesCreateRecords)
    }

    /// `true` if **any** operation in the set authorizes archiving the container's records.
    var authorizesArchiveRecords: Bool {
        contains(where: \.authorizesArchiveRecords)
    }

    /// `true` if **any** operation in the set authorizes destroying the container's records.
    var authorizesDestroyRecords: Bool {
        contains(where: \.authorizesDestroyRecords)
    }

    /// Whether this granted set covers `operation` — including via the wildcard. Use this instead of
    /// `contains(_:)`, which silently ignores the wildcard grant:
    ///
    /// ```swift
    /// grantedOperations.authorizes(.readRecords)
    /// ```
    func authorizes(_ operation: ContainerOperation) -> Bool {
        switch operation {
        case .readRecords: authorizesReadRecords
        case .writeRecords: authorizesWriteRecords
        case .createRecords: authorizesCreateRecords
        case .archiveRecords: authorizesArchiveRecords
        case .destroyRecords: authorizesDestroyRecords
        case .anyOperation: contains(.anyOperation)
        }
    }
}
