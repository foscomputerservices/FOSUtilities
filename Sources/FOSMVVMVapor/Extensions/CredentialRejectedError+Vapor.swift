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

/// Dresses the rejection for the transport: `401 Unauthorized` with the
/// verifier's authentication challenge (for example `WWW-Authenticate:
/// Bearer`). The response *body* remains the typed error — FOSMVVM clients
/// decode and rethrow it; the status exists for proxies, logs, and RFC 7235
/// conformance, never for client branching.
extension CredentialRejectedError: AbortError {
    public var status: HTTPResponseStatus {
        .unauthorized
    }

    public var headers: HTTPHeaders {
        guard let challenge else { return [:] }
        return ["WWW-Authenticate": challenge]
    }

    public var reason: String {
        // Constant — a rejection reason must never echo the presented credential
        "Credential rejected"
    }
}
