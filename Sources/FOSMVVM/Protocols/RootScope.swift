// RootScope.swift
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

/// Where a data requirement or composed child roots its containment scope.
///
/// Read it as the preposition at the call site:
///
/// ```swift
/// .read(Berth.self, in: .parentRoot)              // shares the declaring factory's scope
/// .read(HarborBanner.self, in: .newRoot(.apex))    // starts a fresh tree at the apex
/// ```
public enum RootScope: Hashable, Sendable {
    /// Shares the declaring factory's scope — the overwhelmingly common case.
    case parentRoot
    /// Starts a fresh root — a new tree in the request's forest — sourced as declared.
    case newRoot(RootSource)
}

/// Where a fresh ``RootScope/newRoot(_:)`` root's identity comes from.
///
/// ```swift
/// .read(Berth.self, in: .newRoot(.query))          // the request's RootedQuery vends it
/// .read(HarborBanner.self, in: .newRoot(.apex))     // the app's apex container, server-resolved
/// ```
public enum RootSource: Hashable, Sendable, CaseIterable {
    /// The request's ``RootedQuery`` vends the root identity.
    case query
    /// The app's apex container resolves the root identity — server-resolved, no query required.
    case apex
}
