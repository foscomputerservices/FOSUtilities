// SupplementalRecordLoading.swift
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

import Vapor

/// The load-phase escape hatch for data a factory cannot declare as containment tuples —
/// conform a ``ComposableFactory`` and load that data yourself:
///
/// ```swift
/// extension DockPageViewModel: SupplementalRecordLoading {
///     static func loadSupplementalRecords(for request: Vapor.Request) async throws {
///         // The declarative plan has already run — its records are readable here.
///         // Load whatever could not be declared as a containment tuple, using the
///         // request's full load-phase power. Throwing here fails the request.
///     }
/// }
/// ```
///
/// The hook runs AFTER the declarative plan executes, so records the plan loaded are already
/// readable; full request power lives here — this is the load phase, not projection.
///
/// What you load HERE is not readable through ``ProjectionContext/records(_:)`` — that vends
/// only the declared, planned requirements. Store and consume whatever you load here through
/// your own request-scoped means (e.g. `request.storage`).
///
/// A thrown error FAILS THE REQUEST — it is never swallowed to an empty result (the same
/// no-silent-guess discipline as the declarative path).
public protocol SupplementalRecordLoading {
    static func loadSupplementalRecords(for request: Vapor.Request) async throws
}
