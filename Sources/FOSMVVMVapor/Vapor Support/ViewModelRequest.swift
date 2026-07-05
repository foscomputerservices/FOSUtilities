// ViewModelRequest.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

import FOSMVVM
import Vapor

public extension Vapor.Application {
    /// Registers a read request's route (GET). One door for every request — a body that is a
    /// ViewModel and a body that is not (a report, an export) register the same way.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///    try app.register(request: DockPageRequest.self)
    /// }
    /// ```
    ///
    /// >  *ServerRequest* provides a protocol extension that sets *ServerRequest/path* based on
    /// >   the *ServerRequest/RequestBody* and *ServerRequest/ResponseBody* types. Thus, the
    /// >   route's path is automatically maintained and there is never a path collision or
    /// >   confusion between the client and server.
    ///
    /// Register the app's containers (``Application/register(_:migration:)``) **before** calling
    /// this — a composable body's load plan is derived and validated here, against the containers
    /// registered so far. Registration is Application-only by construction: there is no
    /// grouped/`Routes`-level door, so a composable body can never be registered without its plan.
    ///
    /// A write request (Create/Update/Delete) has its own overload; register it the same way
    /// (`try app.register(request: UpdateBerthRequest.self)`), and Swift picks the write door. A
    /// write request that reaches *this* read door — because its Query/RequestBody miss the write
    /// overload's constraints, or because its protocol (Replace/Destroy) is not yet supported —
    /// fails fast at boot rather than registering GET-only (which would silently drop the write).
    ///
    /// - Parameter request: A *ServerRequest* whose *ResponseBody* is a ``VaporResponseBodyFactory``
    func register<SR: ServerRequest>(request _: SR.Type) throws
        where SR.ResponseBody: VaporResponseBodyFactory, SR.ResponseBody.Request == SR {
        // Boot-time fail-fast: overload resolution can send a write request to this read door.
        // Catch it here — a GET-only registration of a write request would be the silent mode.
        try rejectWriteProtocolAtReadDoor(SR.self)
        // Boot-time fail-fast: a non-Void projection AppState needs a useAppState(_:) builder, and it
        // must already be registered — misconfiguration is a boot error, not a first-request surprise.
        try requireAppStateBuilder(appStateType: SR.ResponseBody.AppState.self, request: SR.self)
        // Boot-derivation seam: a composable ResponseBody's RecordLoadPlan is derived + validated
        // HERE, once per request type. A non-composable (zero-data) body derives no plan.
        try registerRecordLoadPlan(for: SR.self)
        try routes.register(collection: GuardedRequestController<SR>(actions: [
            .show: { req, bound in try await req.serve(bound) }
        ]))
    }

    /// Registers an update request's routes: PATCH for the write, plus the refresh request's read
    /// plan for the fall-through. Swift picks this door when the update request's Query names a
    /// target and its RequestBody writes.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///    try app.register(request: UpdateBerthRequest.self)
    /// }
    /// ```
    ///
    /// Register the app's containers and the refresh request's dependencies (apex resolver,
    /// `useAppState`) **before** calling this — the candidate plan and the refresh read plan are
    /// derived and validated here. After the update commits, the server re-serves the request's
    /// ``UpdateRequest/refreshRequest()`` through the genuine read pipeline.
    func register<SR: UpdateRequest>(request _: SR.Type) throws
        where SR.RequestBody: DataModelWriter,
        SR.Query: TargetedQuery,
        SR.RefreshRequest.ResponseBody: VaporResponseBodyFactory,
        SR.RefreshRequest.ResponseBody.Request == SR.RefreshRequest {
        try registerRefreshPlan(for: SR.RefreshRequest.self)
        try deriveCandidatePlan(for: SR.self, writer: SR.RequestBody.self, expectedOperation: .writeRecords)
        try routes.register(collection: GuardedRequestController<SR>(actions: [
            .update: { req, bound in
                guard let body = bound.requestBody else {
                    throw ServerRequestControllerError.missingRequestBody
                }
                return try await req.serveUpdate(bound, body: body)
            }
        ]))
    }

    /// Registers a create request's routes: POST for the write, plus the refresh request's read
    /// plan for the fall-through.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///    try app.register(request: CreateBerthRequest.self)
    /// }
    /// ```
    ///
    /// The framework instantiates a fresh `Target()`, calls the body's `apply`, sets the container
    /// foreign key from the candidate scope, and saves — then re-serves the request's
    /// ``CreateRequest/refreshRequest()``.
    func register<SR: CreateRequest>(request _: SR.Type) throws
        where SR.RequestBody: DataModelWriter,
        SR.RefreshRequest.ResponseBody: VaporResponseBodyFactory,
        SR.RefreshRequest.ResponseBody.Request == SR.RefreshRequest {
        try registerRefreshPlan(for: SR.RefreshRequest.self)
        try deriveCandidatePlan(for: SR.self, writer: SR.RequestBody.self, expectedOperation: .createRecords)
        try routes.register(collection: GuardedRequestController<SR>(actions: [
            .create: { req, bound in
                guard let body = bound.requestBody else {
                    throw ServerRequestControllerError.missingRequestBody
                }
                return try await req.serveCreate(bound, body: body)
            }
        ]))
    }

    /// Registers a delete request's routes: DELETE for the write, plus the refresh request's read
    /// plan for the fall-through. A delete body declares its candidate set only
    /// (``WriteTargetProviding``); deletion is framework-owned.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///    try app.register(request: DeleteBerthRequest.self)
    /// }
    /// ```
    ///
    /// After the delete commits, the server re-serves the request's ``DeleteRequest/refreshRequest()``.
    func register<SR: DeleteRequest>(request _: SR.Type) throws
        where SR.RequestBody: WriteTargetProviding,
        SR.Query: TargetedQuery,
        SR.RefreshRequest.ResponseBody: VaporResponseBodyFactory,
        SR.RefreshRequest.ResponseBody.Request == SR.RefreshRequest {
        try registerRefreshPlan(for: SR.RefreshRequest.self)
        try deriveCandidatePlan(for: SR.self, writer: SR.RequestBody.self, expectedOperation: .deleteRecords)
        try routes.register(collection: GuardedRequestController<SR>(actions: [
            .delete: { req, bound in try await req.serveDelete(bound) }
        ]))
    }
}

private extension Vapor.Application {
    /// The read plan the write's refresh fall-through re-serves. A non-Void refresh AppState needs
    /// its builder registered before the write request (same rule as the read door).
    func registerRefreshPlan<Refresh: ServerRequest>(for _: Refresh.Type) throws
        where Refresh.ResponseBody: VaporResponseBodyFactory, Refresh.ResponseBody.Request == Refresh {
        try requireAppStateBuilder(appStateType: Refresh.ResponseBody.AppState.self, request: Refresh.self)
        try registerRecordLoadPlan(for: Refresh.self)
    }

    /// Overload resolution sends a write-protocol conformer that misses the write doors' constraints
    /// to the base read door. Reject it there: Create/Update/Delete conformers name unmet write
    /// constraints; Replace/Destroy name the not-yet-supported protocol.
    func rejectWriteProtocolAtReadDoor<SR: ServerRequest>(_: SR.Type) throws {
        let name = String(describing: SR.self)
        if SR.self is any ReplaceRequest.Type || SR.self is any DestroyRequest.Type {
            throw ContainmentError.unsupportedWriteProtocol(request: name)
        }
        if SR.self is any UpdateRequest.Type
            || SR.self is any CreateRequest.Type
            || SR.self is any DeleteRequest.Type {
            throw ContainmentError.writeRequestAtReadDoor(request: name)
        }
    }
}
