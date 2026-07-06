// ComposedChild.swift
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

/// One composed child: the child factory's type + where it roots.
///
/// List children in ``ComposableFactory/children`` with the `.child` factories — the
/// parent-scope default covers the overwhelmingly common case:
///
/// ```swift
/// static var children: [ComposedChild] {
///     [.child(BerthCellViewModel.self),
///      .child(HarborBannerViewModel.self, rootedAt: .apex)]
/// }
/// ```
///
/// Only ``ComposableFactory``-conforming types can appear — a child that does not
/// declare its data cannot be composed; it fails to compile.
public struct ComposedChild: Sendable {
    // swiftformat:disable:next docComments
    // Existential metatype — the shipped Container.containedRecordTypes precedent: a boot-walked declaration list, never hot-path dispatch.
    /// The child factory's type, as listed at the declaration site.
    public let factoryType: any ComposableFactory.Type

    /// Where the child roots its containment scope — the parent's scope unless declared
    /// with `rootedAt:`.
    public let rootScope: RootScope

    /// The declared intermediate containment hops (`via:`) from the parent's scope, in order.
    /// Empty for the parent-scope default and for fresh roots.
    public let intermediates: [any Model.Type]

    /// A child sharing the parent's scope — the overwhelmingly common case:
    ///
    /// ```swift
    /// .child(BerthCellViewModel.self)
    /// ```
    public static func child(
        _ type: (some ComposableFactory).Type
    ) -> ComposedChild {
        .init(factoryType: type, rootScope: .parentRoot, intermediates: [])
    }

    /// A child rooted by containment descent from the parent's scope — `via:` lists the
    /// *intermediate* hops, in order:
    ///
    /// ```swift
    /// .child(SlipBoardViewModel.self, via: Berth.self)
    /// ```
    public static func child(
        _ type: (some ComposableFactory).Type,
        via intermediates: any Model.Type...
    ) -> ComposedChild {
        .init(factoryType: type, rootScope: .parentRoot, intermediates: intermediates)
    }

    /// A child starting a fresh root — a detail tree and an apex list in one request:
    ///
    /// ```swift
    /// .child(HarborBannerViewModel.self, rootedAt: .apex)
    /// ```
    public static func child(
        _ type: (some ComposableFactory).Type,
        rootedAt source: RootSource
    ) -> ComposedChild {
        .init(factoryType: type, rootScope: .newRoot(source), intermediates: [])
    }

    private init(
        factoryType: any ComposableFactory.Type,
        rootScope: RootScope,
        intermediates: [any Model.Type]
    ) {
        self.factoryType = factoryType
        self.rootScope = rootScope
        self.intermediates = intermediates
    }
}
