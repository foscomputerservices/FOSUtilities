// CredentialSeamFixtures.swift
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

// Shared credential-seam fixtures used by both the round-trip and in-process suites.

import FOSFoundation
import FOSMVVM
import Foundation

/// The response body a protected route grants — the client-contract test never
/// receives one (the middleware rejects first).
struct GrantedReply: ServerRequestBody {
    let message: String
}

/// A typed error with a required field — it does NOT decode from a rejection body,
/// so under stock (non-FOS) middleware the raw 401 surfaces
/// (`plain401WithoutEnvelopeFallsBack`), and under FOS `ErrorMiddleware` the
/// typed rejection wins.
struct StrictContractError: ServerRequestError {
    let errorCode: Int
}

/// `.show` fixture behind the protected group — drives the REAL client
/// (`processRequest(mvvmEnv:)`) against the middleware. Its `EmptyError`
/// `ResponseError` decodes from any valid-JSON body; the WireError chain now
/// claims rejections first, so this fixture PROVES the swallow is retired
/// (`emptyErrorNoLongerSwallowsRejections`).
final class ShowGrantedReplyRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = EmptyError

    var action: ServerRequestAction {
        .show
    }

    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}

/// Same .show shape; the CONTROLLER throws StrictContractError after
/// admission — drives the handler-routing positive half.
final class ShowOperationFailureRequest: ServerRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseBody = GrantedReply
    typealias ResponseError = StrictContractError

    var action: ServerRequestAction {
        .show
    }

    var responseBody: GrantedReply?

    init(query: EmptyQuery? = nil, sort: EmptySort? = nil, fragment: EmptyFragment? = nil,
         requestBody: EmptyBody? = nil, responseBody: GrantedReply? = nil) {
        self.responseBody = responseBody
    }
}

/// A mutable token source — models an app session whose credential rotates between requests.
/// (Mirrors the helper in `ClientCredentialProviderTests` — separate test targets, same shape.)
actor TokenVault {
    var token: String?

    init(token: String?) {
        self.token = token
    }

    func rotate(to newToken: String?) {
        token = newToken
    }
}

/// Counts the requests the server actually served.
actor RequestTally {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

/// The server's current good credential — rotates to model a server restart.
actor ServerCredential {
    private var current: String

    init(current: String) {
        self.current = current
    }

    func isCurrent(_ token: String) -> Bool {
        token == current
    }
}

/// A client provider that refreshes on rejection and **persists** the refreshed value,
/// so a later `credentialHeaders()` yields it too (spec §4.1).
struct RefreshingCredentialProvider: ClientCredentialProvider {
    let vault: TokenVault
    let refreshedTo: String?
    let refreshTally: RequestTally

    func credentialHeaders() async throws -> [(field: String, value: String)] {
        guard let token = await vault.token else { return [] }
        return [(field: "Authorization", value: "Bearer \(token)")]
    }

    func credentialHeaders(afterRejection: CredentialRejectedError) async -> [(field: String, value: String)]? {
        await refreshTally.increment()
        guard let refreshedTo else { return nil }
        await vault.rotate(to: refreshedTo)

        return [(field: "Authorization", value: "Bearer \(refreshedTo)")]
    }
}
