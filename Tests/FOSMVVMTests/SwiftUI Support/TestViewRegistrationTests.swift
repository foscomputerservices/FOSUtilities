// TestViewRegistrationTests.swift
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

#if canImport(SwiftUI) && DEBUG
import FOSFoundation
@testable import FOSMVVM
import Foundation
import SwiftUI
import Testing

// ── Honest gap (needs a hosted UI test) ───────────────────────────────────────────────────────────
// This covers the half of the contract that is reachable headless: a view registered through
// `MVVMEnvironment.registerTestView(_:)` is afterwards resolvable by the key the FOSTestingUI
// harness computes, and its factory reports a bad payload by THROWING rather than trapping (which
// is what lets `testHost()` turn it into a diagnostic).
//
// Not reachable here: that `testHost()` actually consults this registry before the first render.
// `TestingView.init` runs only when SwiftUI drives the view, and proving the timing needs a real
// launch — a host app plus a UI-test bundle, neither of which Package.swift can declare. That
// belongs to a consumer app's UI-test target. What IS pinned below is the regression that caused
// this file to exist: registration reaching a process-wide home, with no MVVMEnvironment instance
// anywhere in the call.
//
// `.serialized`: the registry is process-global mutable state, so these tests must not interleave
// with each other. Each restores the registry it found.

@Suite("Test view registration", .serialized)
@MainActor
struct TestViewRegistrationTests {
    /// The lookup key is the one the harness computes from the ViewModel type — see
    /// `ViewModelViewTestCase.presentView`, which puts exactly this into `__FOS_ViewModelType`.
    /// Asserting through it tests the agreed protocol between the two sides.
    private func harnessKey<VM: ViewModel>(for viewModel: VM.Type) -> String {
        String(describing: VM.self)
    }

    private func withRestoredRegistry(_ body: () throws -> Void) rethrows {
        let saved = MVVMEnvironment.registeredTestTypes
        defer { MVVMEnvironment.registeredTestTypes = saved }
        try body()
    }

    @Test("A registered view is resolvable — with no MVVMEnvironment instance in the call")
    func registeredViewIsResolvable() throws {
        try withRestoredRegistry {
            MVVMEnvironment.registeredTestTypes = [:]

            MVVMEnvironment.registerTestView(ProbeView.self)

            #expect(MVVMEnvironment.registeredTestTypes[harnessKey(for: TestViewModel.self)] != nil)
        }
    }

    @Test("An unregistered ViewModel resolves to nothing")
    func unregisteredViewModelResolvesToNothing() throws {
        try withRestoredRegistry {
            MVVMEnvironment.registeredTestTypes = [:]

            MVVMEnvironment.registerTestView(ProbeView.self)

            #expect(MVVMEnvironment.registeredTestTypes[harnessKey(for: OtherProbeViewModel.self)] == nil)
        }
    }

    @Test("Registering several views leaves all of them resolvable")
    func severalViewsAllResolve() throws {
        try withRestoredRegistry {
            MVVMEnvironment.registeredTestTypes = [:]

            MVVMEnvironment.registerTestView(ProbeView.self)
            MVVMEnvironment.registerTestView(OtherProbeView.self)

            #expect(MVVMEnvironment.registeredTestTypes[harnessKey(for: TestViewModel.self)] != nil)
            #expect(MVVMEnvironment.registeredTestTypes[harnessKey(for: OtherProbeViewModel.self)] != nil)
        }
    }

    @Test("Registering the same view twice is not an error and leaves one entry")
    func repeatedRegistrationIsHarmless() throws {
        try withRestoredRegistry {
            MVVMEnvironment.registeredTestTypes = [:]

            MVVMEnvironment.registerTestView(ProbeView.self)
            MVVMEnvironment.registerTestView(ProbeView.self)

            #expect(MVVMEnvironment.registeredTestTypes.count == 1)
        }
    }

    @Test("A registered factory throws on an undecodable payload rather than trapping")
    func factoryThrowsOnUndecodablePayload() throws {
        try withRestoredRegistry {
            MVVMEnvironment.registeredTestTypes = [:]

            MVVMEnvironment.registerTestView(ProbeView.self)
            let registration = try #require(
                MVVMEnvironment.registeredTestTypes[harnessKey(for: TestViewModel.self)]
            )

            // testHost() reports decode failures as a diagnostic, which is only possible because
            // the factory throws. If this ever trapped instead, that reporting path would be dead.
            #expect(throws: (any Error).self) {
                _ = try registration.factory(Data("not a ViewModel".utf8))
            }
        }
    }

    @Test("The scrollable declaration reaches the registry — default false, declared true")
    func scrollableDeclarationReachesTheRegistry() throws {
        try withRestoredRegistry {
            MVVMEnvironment.registeredTestTypes = [:]

            MVVMEnvironment.registerTestView(ProbeView.self)
            MVVMEnvironment.registerTestView(OtherProbeView.self, scrollable: true)

            #expect(
                MVVMEnvironment.registeredTestTypes[harnessKey(for: TestViewModel.self)]?
                    .scrollable == false
            )
            #expect(
                MVVMEnvironment.registeredTestTypes[harnessKey(for: OtherProbeViewModel.self)]?
                    .scrollable == true
            )
        }
    }
}

// MARK: Probes

private struct ProbeView: ViewModelView {
    let viewModel: TestViewModel

    var body: some View {
        EmptyView()
    }

    init(viewModel: TestViewModel) {
        self.viewModel = viewModel
    }
}

@ViewModel
private struct OtherProbeViewModel: ViewModel {
    var vmId = ViewModelId()

    init() {}

    static func stub() -> Self {
        .init()
    }
}

private struct OtherProbeView: ViewModelView {
    let viewModel: OtherProbeViewModel

    var body: some View {
        EmptyView()
    }

    init(viewModel: OtherProbeViewModel) {
        self.viewModel = viewModel
    }
}
#endif
