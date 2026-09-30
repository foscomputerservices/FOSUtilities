// ArchiveRequest.swift
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

/// A request that archives one model: the row stays, marked deleted
///
/// ```swift
/// final class CardArchiveRequest: ArchiveRequest {
///     typealias RequestBody = CardArchiveBody   // a WriteTargetProviding
///     typealias ResponseBody = CardListVM       // remaining children (or EmptyBody)
///     // …query, init…
/// }
/// ```
///
/// An archive returns a ``ServerRequest/ResponseBody`` like any request — normally the
/// container's remaining children, the same type a read of that container returns (or
/// ``EmptyBody`` when there is nothing to return). The archive body declares its
/// candidate set only (``WriteTargetProviding``); archiving is framework-owned.
///
/// The target model must declare a delete timestamp; use ``DestroyRequest`` to remove a row.
///
/// Its `ResponseError` is a ``ValidatableViewModelRequestError``: a validation failure on the
/// server, from the body's rules or from the model's own, reaches the client as that error
/// with the results inside. ``ValidationError`` is the ready-made choice:
///
/// ```swift
/// public typealias ResponseError = ValidationError
/// ```
public protocol ArchiveRequest: ServerRequest, Stubbable where
    ResponseBody: ArchiveResponseBody,
    ResponseError: ValidatableViewModelRequestError {}

public extension ArchiveRequest {
    static var baseTypeName: String {
        "ArchiveRequest"
    }

    var action: ServerRequestAction {
        .archive
    }
}

public protocol ArchiveResponseBody: ServerRequestBody {}

extension EmptyBody: ArchiveResponseBody {}
