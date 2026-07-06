// Container.swift
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

/// A ``Model`` that owns and authorizes other records.
///
/// Conform a model that contains others — a `Dock` owns its `Berth`s — and list what it contains:
///
/// ```swift
/// struct Dock: Container {
///     static var containedRecordTypes: [any Model.Type] { [Berth.self] }
///     // ...Model requirements (id, requireId(), …)...
/// }
/// ```
///
/// A container's contained types drive authorized loading and live-invalidation membership. A model that
/// owns nothing needs no override — it inherits the empty default.
public protocol Container: Model {
    /// The record types this container owns.
    static var containedRecordTypes: [any Model.Type] { get }

    /// Whether authority granted on an ancestor flows through this container to its contained records,
    /// or stops here. Defaults to ``AuthorityFlow/inherits``. See ``AuthorityFlow``.
    static var authorityFlow: AuthorityFlow { get }
}

public extension Container {
    static var containedRecordTypes: [any Model.Type] {
        []
    }

    static var authorityFlow: AuthorityFlow {
        .inherits
    }
}
