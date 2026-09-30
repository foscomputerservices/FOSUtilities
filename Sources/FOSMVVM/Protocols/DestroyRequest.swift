// DestroyRequest.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

/// A request that destroys one model: the row is removed
///
/// ```swift
/// final class CardDestroyRequest: DestroyRequest {
///     typealias RequestBody = CardDestroyBody   // a WriteTargetProviding
///     typealias ResponseBody = CardListVM       // remaining children (or EmptyBody)
///     // …query, init…
/// }
/// ```
///
/// Destroying removes the row permanently, whether or not the model declares a delete
/// timestamp. Use ``ArchiveRequest`` to keep the row and mark it deleted.
///
/// Its `ResponseError` is a ``ValidatableViewModelRequestError``: a validation failure on the
/// server, from the body's rules or from the model's own, reaches the client as that error
/// with the results inside. ``ValidationError`` is the ready-made choice:
///
/// ```swift
/// public typealias ResponseError = ValidationError
/// ```
public protocol DestroyRequest: ServerRequest, Stubbable where
    ResponseBody: DestroyResponseBody,
    ResponseError: ValidatableViewModelRequestError {}

public extension DestroyRequest {
    static var baseTypeName: String {
        "DestroyRequest"
    }

    var action: ServerRequestAction {
        .destroy
    }
}

public protocol DestroyResponseBody: ServerRequestBody {}

extension EmptyBody: DestroyResponseBody {}
