// LiveRegistrationCoordinator.swift
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

#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Owns one live screen's dispatcher registration for the lifetime of its bind resolver (spec §3.4).
///
/// Held as `@State` by ``VMServerResolverView`` when its ViewModel is a ``LiveViewModel``: it holds
/// the ``InvalidationDispatcher/Token`` strongly, re-registers the latest response's identity set on
/// every refresh, and signals the resolver — via the observed ``refreshSignal`` — to re-fetch when a
/// matching server nudge fires. When the resolver leaves the view hierarchy the coordinator
/// deallocates, the token dies, and the registration stops (the dispatcher holds tokens weakly).
@MainActor
@Observable
final class LiveRegistrationCoordinator {
    /// Advances each time a matching nudge fires. The resolver observes it and re-fetches in place
    /// through the freshness gate — it is the signal, not the fetch (the coordinator must never
    /// capture the resolver's `View` value; see the trigger's weak capture below).
    private(set) var refreshSignal = 0

    @ObservationIgnored
    private var token: InvalidationDispatcher.Token?

    /// Whether a registration is currently held — a test/introspection seam.
    var isRegistered: Bool {
        token != nil
    }

    /// Registers (first call) or re-registers (each later call) `registrations` with `dispatcher`, so
    /// a screen whose plan touched new containers starts listening to them automatically (spec §3.4).
    func update(registrations: [ModelIdentity], dispatcher: InvalidationDispatcher) {
        let identities = Set(registrations)
        // v1: every shipped plan root resolves to an *exact* identity, so the namespace tier stays
        // empty here — it ships dormant until a namespace-scoped plan kind exists (spec §3.3 note).
        let namespaces = Set<ModelNamespace>()

        if let token {
            dispatcher.reregister(token, identities: identities, namespaces: namespaces)
        } else {
            token = dispatcher.register(identities: identities, namespaces: namespaces) { [weak self] in
                // Weak by contract: the coordinator holds the token strongly and the dispatcher holds
                // it weakly; a strong capture here would close a token → trigger → coordinator → token
                // cycle that never deallocates (InvalidationDispatcher.register's warning).
                self?.refreshSignal += 1
            }
        }
    }
}
#endif
