// CredentialRejectedError+Vapor.swift
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

import FOSMVVM
import Vapor

/// The transport dressing for a credential rejection: 401 Unauthorized with the
/// challenge rendered as WWW-Authenticate. Applied by ErrorMiddleware, which is
/// the one place a ServerRequestError becomes a Response — the rejection itself
/// is plain data and carries no Vapor conformance. The body remains the typed
/// error inside the WireError envelope; the status exists for proxies, logs,
/// and RFC 7235 conformance, never for client branching.
extension CredentialRejectedError {
    static let transportStatus: HTTPResponseStatus = .unauthorized

    var transportHeaders: HTTPHeaders {
        guard let challenge else { return [:] }
        return ["WWW-Authenticate": Self.headerValue(for: challenge, reason: reason)]
    }

    /// RFC 7235 challenge text, rendered in exactly one place. The error token
    /// follows the reason (RFC 6750 §3.1: no error token when no credential
    /// was presented), so a challenge cannot contradict its rejection.
    static func headerValue(for challenge: CredentialChallenge, reason: Reason) -> String {
        switch challenge {
        case .bearer:
            reason == .invalid ? #"Bearer error="invalid_token""# : "Bearer"
        case .bearerRealm(let realm):
            reason == .invalid ? #"Bearer realm="\(realm)", error="invalid_token""# : #"Bearer realm="\(realm)""#
        case .basicRealm(let realm):
            #"Basic realm="\(realm)""#
        }
    }
}
