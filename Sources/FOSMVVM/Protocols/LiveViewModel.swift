// LiveViewModel.swift
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

/// A ``ViewModel`` that refreshes automatically when its server data changes
///
/// Don't conform directly — opt in with the macro:
///
/// ```swift
/// @ViewModel(options: [.live])
/// public struct DocksViewModel: RequestableViewModel { ... }
/// ```
///
/// Any view bound with `.bind()` then re-fetches whenever another actor mutates
/// the data this ViewModel was served from — no polling, no manual invalidation,
/// and nothing else to write. Where no live connection is configured the
/// ViewModel behaves exactly like a non-live one (fetch once on appear), so
/// adding `.live` to a shipped screen is purely additive.
public protocol LiveViewModel: RequestableViewModel {}
