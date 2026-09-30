// AuthorityFlow.swift
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

/// Whether a grant on a container reaches the models beneath the models it contains, or stops
/// at its direct members.
///
/// ```swift
/// final class Workspace: ContainerDataModel { static var authorityFlow: AuthorityFlow { .inherits } }  // the default
/// final class Board: ContainerDataModel     { static var authorityFlow: AuthorityFlow { .guards } }
/// ```
///
/// With `Card.loadingPlan(.read, within: .request, via: Board.self)` the plan descends
/// Workspace → Board → Card; each hop's grant check runs against the nearest guarding
/// container above it, else the scope's own container.
public enum AuthorityFlow: Hashable, Sendable, CaseIterable {
    /// A grant on this container extends through it: `readRecords` of `Card` granted on a
    /// Workspace reaches the Cards of every Board inside it. The default. One grant high up
    /// serves a whole subtree.
    case inherits

    /// A grant on this container stops here: to read the Cards of a Board the subject needs a
    /// grant on that Board, whatever the Workspace grants. Use it where a container is its own
    /// unit of authority — a private Board inside a shared Workspace.
    case guards
}
