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
