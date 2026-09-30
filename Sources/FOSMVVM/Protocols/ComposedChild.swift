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

/// One composed child: the child factory's type + the scope its plans start from.
///
/// List children in ``ComposableFactory/children`` with the `.child` factories — the
/// parent-scope default covers the overwhelmingly common case:
///
/// ```swift
/// static var children: [ComposedChild] {
///     [.child(CardCellViewModel.self),
///      .child(WorkspaceBannerViewModel.self, within: .application)]
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

    /// The scope the child's plans start from — the parent's scope unless declared
    /// with `within:`.
    public let scope: ContainmentScope

    /// The declared intermediate containment hops (`via:`) from the parent's scope, in order.
    /// Empty for the parent-scope default and wherever the child opens its own scope.
    public let intermediates: [any Model.Type]

    /// A child sharing the parent's scope — the overwhelmingly common case:
    ///
    /// ```swift
    /// .child(CardCellViewModel.self)
    /// ```
    public static func child(
        _ type: (some ComposableFactory).Type
    ) -> ComposedChild {
        .init(factoryType: type, scope: .parent, intermediates: [])
    }

    /// A child reached by containment descent from the parent's scope — `via:` lists the
    /// *intermediate* hops, in order:
    ///
    /// ```swift
    /// .child(ChecklistPanelViewModel.self, via: Card.self)
    /// ```
    public static func child(
        _ type: (some ComposableFactory).Type,
        via intermediates: any Model.Type...
    ) -> ComposedChild {
        .init(factoryType: type, scope: .parent, intermediates: intermediates)
    }

    /// A child opening a scope of its own — a detail tree and an application-wide list in one
    /// request:
    ///
    /// ```swift
    /// .child(WorkspaceBannerViewModel.self, within: .application)
    /// .child(CardCellViewModel.self, within: .request, via: Board.self)
    /// ```
    public static func child(
        _ type: (some ComposableFactory).Type,
        within scope: ContainmentScope,
        via intermediates: any Model.Type...
    ) -> ComposedChild {
        .init(factoryType: type, scope: scope, intermediates: intermediates)
    }

    /// The former spelling of ``child(_:within:via:)``.
    @available(*, deprecated, message: "use .child(_:within:)")
    public static func child(
        _ type: (some ComposableFactory).Type,
        rootedAt source: RootSource
    ) -> ComposedChild {
        .init(factoryType: type, scope: source.containmentScope, intermediates: [])
    }

    private init(
        factoryType: any ComposableFactory.Type,
        scope: ContainmentScope,
        intermediates: [any Model.Type]
    ) {
        self.factoryType = factoryType
        self.scope = scope
        self.intermediates = intermediates
    }
}
