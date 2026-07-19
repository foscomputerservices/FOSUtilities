// ClientCredentialProviderTests.swift
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
import Testing

@Suite("ClientCredentialProvider")
struct ClientCredentialProviderTests {
    @Test("BearerCredentialProvider yields exactly one Authorization: Bearer header")
    func bearerHeader() async throws {
        let provider = BearerCredentialProvider { "abc" }

        let headers = try await provider.credentialHeaders()

        #expect(headers.count == 1)
        #expect(headers.first?.field == "Authorization")
        #expect(headers.first?.value == "Bearer abc")
    }

    @Test("A nil token yields no headers — the request proceeds unauthenticated")
    func nilToken() async throws {
        let provider = BearerCredentialProvider { nil }

        let headers = try await provider.credentialHeaders()

        #expect(headers.isEmpty)
    }

    @Test("A rotated token is reflected on the next credentialHeaders() call")
    func rotation() async throws {
        let vault = TokenVault(token: "first")
        let provider = BearerCredentialProvider { await vault.token }

        let first = try await provider.credentialHeaders()
        #expect(first.first?.value == "Bearer first")

        await vault.rotate(to: "second")

        let second = try await provider.credentialHeaders()
        #expect(second.first?.value == "Bearer second")
    }

    @Test("A provider that does not override the refresh seam declines to refresh")
    func refreshSeamDefaultsToDeclining() async {
        let provider = BearerCredentialProvider { "abc" }

        let refreshed = await provider.credentialHeaders(
            afterRejection: CredentialRejectedError(code: .invalid)
        )

        #expect(refreshed == nil)
    }

    @Test("An overriding provider supplies replacement headers")
    func refreshSeamOverrideSuppliesHeaders() async {
        let provider = RefreshingProvider(refreshedTo: "fresh")

        let refreshed = await provider.credentialHeaders(
            afterRejection: CredentialRejectedError(code: .invalid)
        )

        #expect(refreshed?.count == 1)
        #expect(refreshed?.first?.field == "Authorization")
        #expect(refreshed?.first?.value == "Bearer fresh")
    }
}

/// A mutable token source — models an app session whose credential rotates between requests.
private actor TokenVault {
    var token: String?

    init(token: String?) {
        self.token = token
    }

    func rotate(to newToken: String?) {
        token = newToken
    }
}

/// A provider that returns fresh replacement headers when asked after a rejection.
private struct RefreshingProvider: ClientCredentialProvider {
    let vault = TokenVault(token: nil)
    let refreshedTo: String

    func credentialHeaders() async throws -> [(field: String, value: String)] {
        guard let token = await vault.token else { return [] }
        return [(field: "Authorization", value: "Bearer \(token)")]
    }

    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        await vault.rotate(to: refreshedTo)
        return [(field: "Authorization", value: "Bearer \(refreshedTo)")]
    }
}
