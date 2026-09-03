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

// The wire form of every ServerRequest error body: exactly one of the
// well-known surface errors (closed, FOS-owned list — CredentialRejectedError
// today) or the request's own ResponseError. The server's ErrorMiddleware
// encodes it; the client fetch path and the FOSTestingVapor harness decode it.
// Synthesized Codable keys the body by case, so the discrimination lives here
// and never inside a payload. Add a future surface error HERE, nowhere else.
// `package`: one definition, consumed by FOSMVVM, FOSMVVMVapor, and
// FOSTestingVapor.
package enum WireError<E: ServerRequestError>: Error, Codable {
    case surface(CredentialRejectedError)
    case response(E)
}
