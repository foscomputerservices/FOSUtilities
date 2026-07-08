// ProjectionContext+Records.swift
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

import FOSFoundation
import FOSMVVM
import Foundation

/// The typed record read is a containment capability: it names the plan's tuples and throws
/// `ContainmentError`, both of which live at this layer. `ProjectionContext` (FOSMVVM) carries
/// the plan and the tuple→records snapshot; this extension turns a declared handle into typed
/// records against them.
public extension ProjectionContext {
    /// The records a declared requirement loaded — read by the SAME static handle the factory
    /// declared. Any handle in the request's plan is readable, including a child factory's
    /// (that is how parents compose their children).
    ///
    /// A handle that never reached the plan THROWS — never returns `[]`. A silently-empty
    /// result is a misconfiguration's invisible mode; the throw names the record type and the
    /// request, and points at the declaration that was forgotten. A handle that resolves to
    /// more than one declared load also throws — the framework never guesses which set to
    /// return; disambiguate the declarations.
    ///
    /// Treat the returned records as read-only: they are shared snapshots of what the load
    /// phase produced — do not mutate them. Mutation belongs to the write path, which
    /// invalidates and re-serves.
    func records<Record: FOSMVVM.Model>(_ handle: LoadRequirement<Record>) throws -> [Record] {
        let requestName = String(describing: Request.self)
        let recordName = String(describing: Record.self)

        guard let plan else {
            throw ContainmentError.unplannedRequirement(recordType: recordName, request: requestName)
        }

        let candidates = plan.tuples(matching: handle)
        guard let tuple = candidates.first else {
            throw ContainmentError.unplannedRequirement(recordType: recordName, request: requestName)
        }
        guard candidates.count == 1 else {
            throw ContainmentError.ambiguousRequirement(
                recordType: recordName,
                request: requestName,
                matchCount: candidates.count
            )
        }

        // The matched tuple's records, read back in deposit order. No same-type aggregation across
        // tuples: two same-typed declared loads never blend, and a denied load reads back as its
        // own (empty) entry, never another tuple's records.
        return (recordsByTuple[tuple] ?? []).compactMap { $0 as? Record }
    }

    /// The total number of records the window pages through — read by the SAME handle the factory
    /// declared, alongside ``records(_:)``.
    ///
    /// A ``PaginatedQuery`` returns only a window; the View needs the full set's size to render
    /// position — a scroll bar over 1.2M rows, or "showing 40–65 of 1,204,882". Pre-compute it in
    /// the factory and store it (a computed property would not survive the JSON round trip):
    ///
    /// ```swift
    /// static func model(context: Context) throws -> BerthSearchViewModel {
    ///     .init(
    ///         berths: try context.records(Self.berths).map(BerthRowViewModel.init),
    ///         totalMatches: try context.totalCount(for: Self.berths)
    ///     )
    /// }
    /// ```
    ///
    /// The count is the **authorized** set the window is a view into — the same records
    /// ``records(_:)`` would return without the window. For a non-paginated load it equals
    /// `records(_:).count`.
    ///
    /// Throws exactly as ``records(_:)`` does: an unplanned handle throws (never returns 0 — a
    /// misconfiguration is not a genuine "no matches"); a handle matching more than one declared
    /// load throws.
    func totalCount<Record: FOSMVVM.Model>(for handle: LoadRequirement<Record>) throws -> Int {
        let requestName = String(describing: Request.self)
        let recordName = String(describing: Record.self)

        guard let plan else {
            throw ContainmentError.unplannedRequirement(recordType: recordName, request: requestName)
        }

        let candidates = plan.tuples(matching: handle)
        guard let tuple = candidates.first else {
            throw ContainmentError.unplannedRequirement(recordType: recordName, request: requestName)
        }
        guard candidates.count == 1 else {
            throw ContainmentError.ambiguousRequirement(
                recordType: recordName,
                request: requestName,
                matchCount: candidates.count
            )
        }

        return countsByTuple[tuple] ?? 0
    }
}
