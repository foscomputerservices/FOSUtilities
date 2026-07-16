// ProjectionContext+Dependencies.swift
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

// swiftformat:disable docComments
// The registration deposit is a server capability — the sink writes into the serving Request's
// registration set (FOSMVVMVapor's ServeRequest installs it). So the public method lives at this
// layer even though `dependencySink` is FOSMVVM's field, the same siting rationale as `records(_:)`.
// swiftformat:enable docComments
public extension ProjectionContext {
    /// Declares that this response depends on `model`, so live clients refresh
    /// its projections when the model changes
    ///
    /// Plan-loaded records are registered automatically. Call this from your
    /// factory for data the plan can't see — state your `appState` builder
    /// snapshotted from an `Application`-hosted actor:
    ///
    /// ```swift
    /// // boot: the builder snapshots the actor (async, before the factory runs)
    /// try app.useAppState(DashboardState.self) { req in
    ///     DashboardState(status: await req.application.statusMonitor.snapshot())
    /// }
    ///
    /// // factory: read the value, register the dependency
    /// static func body<R: ServerRequest>(context: ProjectionContext<R, DashboardState>) throws -> Self
    ///     where R.ResponseBody == Self {
    ///     let status = context.appState.status
    ///     try context.registerDependency(on: status)
    ///     return .init(activeSessions: status.activeSessions)
    /// }
    /// ```
    ///
    /// The registered identity rides to the client with the response; a later
    /// ``Vapor/Application/invalidateProjections(of:)`` for the same model triggers the refresh.
    /// Register and invalidate must name the same entity — that pairing IS the
    /// live contract.
    ///
    /// - Throws: `ModelError.missingId` when `model.id` is `nil`.
    func registerDependency(on model: some FOSMVVM.Model) throws {
        try dependencySink(model.modelIdentity)
    }
}
