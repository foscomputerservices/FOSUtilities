// ComposableFactory.swift
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

/// Declares the data a composable factory loads — co-located with the
/// factory, aggregated automatically, loaded once per request.
///
/// ```swift
/// extension BoardPageViewModel: ComposableFactory {
///     static let cards = Card.loadingPlan(.read, within: .parent)
///         .refinedByRequest
///     static let members = Member.loadingPlan(.read, within: .parent)
///
///     static var loadingPlans: LoadingPlans {
///         cards
///         members
///     }
///     static var children: [ComposedChild] {
///         [.child(CardCellViewModel.self),
///          .child(WorkspaceBannerViewModel.self, within: .application)]
///     }
/// }
/// ```
///
/// The adopter need not be a ViewModel — any `ServerRequestBody` may declare its
/// data. A CLI's plain manifest body composes the same machinery:
///
/// ```swift
/// extension BoardManifest: ComposableFactory {
///     static let cards = Card.loadingPlan(.read, within: .parent)
///     static var loadingPlans: LoadingPlans { cards }
/// }
/// ```
///
/// A child that does not declare its data — does not conform to
/// ``ComposableFactory`` — cannot be composed: it fails to compile.
/// Declarations are aggregated automatically at boot and loaded once,
/// before the body is built.
///
/// Adopting the trait and declaring nothing — both defaults left empty — fails fast at boot.
public protocol ComposableFactory: Sendable {
    /// This factory's own plan — its clauses, listed in a builder block. Empty is meaningful:
    /// a pure composer.
    ///
    /// ```swift
    /// static var loadingPlans: LoadingPlans {
    ///     workspaces
    ///     boards
    /// }
    /// ```
    @LoadingPlansBuilder static var loadingPlans: LoadingPlans { get }

    /// The child factories this factory composes. Only trait-conforming
    /// types can appear — an undeclared child cannot be composed.
    static var children: [ComposedChild] { get }

    /// The former declaration list, honored for one release. Declare ``loadingPlans`` instead.
    @available(*, deprecated, message: "declare loadingPlans")
    static var dataRequirements: [any DataRequirement] { get }
}

public extension ComposableFactory {
    static var children: [ComposedChild] {
        []
    }
}

/// A factory written against the former `dataRequirements` still walks: this default erases that
/// list into the plan. A factory that declares neither is a pure composer.
@available(*, deprecated, message: "declare loadingPlans")
public extension ComposableFactory {
    static var loadingPlans: LoadingPlans {
        .init(plans: dataRequirements.compactMap { $0 as? any LoadingPlanWalkFace })
    }

    static var dataRequirements: [any DataRequirement] {
        []
    }
}
