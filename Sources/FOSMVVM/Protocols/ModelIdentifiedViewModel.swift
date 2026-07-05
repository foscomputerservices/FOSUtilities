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
/// Conform when a ViewModel represents a specific entity — a user, a document, a list row — so the
/// framework can key identity-based behavior (e.g. live refresh) to it. Singleton or ephemeral
/// ViewModels don't conform and keep only ``ViewModel/vmId``.
///
/// ```swift
/// @ViewModel
/// struct UserViewModel: RequestableViewModel, ModelIdentifiedViewModel {
///     let modelIdentity: ModelIdentity
///     let vmId: ViewModelId
///
///     init(user: User) throws {
///         self.modelIdentity = try user.modelIdentity
///         self.vmId = modelIdentity.viewModelId
///     }
/// }
/// ```
public protocol ModelIdentifiedViewModel: ViewModel {
    var modelIdentity: ModelIdentity { get }
}
