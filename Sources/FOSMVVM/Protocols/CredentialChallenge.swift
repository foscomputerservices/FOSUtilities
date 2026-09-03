// CredentialChallenge.swift
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

import Foundation

/// What a server demands of a credential — one case per authentication scheme
///
/// A ``ServerCredentialVerifier`` attaches it to the ``CredentialRejectedError``
/// it throws; the transport renders it as the response's `WWW-Authenticate`
/// header, and the client receives the same typed value on the decoded error:
///
/// ```swift
/// throw CredentialRejectedError(reason: .missing, challenge: .bearer)
/// throw CredentialRejectedError(reason: .invalid, challenge: .bearerRealm("api"))
/// ```
///
/// The header's error token is not part of the challenge — it follows from the
/// rejection's ``CredentialRejectedError/Reason``, so a challenge can never
/// contradict the reason it accompanies.
///
/// > Note: A scheme this enum lacks is a case to add, with its parameters
/// > typed. There is no free-form case.
public enum CredentialChallenge: Codable, Sendable, Equatable {
    /// `Bearer` (RFC 6750), one protection space
    case bearer

    /// `Bearer` (RFC 6750), a named protection space
    case bearerRealm(String)

    /// `Basic` (RFC 7617); the scheme requires a named protection space
    case basicRealm(String)
}
