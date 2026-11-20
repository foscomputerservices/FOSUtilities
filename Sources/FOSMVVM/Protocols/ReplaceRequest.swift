// ReplaceRequest.swift
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

/// A ``ServerRequest`` that asks the server to **replace** a resource with the state its body carries.
///
/// ```swift
/// final class CardReplaceRequest: ReplaceRequest {
///     typealias RequestBody = CardReplaceBody   // a DataModelWriter
///     typealias ResponseBody = CardListVM       // the container's children
///     typealias ResponseError = ValidationError
///     // …query, init…
/// }
/// ```
///
/// Reach for a replace when the client sends the resource's whole desired state (HTTP PUT).
/// Reach for ``UpdateRequest`` when it sends a change to part of it (HTTP PATCH).
///
/// The server serves both the same way: it loads the writer's candidate scope, resolves the
/// target, applies the body, saves, then builds the response from the refreshed records.
/// The target must already exist. A replace never creates one.
///
/// > Important: The body's `apply(to:)` decides what is written. A field it does not assign
/// > keeps its stored value.
public protocol ReplaceRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel,
    ResponseBody: ReplaceResponseBody,
    ResponseError: ValidatableViewModelRequestError {}

public extension ReplaceRequest {
    static var baseTypeName: String {
        "ReplaceRequest"
    }

    var action: ServerRequestAction {
        .replace
    }
}

public protocol ReplaceResponseBody: ServerRequestBody {}

extension EmptyBody: ReplaceResponseBody {}
