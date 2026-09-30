// CreateRequest.swift
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

/// A ``ServerRequest`` that requests that the server **create** a resource.
///
/// A create returns a ``ServerRequest/ResponseBody`` like any request — normally the
/// container's updated children, the same type a read of that container returns. Give
/// the request that `ResponseBody`; the framework loads the writer's candidate scope,
/// creates into it, commits, then builds the response from the refreshed records.
///
/// ```swift
/// final class CardCreateRequest: CreateRequest {
///     typealias RequestBody = CardCreateBody   // a DataModelWriter
///     typealias ResponseBody = CardListVM      // the container's children
///     // …query, init…
/// }
/// ```
///
/// Its `ResponseError` is a ``ValidatableViewModelRequestError``: a validation failure on the
/// server, from the body's rules or from the model's own, reaches the client as that error
/// with the results inside. ``ValidationError`` is the ready-made choice:
///
/// ```swift
/// public typealias ResponseError = ValidationError
/// ```
public protocol CreateRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel,
    ResponseBody: CreateResponseBody,
    ResponseError: ValidatableViewModelRequestError {}

public extension CreateRequest {
    static var baseTypeName: String {
        "CreateRequest"
    }

    var action: ServerRequestAction {
        .create
    }
}

public protocol CreateResponseBody: ServerRequestBody {}

extension EmptyBody: CreateResponseBody {}
