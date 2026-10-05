// ModelIdentifiedViewModel.swift
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

/// A ``ViewModel`` that knows *which* ``Model`` instance it projects.
///
/// Conform when a ViewModel represents a specific entity, such as a board, a card, or a list row, so it
/// carries the identity of the entity it projects and roots its ``ViewModel/vmId`` in it. Singleton
/// or ephemeral ViewModels don't conform and keep only ``ViewModel/vmId``.
///
/// The identity is opaque to the ViewModel: it takes the identity in its init and passes it,
/// unchanged, to the Operations that act on the entity. Its factory reads ``Model/modelIdentity``
/// and passes it in; a test or preview passes ``ModelIdentity/stub()``.
///
/// ```swift
/// @ViewModel
/// struct CardViewModel: ModelIdentifiedViewModel {
///     let modelIdentity: ModelIdentity
///     let vmId: ViewModelId
///
///     init(modelIdentity: ModelIdentity) {
///         self.modelIdentity = modelIdentity
///         self.vmId = modelIdentity.viewModelId
///     }
///
///     static func stub(modelIdentity: ModelIdentity = .stub()) -> Self {
///         .init(modelIdentity: modelIdentity)
///     }
/// }
/// ```
public protocol ModelIdentifiedViewModel: ViewModel {
    var modelIdentity: ModelIdentity { get }
}
