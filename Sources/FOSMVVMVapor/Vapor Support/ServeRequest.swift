// ServeRequest.swift
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
import Vapor

// MARK: The shared serve point (GET; the write route's refresh re-enters here)

extension Vapor.Request {
    /// Runs the declared load plan for the TYPED request instance, then projects the request's
    /// body from a value-only ``ProjectionContext``. The single serve point: the GET route
    /// passes the middleware-bound instance; a write route's refresh passes its constructed
    /// refresh instance and re-enters this same pipeline after it commits (there is no second
    /// serving path).
    func serve<SR: ServerRequest>(_ vmRequest: SR) async throws -> SR.ResponseBody
        where SR.ResponseBody: VaporResponseBodyFactory, SR.ResponseBody.Request == SR {
        // Load phase: declared requirements land in the container-record cache and the
        // tuple→keys side map (a no-op for a zero-data body). Projection reads only what
        // this deposited.
        try await executeRecordLoadPlan(for: vmRequest)

        let context = try await ProjectionContext<SR, SR.ResponseBody.AppState>(
            vmRequest: vmRequest,
            appState: resolveAppState(SR.ResponseBody.AppState.self, request: SR.self),
            appVersion: Result { try applicationVersion() },
            plan: application.recordLoadPlan(for: SR.self),
            cacheSnapshot: containerRecordCache,
            tupleKeys: tupleCacheKeys
        )
        return try SR.ResponseBody.body(context: context)
    }

    /// Resolves the projection's `AppState` value. `Void` is the zero-ceremony default (no builder,
    /// no registration). For a non-`Void` `AppState`, the builder registered with
    /// `useAppState(_:builder:)` runs here — in the load phase, with full request power — and its
    /// value is handed to the projection. The boot check in `register(request:)` guarantees a
    /// builder exists and produces this exact type, so a missing or mistyped builder here is a
    /// framework-invariant breakage, never an app misconfiguration.
    private func resolveAppState<AppState: Sendable>(_: AppState.Type, request: Any.Type) async throws -> AppState {
        if let void = (() as Any) as? AppState {
            return void
        }

        let appStateName = String(describing: AppState.self)
        let requestName = String(describing: request)

        guard let builder = application.appStateBuilder(forTypeIdentifier: ObjectIdentifier(AppState.self)) else {
            throw ContainmentError.appStateInconsistency(
                request: requestName,
                appStateType: appStateName,
                reason: "no builder was registered at request time, though the boot check requires one"
            )
        }

        let built = try await builder.build(self)
        guard let typed = built as? AppState else {
            throw ContainmentError.appStateInconsistency(
                request: requestName,
                appStateType: appStateName,
                reason: "the registered builder produced \(String(describing: type(of: built))), not \(appStateName)"
            )
        }
        return typed
    }
}
