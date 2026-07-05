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

/// Whether authority granted on an ancestor flows through this container to its contained records, or
/// stops here.
///
/// The default — ``inherits`` — means one grant at the apex (or any ancestor) covers the descent;
/// nothing to declare. Declare ``guards`` on a container whose records need authority anchored at *it*:
///
/// ```swift
/// extension PersonnelFolder {
///     static var authorityFlow: AuthorityFlow { .guards }
/// }
/// ```
///
/// Reads from the declaration site: *"PersonnelFolder guards; everything else inherits."*
public enum AuthorityFlow: Hashable, Sendable, CaseIterable {
    /// An ancestor's grant covers this container's records too — the default; nothing to declare.
    case inherits
    /// This container's records need their own grant, anchored at this container.
    case guards
}
