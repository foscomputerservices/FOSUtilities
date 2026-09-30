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

/// The former spelling of a plan's scope. `.parentRoot` is ``ContainmentScope/parent``;
/// `.newRoot(.query)` is ``ContainmentScope/request``; `.newRoot(.apex)` is
/// ``ContainmentScope/application``.
@available(*, deprecated, message: "declare the plan within: a ContainmentScope")
public enum RootScope: Hashable, Sendable {
    case parentRoot
    case newRoot(RootSource)

    package var containmentScope: ContainmentScope {
        switch self {
        case .parentRoot: .parent
        case .newRoot(.query): .request
        case .newRoot(.apex): .application
        }
    }
}

/// The former binder of a fresh root: `.query` is ``ContainmentScope/request``, `.apex` is
/// ``ContainmentScope/application``.
@available(*, deprecated, message: "declare the plan within: a ContainmentScope")
public enum RootSource: Hashable, Sendable, CaseIterable {
    case query
    case apex

    package var containmentScope: ContainmentScope {
        switch self {
        case .query: .request
        case .apex: .application
        }
    }
}
