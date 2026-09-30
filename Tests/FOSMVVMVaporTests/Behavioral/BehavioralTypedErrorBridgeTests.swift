// BehavioralTypedErrorBridgeTests.swift
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
import FOSMVVMVapor
import FOSTesting
import Foundation
import Testing

/// OQ21b / 3c-1 and DocC 4.14: a write request's `ResponseError` is a
/// `ValidatableViewModelRequestError`, so the validations the server collected arrive at the
/// client inside the request's OWN error type — the one it decodes.
@Suite("Behavioral: the typed error bridge on a write request")
struct BehavioralTypedErrorBridgeTests: LocalizableTestCase {
    /// The bridge, exercised exactly as the route uses it: build the request's declared error
    /// type from the results, without naming a concrete type.
    private func bridge<E: ValidatableViewModelRequestError>(_: E.Type, results: [ValidationResult]) -> E {
        .init(validations: results)
    }

    @Test("An archive request's declared error type carries the results it was built from")
    func requestErrorCarriesItsResults() throws {
        let error = bridge(BehavioralRelicArchiveRequest.ResponseError.self, results: [
            .init(status: .error, message: BehavioralMessages.full)
        ])

        #expect(error.validations.count == 1)
        let message = try #require(error.validations.first?.messages.first)
        #expect(message.addressesModel)
    }

    @Test("The bridged error localizes its messages when it is encoded")
    func bridgedErrorLocalizes() throws {
        let error = bridge(BehavioralRelicArchiveRequest.ResponseError.self, results: [
            .init(status: .error, message: BehavioralMessages.full)
        ])

        let decoded: ValidationError = try error.toJSON(encoder: encoder(locale: Self.en)).fromJSON()

        let message = try #require(decoded.validations.first?.messages.first)
        #expect(try message.message.localizedString == "The box is full")
    }

    /// negative space: 3c-1 names the failure this constraint prevents — a write whose error type
    /// carries no validations gives the user a decode failure instead of messages. An empty set is
    /// a legal value; the type still round-trips, so the client never fails to decode.
    @Test("An empty result set still round-trips through the request's error type")
    func emptyResultsRoundTrip() throws {
        let error = bridge(BehavioralRelicArchiveRequest.ResponseError.self, results: [])

        let decoded: ValidationError = try error.toJSON(encoder: encoder(locale: Self.en)).fromJSON()

        #expect(decoded.validations.isEmpty)
    }

    let locStore: LocalizationStore
    init() throws {
        self.locStore = try Self.loadLocalizationStore(bundle: .module, resourceDirectoryName: "TestYAML")
    }
}
