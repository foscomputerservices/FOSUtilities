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

public extension RoutesBuilder {
    /// Registers a read request's route (GET) on this route group.
    ///
    /// The group you call it on decides the middleware that guards the route —
    /// mount privileged requests behind your credential group, public ones on the
    /// `Application` itself (an `Application` is a `RoutesBuilder`):
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///     let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    ///     try authed.register(request: DockPageRequest.self, app: app)
    ///     try app.register(request: LandingPageRequest.self, app: app)
    /// }
    /// ```
    ///
    /// One door for every request — a body that is a ViewModel and a body that is
    /// not (a report, an export) register the same way.
    ///
    /// >  *ServerRequest* provides a protocol extension that sets *ServerRequest/path* based on
    /// >   the *ServerRequest/RequestBody* and *ServerRequest/ResponseBody* types. Thus, the
    /// >   route's path is automatically maintained and there is never a path collision or
    /// >   confusion between the client and server. Mount on **middleware-only** groups: a
    /// >   path-prefixing group would change the served URL while clients derive it from the
    /// >   type — registration rejects that at boot.
    ///
    /// Register the app's containers (``Vapor/Application/register(_:migration:)``) **before**
    /// calling this — a composable body's load plan is derived and validated here, against
    /// `app`'s registered containers. Every door derives the plan: where a request mounts is
    /// your decision; that its plan is derived is not.
    ///
    /// A write request (Create/Update/Delete) has its own overload; register it the same way
    /// (`try authed.register(request: BerthUpdateRequest.self, app: app)`), and Swift picks
    /// the write door. A write request that reaches *this* read door — because its
    /// Query/RequestBody miss the write overload's constraints, or because its protocol
    /// (Replace/Destroy) is not yet supported — fails fast at boot rather than registering
    /// GET-only (which would silently drop the write).
    ///
    /// - Parameters:
    ///   - request: A *ServerRequest* whose *ResponseBody* is a ``VaporResponseBodyFactory``
    ///   - app: The application this route serves — the request's load plan is derived
    ///     into and validated against it
    func register<SR: ServerRequest>(request _: SR.Type, app: Vapor.Application) throws
        where SR.ResponseBody: VaporResponseBodyFactory {
        // Boot-time fail-fast: overload resolution can send a write request to this read door.
        // Catch it here — a GET-only registration of a write request would be the silent mode.
        try rejectWriteProtocolAtReadDoor(SR.self)
        // Boot-time fail-fast: a non-Void projection AppState needs a useAppState(_:) builder, and it
        // must already be registered — misconfiguration is a boot error, not a first-request surprise.
        try app.requireAppStateBuilder(appStateType: SR.ResponseBody.AppState.self, request: SR.self)
        // Boot-derivation seam: a composable ResponseBody's RecordLoadPlan is derived + validated
        // HERE, once per request type. A non-composable (zero-data) body derives no plan.
        try app.registerRecordLoadPlan(for: SR.self)
        try mountVerifyingPath(SR.self, app: app) {
            try register(collection: GuardedRequestController<SR>(actions: [
                .show: { req, bound in try await req.serve(bound) }
            ]))
        }
    }
}

public extension RoutesBuilder {
    /// Registers a create request's route (POST) on this route group, plus the request's own read
    /// plan for the response.
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///     let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    ///     try authed.register(request: CreateBerthRequest.self, app: app)
    /// }
    /// ```
    ///
    /// Mount on **middleware-only** groups: a path-prefixing group is rejected at boot, because clients
    /// derive the served URL from the request type.
    ///
    /// The framework instantiates a fresh `Target()`, calls the body's `apply`, sets the container
    /// foreign key from the candidate scope, and saves — then re-serves the request itself to build
    /// its `ResponseBody` from the refreshed records.
    ///
    /// - Parameters:
    ///   - request: A *CreateRequest* whose *ResponseBody* is a ``VaporResponseBodyFactory``
    ///   - app: The application this route serves — the request's candidate and response load plans
    ///     are derived into and validated against it
    func register<SR: CreateRequest>(request _: SR.Type, app: Vapor.Application) throws
        where SR.RequestBody: DataModelWriter,
        SR.ResponseBody: VaporResponseBodyFactory {
        try app.requireAppStateBuilder(appStateType: SR.ResponseBody.AppState.self, request: SR.self)
        try app.registerRecordLoadPlan(for: SR.self)
        try app.deriveCandidatePlan(for: SR.self, writer: SR.RequestBody.self, expectedOperation: .createRecords)
        try mountVerifyingPath(SR.self, app: app) {
            try register(collection: GuardedRequestController<SR>(actions: [
                .create: { req, bound in
                    let body = try req.content.decode(SR.RequestBody.self)
                    return try await req.serveCreate(bound, body: body)
                }
            ]))
        }
    }

