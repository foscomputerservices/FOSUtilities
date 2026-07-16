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

/// Everything a projection may see: the typed request, the app-declared state, and typed
/// reads of the records the plan loaded. Nothing else.
///
/// ```swift
/// static func body<R: ServerRequest>(context: ProjectionContext<R, SessionBanner>) throws -> Self where R.ResponseBody == Self {
///     let berths = try context.records(Self.berths)              // own handle
///     let crew   = try context.records(CrewListViewModel.crew)   // a child's
///     return .init(..., signedInAs: context.appState.userName)
/// }
/// ```
///
/// Read it inside `body(context:)` and let it go: the context must not escape the
/// projection (no capturing it in a spawned `Task`) — reads are contracted to the request's
/// handler task, like everything request-scoped. The typed `records(_:)` accessor is a
/// server capability supplied by FOSMVVMVapor.
public struct ProjectionContext<Request: ServerRequest, AppState: Sendable>: @unchecked Sendable {
    // @unchecked Sendable: the records vended by `recordsByTuple` are live model class instances
    // (not statically Sendable), captured here as a value snapshot of the request's loaded records.
    // The snapshot is only ever READ, and only within the request's handler task (the context must
    // not escape the projection). No reader mutates the shared instances. The `dependencySink`
    // closure is likewise invoke-only on that same handler task (see its field doc) — never stored,
    // never called off-task.

    /// The typed request — query, sort, pagination, selectors.
    public let vmRequest: Request

    /// The app-declared per-request value, built by the closure registered with
    /// `useAppState(_:builder:)` — the sanctioned home for session-derived display data.
    /// `Void` when nothing is registered.
    public let appState: AppState

    // package: the plan and the tuple→records snapshot are read by FOSMVVMVapor's `records(_:)`
    // accessor — the typed containment read lives at the layer that owns the containment types.
    // Never a public surface: consumers read records through `records(_:)`, never the raw storage.
    package let plan: RecordLoadPlan?
    package let recordsByTuple: [RecordLoadPlan.Tuple: [any Model]]
    /// Per-tuple total the window is a view into; empty for a zero-data context. Read via
    /// FOSMVVMVapor's `totalCount(for:)`, never as raw storage.
    package let countsByTuple: [RecordLoadPlan.Tuple: Int]

    /// Deposits one registered dependency identity into the serving request's
    /// registration set. Installed at construction — required, never defaulted: a
    /// silently-dropping sink would be a misconfiguration's invisible mode. Invoked
    /// only within the projection, on the request's handler task (the same
    /// no-escape contract the record snapshot already relies on).
    package let dependencySink: (ModelIdentity) -> Void

    package init(
        vmRequest: Request,
        appState: AppState,
        plan: RecordLoadPlan,
        recordsByTuple: [RecordLoadPlan.Tuple: [any Model]],
        countsByTuple: [RecordLoadPlan.Tuple: Int] = [:],
        dependencySink: @escaping (ModelIdentity) -> Void
    ) {
        self.vmRequest = vmRequest
        self.appState = appState
        self.plan = plan
        self.recordsByTuple = recordsByTuple
        self.countsByTuple = countsByTuple
        self.dependencySink = dependencySink
    }

    package init(
        vmRequest: Request,
        appState: AppState,
        dependencySink: @escaping (ModelIdentity) -> Void
    ) {
        self.vmRequest = vmRequest
        self.appState = appState
        self.plan = nil
        self.recordsByTuple = [:]
        self.countsByTuple = [:]
        self.dependencySink = dependencySink
    }
}
