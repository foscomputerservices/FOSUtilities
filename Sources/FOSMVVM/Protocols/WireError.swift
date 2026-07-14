// WireError.swift
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

// swiftformat:disable docComments
// The client-side decode order for a ServerRequest error body: the well-known
// surface errors (closed, FOS-owned list — CredentialRejectedError today) are
// tried STRICTLY before the request's own ResponseError. Passed to DataFetch
// as the ONE existing `errorType:` — FOSFoundation stays untouched; add a
// future surface error HERE, nowhere else.
// `package`: the decode chain is defined once here and consumed by both the
// client fetch path (FOSMVVM) and the test harness (FOSTestingVapor) — spec §3.4.
package enum WireError<E: ServerRequestError>: Error, Decodable {
    case surface(CredentialRejectedError)
    case response(E)

    // swiftformat:enable docComments
    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rejection = try? container.decode(CredentialRejectedError.self) {
            self = .surface(rejection)
        } else {
            self = try .response(container.decode(E.self))
        }
    }
}
