// ProjectionContext.swift
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
import Vapor

/// Everything a projection may see: the typed request, the app-declared state, and typed
/// reads of the records the plan loaded. Nothing else.
///
/// ```swift
/// static func body(context: ProjectionContext<Request, SessionBanner>) throws -> Self {
///     let berths = try context.records(Self.berths)              // own handle
///     let crew   = try context.records(CrewListViewModel.crew)   // a child's
///     return .init(..., signedInAs: context.appState.userName)
/// }
/// ```
///
/// Read it inside `body(context:)` and let it go: the context must not escape the
/// projection (no capturing it in a spawned `Task`) — reads are contracted to the request's
/// handler task, like everything request-scoped.
public struct ProjectionContext<Request: ServerRequest, AppState: Sendable>: ViewModelFactoryContext, @unchecked Sendable {
    // @unchecked Sendable: `records` are live Fluent model classes (not statically Sendable),
    // captured here as a value snapshot of the request's container-record cache. The mirror of
    // ContainerRecordCache's posture and justification — the snapshot is only ever READ, and
    // only within the request's handler task (the context must not escape the projection). No
    // reader mutates the shared model instances.

    /// The typed request — query, sort, pagination, selectors.
    public let vmRequest: Request

    /// The app-declared per-request value, built by the closure registered with
    /// `useAppState(_:builder:)` — the sanctioned home for session-derived display data.
    /// `Void` when nothing is registered.
    public let appState: AppState

    /// The client's requested SystemVersion (``ViewModelFactoryContext``).
    public var appVersion: SystemVersion {
        get throws { try resolvedAppVersion.get() }
    }

    /// The records a declared requirement loaded — read by the SAME static handle the factory
    /// declared. Any handle in the request's plan is readable, including a child factory's
    /// (that is how parents compose their children).
    ///
    /// A handle that never reached the plan THROWS — never returns `[]`. A silently-empty
    /// screen is a misconfiguration's invisible mode; the throw names the record type and the
    /// request, and points at the declaration that was forgotten. A handle that resolves to
    /// more than one declared load also throws — the framework never guesses which set to
    /// return; disambiguate the declarations.
    ///
    /// Treat the returned records as read-only: they are shared snapshots of what the load
    /// phase produced — do not mutate them. Mutation belongs to the write path, which
    /// invalidates and re-serves.
    public func records<Record: FOSMVVM.Model>(_ handle: LoadRequirement<Record>) throws -> [Record] {
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

        return typedRecords(of: Record.self, for: tuple)
    }

    // MARK: Internal construction

    private let resolvedAppVersion: Result<SystemVersion, any Error>
    private let plan: RecordLoadPlan?
    private let cacheSnapshot: [ContainerRecordCacheKey: [any DataModel]]
    private let tupleKeys: [RecordLoadPlan.Tuple: [ContainerRecordCacheKey]]

    init(
        vmRequest: Request,
        appState: AppState,
        appVersion: Result<SystemVersion, any Error>,
        plan: RecordLoadPlan?,
        cacheSnapshot: [ContainerRecordCacheKey: [any DataModel]],
        tupleKeys: [RecordLoadPlan.Tuple: [ContainerRecordCacheKey]]
    ) {
        self.vmRequest = vmRequest
        self.appState = appState
        self.resolvedAppVersion = appVersion
        self.plan = plan
        self.cacheSnapshot = cacheSnapshot
        self.tupleKeys = tupleKeys
    }
}

private extension ProjectionContext {
    /// The records the matched tuple loaded: exactly the cache entries the executor deposited
    /// for THAT tuple, read back through its tuple→keys side map (one key per descent branch,
    /// in deposit order — already deterministic). No same-type aggregation across tuples: two
    /// same-typed declared loads never blend, and a denied load reads back as its own (empty)
    /// entries, never another tuple's records.
    func typedRecords<Record: FOSMVVM.Model>(of _: Record.Type, for tuple: RecordLoadPlan.Tuple) -> [Record] {
        (tupleKeys[tuple] ?? [])
            .flatMap { cacheSnapshot[$0] ?? [] }
            .compactMap { $0 as? Record }
    }
}
