// ModelOperation.swift
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

/// What a grant lets its holder do to a model itself — the model-level axis of authorization.
///
/// It has two homes. A grant answers it for the model it names:
///
/// ```swift
/// func authorizes(_ operation: ModelOperation, on model: ModelIdentity) -> Bool {
///     model == authorizedModel && modelOperations.authorizes(operation)
/// }
/// ```
///
/// and a loading plan names the operation the subject must hold over every model it returns:
///
/// ```swift
/// static let boards  = Board.loadingPlan(.read, within: .subject)
/// static let targets = Board.loadingPlan(.archive, within: .subject)   // an archive request's candidates
/// ```
///
/// Check a granted set by intent, never by comparing cases — `granted.authorizes(.archive)` —
/// so the wildcard is honored. There is no `create`: a model is created into a container,
/// which is `creationPlan(within:)` on the model and ``ContainerOperation/createRecords`` on
/// the container's grant.
public enum ModelOperation: Hashable, CaseIterable, Sendable {
    /// Read the model's own row. In a plan: the models the subject may read.
    ///
    /// ```swift
    /// static let workspaces = Workspace.loadingPlan(.read, within: .subject)
    /// ```
    case read

    /// Modify the model's own fields. In a plan: an update request's candidates — the submitted
    /// target must be one of them.
    ///
    /// ```swift
    /// static let candidates = Workspace.loadingPlan(.write, within: .subject)
    /// ```
    case write

    /// Archive the model: it stays, marked deleted and recoverable. In a plan: an archive
    /// request's candidates.
    ///
    /// ```swift
    /// static let candidates = Board.loadingPlan(.archive, within: .subject)
    /// ```
    case archive

    /// Destroy the model permanently. Never implied by ``anyOperation``; a grant must say it.
    /// In a plan: a destroy request's candidates.
    ///
    /// ```swift
    /// static let candidates = Board.loadingPlan(.destroy, within: .subject)
    /// ```
    case destroy

    /// Wildcard: every operation except ``destroy``. A grant may hold it; a loading plan may not
    /// name it — `loadingPlan(.anyOperation, ...)` fails at boot, because "models the subject
    /// holds every authority over" is not a set anyone declares.
    ///
    /// ```swift
    /// let modelOperations: [ModelOperation] = [.anyOperation]   // read, write, archive — not destroy
    /// ```
    case anyOperation
}

public extension ModelOperation {
    /// `true` if this operation authorizes reading the model.
    var authorizesRead: Bool {
        self == .anyOperation || self == .read
    }

    /// `true` if this operation authorizes modifying the model.
    var authorizesWrite: Bool {
        self == .anyOperation || self == .write
    }

    /// `true` if this operation authorizes archiving the model.
    var authorizesArchive: Bool {
        self == .anyOperation || self == .archive
    }

    /// `true` only for ``destroy`` — the wildcard deliberately does **not** grant destroy.
    var authorizesDestroy: Bool {
        self == .destroy
    }
}

public extension Sequence<ModelOperation> {
    /// `true` if **any** operation in the set authorizes reading the model.
    var authorizesRead: Bool {
        contains(where: \.authorizesRead)
    }

    /// `true` if **any** operation in the set authorizes modifying the model.
    var authorizesWrite: Bool {
        contains(where: \.authorizesWrite)
    }

    /// `true` if **any** operation in the set authorizes archiving the model.
    var authorizesArchive: Bool {
        contains(where: \.authorizesArchive)
    }

    /// `true` if **any** operation in the set authorizes destroying the model.
    var authorizesDestroy: Bool {
        contains(where: \.authorizesDestroy)
    }

    /// Whether this granted set covers `operation` — including via the wildcard. Use this instead of
    /// `contains(_:)`, which silently ignores the wildcard grant:
    ///
    /// ```swift
    /// modelOperations.authorizes(.archive)
    /// ```
    func authorizes(_ operation: ModelOperation) -> Bool {
        switch operation {
        case .read: authorizesRead
        case .write: authorizesWrite
        case .archive: authorizesArchive
        case .destroy: authorizesDestroy
        case .anyOperation: contains(.anyOperation)
        }
    }
}

/// The two axes map one to one except create, which has no model-level twin: a model is created
/// into a container. `package`, not public: the FOSMVVMVapor engine binds a subject-scoped plan by
/// asking named models for the model operation and granted containers for the member operation;
/// an app never needs to translate between the two.
package extension ModelOperation {
    /// The member operation a granted container must extend for this model operation.
    var containerOperation: ContainerOperation {
        switch self {
        case .read: .readRecords
        case .write: .writeRecords
        case .archive: .archiveRecords
        case .destroy: .destroyRecords
        case .anyOperation: .anyOperation
        }
    }
}

package extension ContainerOperation {
    /// The model operation a named model must hold for this member operation; `nil` for
    /// ``createRecords``, which has no model-level twin.
    var modelOperation: ModelOperation? {
        switch self {
        case .readRecords: .read
        case .writeRecords: .write
        case .createRecords: nil
        case .archiveRecords: .archive
        case .destroyRecords: .destroy
        case .anyOperation: .anyOperation
        }
    }
}
