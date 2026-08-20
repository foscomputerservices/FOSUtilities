// ErrorAlertTests.swift
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
import FOSFoundation
@testable import FOSMVVM
import FOSTesting
import Foundation
import SwiftUI
import Testing

/// The alert is Localizable *composition* — the generated twins render; the only logic is
/// the `%{error}` substitution-value ladder, tested here rung by rung across both
/// localization domains, plus the composed message as a value.
struct ErrorAlertTests: LocalizableTestCase {
    // MARK: Substitution-value ladder

    @Test func wireError_contributesItsDecodedMessage() throws {
        let received: TestQuotaError = try TestQuotaError(requested: 5, maximum: 3)
            .toJSON(encoder: encoder())
            .fromJSON()

        let value = ErrorAlertMessage.substitutionValue(
            for: received,
            mvvmEnv: clientHostedEnv,
            locale: Self.en
        )

        #expect(try value.localizedString == "Requested 5 exceeds the maximum of 3")
    }

    @Test func clientHostedError_resolvesAgainstTheClientStore() throws {
        let value = ErrorAlertMessage.substitutionValue(
            for: TestOfflineError(),
            mvvmEnv: clientHostedEnv,
            locale: Self.en
        )

        #expect(try value.localizedString == "This action requires a network connection")
    }

    @Test func clientHostedError_resolvesInTheEnvironmentLocale() throws {
        let value = ErrorAlertMessage.substitutionValue(
            for: TestOfflineError(),
            mvvmEnv: clientHostedEnv,
            locale: Self.es
        )

        #expect(try value.localizedString == "Esta acción requiere conexión de red")
    }

    @Test func clientHostedError_withoutResolvableStore_fallsBackToDebugDescription() {
        let error = TestOfflineError()

        let value = ErrorAlertMessage.substitutionValue(
            for: error,
            mvvmEnv: storelessEnv,
            locale: Self.en
        )

        #expect((try? value.localizedString) == "\(error)")
    }

    @Test func clientHostedError_withoutEnvironment_fallsBackToDebugDescription() {
        let error = TestOfflineError()

        let value = ErrorAlertMessage.substitutionValue(
            for: error,
            mvvmEnv: nil,
            locale: Self.en
        )

        #expect((try? value.localizedString) == "\(error)")
    }

    @Test func nonConformingError_contributesItsDebugDescription() {
        let value = ErrorAlertMessage.substitutionValue(
            for: PlainError.boom,
            mvvmEnv: clientHostedEnv,
            locale: Self.en
        )

        #expect((try? value.localizedString) == "\(PlainError.boom)")
    }

    // MARK: The composed message value

    @Test func message_fillsItsErrorSlot() throws {
        let received: TestQuotaError = try TestQuotaError(requested: 5, maximum: 3)
            .toJSON(encoder: encoder())
            .fromJSON()

        let composed = LocalizableString.constant("Failed: %{error}").bind(substitutions: [
            "error": ErrorAlertMessage.substitutionValue(
                for: received,
                mvvmEnv: nil,
                locale: Self.en
            )
        ])

        #expect(try composed.localizedString == "Failed: Requested 5 exceeds the maximum of 3")
    }

    @Test func slotFreeMessage_passesThroughUnchanged() throws {
        let composed = LocalizableString.constant("A static message").bind(substitutions: [
            "error": ErrorAlertMessage.substitutionValue(
                for: PlainError.boom,
                mvvmEnv: nil,
                locale: Self.en
            )
        ])

        #expect(try composed.localizedString == "A static message")
    }

    // MARK: Public modifier surface

    @MainActor @Test func modifier_appliesToAView() {
        let error = Binding<Error?>.constant(nil)

        _ = Text("content").alert(
            error: error,
            title: LocalizableString.constant("An Error Occurred"),
            message: .constant("%{error}"),
            dismissButtonLabel: LocalizableString.constant("OK")
        )
        _ = Text("content").alert(
            error: error,
            title: LocalizableString.constant("An Error Occurred"),
            dismissButtonLabel: LocalizableString.constant("OK")
        )
    }

    let locStore: LocalizationStore
    let clientHostedEnv: MVVMEnvironment
    let storelessEnv: MVVMEnvironment

    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
        let url = try #require(URL(string: "http://localhost:8080"))
        self.clientHostedEnv = MVVMEnvironment(
            appBundle: Bundle.module,
            resourceBundles: [Bundle.module],
            resourceDirectoryName: "TestYAML",
            deploymentURLs: [.debug: url]
        )
        self.storelessEnv = MVVMEnvironment(
            appBundle: Bundle.module,
            resourceBundles: [],
            deploymentURLs: [.debug: url]
        )
    }
}

/// Wire-domain conformer — shares the `TestQuotaError` fixture keys with
/// `LocalizableErrorTests`.
@LocalizableError
private struct TestQuotaError: ServerRequestError {
    let requested: Int
    let maximum: Int

    @LocalizedSubs(substitutions: \.subs) var errorMessage

    var localizedMessage: any Localizable {
        errorMessage
    }

    private var subs: [String: any Localizable] {
        [
            "requested": LocalizableInt(value: requested),
            "maximum": LocalizableInt(value: maximum)
        ]
    }
}

/// Client-domain conformer — created in the app, localized at presentation against the
/// client-hosted store.
@LocalizableError(options: [.clientHosted])
private struct TestOfflineError {
    @LocalizedString var errorMessage

    var localizedMessage: any Localizable {
        errorMessage
    }

    init() {}
}

private enum PlainError: Error {
    case boom
}
#endif
