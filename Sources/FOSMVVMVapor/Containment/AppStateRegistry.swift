// AppStateRegistry.swift
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

public extension Vapor.Application {
    /// Registers the builder for a factory's `AppState` — the one sanctioned place session-derived
    /// display data ("signed in as…") is computed, with full request power (it runs in the load
    /// phase, not the projection), then handed to the projection as a plain value.
    ///
    /// ```swift
    /// // in configure(_:)
    /// try app.useAppState(SessionBanner.self) { req in
    ///     SessionBanner(userName: try req.auth.require(User.self).displayName)
    /// }
    /// ```
    ///
    /// Register the builder **before** the requests that project it — a request whose `ResponseBody`
    /// declares a non-`Void` `AppState` with no builder registered fails at ``register(request:)``.
    ///
    /// The builder is keyed by the `AppState` type: everything the projection needs about the session
    /// arrives through the value it returns. Capturing the request's power in the closure is
    /// legitimate here — this is the load phase — but the value the projection receives is all it sees.
    ///
    /// - Throws: if a builder for this `AppState` type is already registered — exactly one builder per
    ///   type, caught at boot (silently keeping the last registration would hide the duplicate).
    func useAppState<AppState: Sendable>(
        _ type: AppState.Type,
        builder: @escaping @Sendable (Vapor.Request) async throws -> AppState
    ) throws {
        let key = ObjectIdentifier(type)
        var registry = storage[AppStateBuilderStore.self] ?? [:]
        guard registry[key] == nil else {
            throw ContainmentError.duplicateAppStateBuilder(appStateType: String(describing: type))
        }
        // Erase the typed builder for storage; the concrete `AppState` is recovered at build time
        // by a typed downcast in the generic context that knows AppState (Request.resolveAppState).
        registry[key] = AppStateBuilder { req in try await builder(req) }
        storage[AppStateBuilderStore.self] = registry
    }
}

extension Application {
    /// Read side of the seam — consumed by the ``register(request:)`` boot check and by
    /// Request.resolveAppState at request time (same module).
    func appStateBuilder(forTypeIdentifier id: ObjectIdentifier) -> AppStateBuilder? {
        storage[AppStateBuilderStore.self]?[id]
    }

    /// Boot-time fail-fast: a request whose `ResponseBody` declares a non-`Void` `AppState` must have
    /// a builder registered before it is. `Void` needs none — the zero-ceremony default.
    func requireAppStateBuilder(appStateType: Any.Type, request: Any.Type) throws {
        guard appStateType != Void.self else {
            return
        }
        guard appStateBuilder(forTypeIdentifier: ObjectIdentifier(appStateType)) != nil else {
            throw ContainmentError.missingAppStateBuilder(
                request: String(describing: request),
                appStateType: String(describing: appStateType)
            )
        }
    }
}

/// A registered `AppState` builder, type-erased for storage in a type-keyed registry. The concrete
/// `AppState` is recovered by a typed downcast in the generic context that knows AppState at build
/// time (the mirror of `ApexContainerResolver`, here keyed by the `AppState` type rather than held
/// as one closure).
struct AppStateBuilder: Sendable {
    let build: @Sendable (Vapor.Request) async throws -> any Sendable
}

private struct AppStateBuilderStore: StorageKey {
    typealias Value = [ObjectIdentifier: AppStateBuilder]
}
