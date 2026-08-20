// LocalizableErrorTests.swift
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
import FOSTesting
import Foundation
import Testing

/// A `LocalizableError` localizes exactly as a ViewModel does — during the localizing
/// encode. These tests round-trip the whole error to model the wire flow: the server
/// throws, `ErrorMiddleware` encodes with the localizing encoder (resolving the
/// `@Localized…` message), and the client decodes an already-localized value it displays
/// with no localization store of its own.
struct LocalizableErrorTests: LocalizableTestCase {
    @Test func wireRoundTrip_deliversTheLocalizedMessage() throws {
        let thrown = TestQuotaError(requested: 5, maximum: 3)

        // Server leg: ErrorMiddleware encodes the error with the localizing encoder
        // Client leg: decode the typed error — no store anywhere after this point
        let received: TestQuotaError = try thrown
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(received.localizedMessage.localizationStatus == .localized)
        #expect(try received.localizedMessage.localizedString == "Requested 5 exceeds the maximum of 3")
    }

    @Test func wireRoundTrip_localizesInTheRequestLocale() throws {
        let thrown = TestQuotaError(requested: 5, maximum: 3)

        let received: TestQuotaError = try thrown
            .toJSON(encoder: encoder(locale: Self.es))
            .fromJSON()

        #expect(try received.localizedMessage.localizedString == "Lo solicitado 5 supera el máximo de 3")
    }

    @Test func wireRoundTrip_plainMessageLocalizes() throws {
        let received: TestSaveError = try TestSaveError()
            .toJSON(encoder: encoder())
            .fromJSON()

        #expect(try received.localizedMessage.localizedString == "The document could not be saved")
    }

    @Test func conformance_isReachableThroughAnyError() throws {
        let received: TestQuotaError = try TestQuotaError(requested: 5, maximum: 3)
            .toJSON(encoder: encoder())
            .fromJSON()
        let error: any Error = received

        let localizable = try #require(error as? any LocalizableError)
        #expect(localizable.localizedMessage.localizationStatus == .localized)
    }

    // MARK: Client-hosted domain — localized(locale:localizationStore:)

    @Test func clientHosted_localizes_viaTheSameRoundTripAsAViewModel() throws {
        let localized = try TestOfflineError().localized(
            locale: Self.en,
            localizationStore: locStore
        )

        #expect(try localized.localizedMessage.localizedString == "This action requires a network connection")
    }

    @Test func clientHosted_localizes_perLocale() throws {
        let localized = try TestOfflineError().localized(
            locale: Self.es,
            localizationStore: locStore
        )

        #expect(try localized.localizedMessage.localizedString == "Esta acción requiere conexión de red")
    }

    @Test func clientHostedMarker_isEmittedByTheOptionsFlag() {
        #expect(TestOfflineError() is any ClientHostedLocalizableError)
        #expect(!(TestQuotaError(requested: 1, maximum: 1) is any ClientHostedLocalizableError))
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

/// The canonical conformer: composed like a ViewModel — `@Localized…` message, values
/// carried via `@LocalizedSubs`, plumbing from the `@LocalizableError` macro.
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

@LocalizableError
private struct TestSaveError: ServerRequestError {
    @LocalizedString var errorMessage

    var localizedMessage: any Localizable {
        errorMessage
    }

    init() {}
}
