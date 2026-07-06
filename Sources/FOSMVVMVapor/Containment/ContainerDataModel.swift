// ContainerDataModel.swift
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

import FluentKit
import FOSFoundation
import FOSMVVM
import Foundation

/// A Fluent-backed ``Container`` that declares which of its relationships are authorization-bearing
/// containment.
///
/// ```swift
/// final class Dock: ContainerDataModel {
///     static var containment: [ContainmentRelation] { [.children(\Dock.$berths), .siblings(\Dock.$crew)] }
///     // ...Fluent + Container members...
/// }
/// ```
public protocol ContainerDataModel: DataModel, Container where IDValue == ModelIdType {
    /// The authorization-bearing containment relationships. Must declare the same record types as
    /// ``Container/containedRecordTypes`` — ``Application/register(_:migration:)`` verifies both
    /// declarations agree at boot.
    static var containment: [ContainmentRelation] { get }
}
