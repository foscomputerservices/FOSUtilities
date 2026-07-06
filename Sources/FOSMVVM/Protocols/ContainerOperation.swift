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

/// The operations a subject can be authorized to perform on a container's records.
///
/// Check authorization by **intent**, never by comparing cases — this honors the ``anyOperation``
/// wildcard and stays correct as operations are added:
///
/// ```swift
/// if grantedOperations.authorizesReadRecords {   // grantedOperations: [ContainerOperation]
///     // ...load the records...
/// }
/// ```
public enum ContainerOperation: Hashable, CaseIterable, Sendable {
    /// Read the records the container owns.
    case readRecords
    /// Modify the records the container owns.
    case writeRecords
    /// Create new records in the container.
    case createRecords
    /// Mark the container's records deleted (recoverable).
    case deleteRecords
    /// Permanently destroy the container's records (unrecoverable).
    case destroyRecords
    /// Wildcard: authorizes every operation **except** ``destroyRecords``, which must be granted explicitly.
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

    /// `true` if this operation authorizes (recoverably) deleting the container's records.
    var authorizesDeleteRecords: Bool {
        self == .anyOperation || self == .deleteRecords
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

    /// `true` if **any** operation in the set authorizes (recoverably) deleting the container's records.
    var authorizesDeleteRecords: Bool {
        contains(where: \.authorizesDeleteRecords)
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
        case .deleteRecords: authorizesDeleteRecords
        case .destroyRecords: authorizesDestroyRecords
        case .anyOperation: contains(.anyOperation)
        }
    }
}
