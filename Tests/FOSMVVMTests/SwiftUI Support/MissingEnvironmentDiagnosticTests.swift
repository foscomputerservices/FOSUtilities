// MissingEnvironmentDiagnosticTests.swift
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
// so long as the facts below survive. What is NOT reachable here is the delivery: that a view whose
// required environment object is missing actually reaches `reportAndStop`. `reportAndStop` traps,
// and a trap cannot be caught by a test; the call sites need SwiftUI to drive a render. That path
// needs a host app target FOSUtilities does not ship, so it belongs to a consumer app. The message
// CONTENT is pinned here, and portably: these run on the Linux leg, the only one CI executes.

@Suite("Missing-environment diagnostics")
struct MissingEnvironmentDiagnosticTests {
    @Test("require passes an installed value through unchanged")
    func requirePassesValueThrough() {
        let value = MissingEnvironmentDiagnostic.require(42, orStop: "unused")

        #expect(value == 42)
    }

    @Test("Missing MVVMEnvironment names the API that needed it")
    func missingMVVMEnvironmentNamesTheReader() {
        let message = MissingEnvironmentDiagnostic.missingMVVMEnvironment(
            reader: "Localizable.text"
        )

        #expect(message.contains("Localizable.text"))
    }

    @Test("Missing MVVMEnvironment teaches the .environment(MVVMEnvironment(...)) fix")
    func missingMVVMEnvironmentTeachesTheFix() {
        let message = MissingEnvironmentDiagnostic.missingMVVMEnvironment(
            reader: "ViewModelView.bind()"
        )

        #expect(message.contains(".environment("))
        #expect(message.contains("MVVMEnvironment("))
        #expect(message.contains("deploymentURLs:"))
    }

    @Test("Missing Validations names the field that wanted to display messages")
    func missingValidationsNamesTheField() {
        let message = MissingEnvironmentDiagnostic.missingValidations(fieldId: "email")

        #expect(message.contains("email"))
    }

    @Test("Missing Validations teaches installing the shared instance around the form")
    func missingValidationsTeachesTheFix() {
        let message = MissingEnvironmentDiagnostic.missingValidations(fieldId: "email")

        #expect(message.contains("Validations()"))
        #expect(message.contains(".environment(validations)"))
    }

    @Test("Missing store without an error reports an unconfigured store, not a failure")
    func missingStoreWithoutErrorReportsUnconfigured() {
        let message = MissingEnvironmentDiagnostic.missingLocalizationStore(
            reader: "Localizable.text",
            resolutionError: nil
        )

        #expect(message.contains("Localizable.text"))
        #expect(message.contains("has no client localization store"))
        #expect(!message.contains("failed"))
    }

    @Test("Missing store surfaces the resolution error verbatim")
    func missingStoreSurfacesTheResolutionError() {
        let message = MissingEnvironmentDiagnostic.missingLocalizationStore(
            reader: "Localizable.text",
            resolutionError: "noResourcePaths(bundlePath: \"/App.app\")"
        )

        #expect(message.contains("noResourcePaths(bundlePath: \"/App.app\")"))
    }

    @Test("Missing store teaches both configuration doors: resourceBundles and localizationStore")
    func missingStoreTeachesBothDoors() {
        let message = MissingEnvironmentDiagnostic.missingLocalizationStore(
            reader: "Localizable.text",
            resolutionError: nil
        )

        #expect(message.contains("resourceBundles:"))
        #expect(message.contains("localizationStore:"))
    }
}