    /// Registers an update request's route (PATCH) on this route group, plus the request's own read
    /// plan for the response. Swift picks this door when the update request's Query names a
    /// target and its RequestBody writes.
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///     let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    ///     try authed.register(request: UpdateBerthRequest.self, app: app)
    /// }
    /// ```
    ///
    /// Mount on **middleware-only** groups: a path-prefixing group is rejected at boot, because clients
    /// derive the served URL from the request type.
    ///
    /// Register the app's containers and the request's response dependencies (apex resolver,
    /// `useAppState`) **before** calling this — the candidate plan and the response read plan are
    /// derived and validated here. After the update commits, the server re-serves the request itself
    /// through the genuine read pipeline to build its `ResponseBody`.
    ///
    /// - Parameters:
    ///   - request: An *UpdateRequest* whose *ResponseBody* is a ``VaporResponseBodyFactory``
    ///   - app: The application this route serves — the request's candidate and response load plans
    ///     are derived into and validated against it
    func register<SR: UpdateRequest>(request _: SR.Type, app: Vapor.Application) throws
        where SR.RequestBody: DataModelWriter,
        SR.Query: TargetedQuery,
        SR.ResponseBody: VaporResponseBodyFactory {
        try app.requireAppStateBuilder(appStateType: SR.ResponseBody.AppState.self, request: SR.self)
        try app.registerRecordLoadPlan(for: SR.self)
        try app.deriveCandidatePlan(for: SR.self, writer: SR.RequestBody.self, expectedOperation: .writeRecords)
        try mountVerifyingPath(SR.self, app: app) {
            try register(collection: GuardedRequestController<SR>(actions: [
                .update: { req, bound in
                    let body = try req.content.decode(SR.RequestBody.self)
                    return try await req.serveUpdate(bound, body: body)
                }
            ]))
        }
    }

    /// Registers a delete request's route (DELETE) on this route group, plus the request's own read
    /// plan for the response. A delete body declares its candidate set only
    /// (``WriteTargetProviding``); deletion is framework-owned.
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///     let authed = app.grouped(ClientCredentialMiddleware(verifier: myVerifier))
    ///     try authed.register(request: DeleteBerthRequest.self, app: app)
    /// }
    /// ```
    ///
    /// Mount on **middleware-only** groups: a path-prefixing group is rejected at boot, because clients
    /// derive the served URL from the request type.
    ///
    /// After the delete commits, the server re-serves the request itself to build its `ResponseBody`
    /// from the refreshed records (or `EmptyBody` when there is nothing to return).
    ///
    /// - Parameters:
    ///   - request: A *DeleteRequest* whose *ResponseBody* is a ``VaporResponseBodyFactory``
    ///   - app: The application this route serves — the request's candidate and response load plans
    ///     are derived into and validated against it
    func register<SR: DeleteRequest>(request _: SR.Type, app: Vapor.Application) throws
        where SR.RequestBody: WriteTargetProviding,
        SR.Query: TargetedQuery,
        SR.ResponseBody: VaporResponseBodyFactory {
        try app.requireAppStateBuilder(appStateType: SR.ResponseBody.AppState.self, request: SR.self)
        try app.registerRecordLoadPlan(for: SR.self)
        try app.deriveCandidatePlan(for: SR.self, writer: SR.RequestBody.self, expectedOperation: .deleteRecords)
        try mountVerifyingPath(SR.self, app: app) {
            try register(collection: GuardedRequestController<SR>(actions: [
                .delete: { req, bound in try await req.serveDelete(bound) }
            ]))
        }
    }
}

// swiftformat:disable docComments
// Overload resolution sends a write-protocol conformer that misses the write doors' constraints
// to the base read door. Reject it there: Create/Update/Delete conformers name unmet write
// constraints; Replace/Destroy name the not-yet-supported protocol.
// swiftformat:enable docComments
private func rejectWriteProtocolAtReadDoor<SR: ServerRequest>(_: SR.Type) throws {
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

// swiftformat:disable docComments
// Runs `mount` (the `register(collection:)` that appends the request's route), then verifies
// every route it appended carries exactly the type-derived path. A middleware-only group adds no
// path components and passes untouched; a path-prefixing group (`app.grouped("admin")`) shifts the
// served URL away from the type — the client derives the URL from the request type, so that
// divergence is a boot error, not a silent runtime 404.
//
// Both the before-snapshot and the after-scan read `app.routes.all` — never the receiver builder:
// a `MiddlewareGroup` has no route storage, forwarding registrations up to the root. `Routes.all`
// is append-only and boot registration is single-threaded, so the suffix past the snapshot is
// exactly the routes this registration added.
//
// The check assumes the receiver builder belongs to `app`: registering a builder derived from a
// different Application is outside the contract — the suffix past `app.routes.all`'s snapshot would
// hold none of this registration's routes, so the path check would pass vacuously.
// swiftformat:enable docComments
private func mountVerifyingPath<SR: ServerRequest>(
    _: SR.Type,
    app: Vapor.Application,
    _ mount: () throws -> Void
) throws {
    let priorCount = app.routes.all.count
    try mount()
    let expected = SR.path.pathComponents.map(\.description)
    for route in app.routes.all[priorCount...] {
        let mounted = route.path.map(\.description)
        if mounted != expected {
            throw ContainmentError.pathPrefixedMount(
                request: String(describing: SR.self),
                mountedPath: "/" + mounted.joined(separator: "/")
            )
        }
    }
}
