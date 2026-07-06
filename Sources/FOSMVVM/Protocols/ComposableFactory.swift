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
/// extension BerthsViewModel: ComposableFactory {
///     static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
///         .refinedByRequest
///     static let crew   = LoadRequirement.read(CrewMember.self, in: .parentRoot)
///
///     static var dataRequirements: [any DataRequirement] { [berths, crew] }
///     static var children: [ComposedChild] {
///         [.child(BerthCellViewModel.self),
///          .child(HarborBannerViewModel.self, rootedAt: .apex)]
///     }
/// }
/// ```
///
/// The adopter need not be a ViewModel — any `ServerRequestBody` may declare its
/// data. A CLI's plain manifest body composes the same machinery:
///
/// ```swift
/// extension DockManifest: ComposableFactory {
///     static let berths = LoadRequirement.read(Berth.self, in: .parentRoot)
///     static var dataRequirements: [any DataRequirement] { [berths] }
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
    /// This factory's own data needs. Empty is meaningful: a pure composer.
    static var dataRequirements: [any DataRequirement] { get }

    /// The child factories this factory composes. Only trait-conforming
    /// types can appear — an undeclared child cannot be composed.
    static var children: [ComposedChild] { get }
}

public extension ComposableFactory {
    static var dataRequirements: [any DataRequirement] {
        []
    }

    static var children: [ComposedChild] {
        []
    }
}
