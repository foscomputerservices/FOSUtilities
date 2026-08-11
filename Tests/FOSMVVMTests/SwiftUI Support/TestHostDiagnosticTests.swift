// TestHostDiagnosticTests.swift
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
@testable import FOSMVVM
import Foundation
import Testing

// ── Honest gap (needs a hosted UI test) ───────────────────────────────────────────────────────────
// These pin what each diagnostic must TELL the user, not its prose — the wording is free to change
// so long as the facts below survive. What is NOT reachable here is the delivery: that
// `TestingView.init` actually reaches `reportAndStop` on a misconfigured app, and that the message
// lands in an `xcodebuild` log. `reportAndStop` traps, and a trap cannot be caught by a test; the
// call site needs SwiftUI to drive it. That path needs a host app target FOSUtilities does not ship
// (a UI-test bundle cannot be declared in Package.swift), so it belongs to a consumer app's UI-test
// target. The message CONTENT — the expensive part to get right, and the part a user reads at 2am —
// is pinned here, and portably: these run on the Linux leg, the only one CI executes.

@Suite("TestHost diagnostics")
struct TestHostDiagnosticTests {
    @Test("Names the ViewModel the harness asked for")
    func namesTheRequestedViewModel() {
        let message = TestHostDiagnostic.unregisteredView(
            viewModelType: "DashboardViewModel",
            registered: ["CardViewModel"]
        )

        #expect(message.contains("DashboardViewModel"))
    }

    @Test("Lists every ViewModel that IS registered, so the user can spot a near-miss")
    func listsTheRegisteredViewModels() {
        let message = TestHostDiagnostic.unregisteredView(
            viewModelType: "DashboardViewModel",
            registered: ["CardViewModel", "LandingPageViewModel"]
        )

        #expect(message.contains("CardViewModel"))
        #expect(message.contains("LandingPageViewModel"))
    }

    @Test("An empty registry is reported as its own cause — nothing registered, not a typo")
    func emptyRegistryReportsItsOwnCause() {
        let message = TestHostDiagnostic.unregisteredView(
            viewModelType: "DashboardViewModel",
            registered: []
        )

        // The two causes must not be confusable: an empty registry means the calls are missing or
        // ran too late, which is a different fix from "you registered the wrong one".
        #expect(message.contains("No test views are registered at all"))
        #expect(!message.contains("Some test views are registered"))
    }

    @Test("A populated registry missing this one reports the other cause")
    func populatedRegistryReportsTheOtherCause() {
        let message = TestHostDiagnostic.unregisteredView(
            viewModelType: "DashboardViewModel",
            registered: ["CardViewModel"]
        )

        #expect(message.contains("Some test views are registered"))
        #expect(!message.contains("No test views are registered at all"))
    }

    @Test("Directs the user to init(), the only supported registration site")
    func directsTheUserToInit() {
        let empty = TestHostDiagnostic.unregisteredView(viewModelType: "AVM", registered: [])
        let populated = TestHostDiagnostic.unregisteredView(viewModelType: "AVM", registered: ["BVM"])

        // Both causes share one fix; neither may leave the user without it.
        for message in [empty, populated] {
            #expect(message.contains("init()"))
            #expect(message.contains("registerTestView"))
        }
    }

    @Test("Warns against the late-registration sites that caused the misconfiguration")
    func warnsAgainstLateRegistrationSites() {
        let message = TestHostDiagnostic.unregisteredView(viewModelType: "AVM", registered: [])

        // The empty-registry case is the one where "you registered, but too late" is the likely
        // story, so it must name where late registration hides.
        #expect(message.contains("mvvmEnv"))
        #expect(message.contains(".onAppear"))
        #expect(message.contains(".task"))
    }

    @Test("A decode failure surfaces the underlying error, not just the type")
    func decodeFailureSurfacesTheUnderlyingError() {
        struct SentinelError: Error, CustomStringConvertible {
            var description: String {
                "keyNotFound: sentinelKey"
            }
        }

        let message = TestHostDiagnostic.undecodableViewModel(
            viewModelType: "DashboardViewModel",
            error: SentinelError()
        )

        #expect(message.contains("DashboardViewModel"))
        #expect(message.contains("keyNotFound: sentinelKey"))
    }

    @Test("Every diagnostic points at the documentation that carries the full contract")
    func everyDiagnosticPointsAtTheDocumentation() {
        let messages = [
            TestHostDiagnostic.unregisteredView(viewModelType: "AVM", registered: []),
            TestHostDiagnostic.unregisteredView(viewModelType: "AVM", registered: ["BVM"]),
            TestHostDiagnostic.undecodableViewModel(viewModelType: "AVM", error: CancellationError())
        ]

        for message in messages {
            #expect(message.contains("MVVMEnvironment.registerTestView(_:)"))
        }
    }
}
