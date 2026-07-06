// DeleteRequest.swift
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

/// A ``ServerRequest`` that requests that the server **delete** a resource
///
/// > **delete** indicates "soft delete" as opposed to *destroy* that permanently
/// > removes the item
///
/// A delete returns a ``ServerRequest/ResponseBody`` like any request — normally the
/// container's remaining children, the same type a read of that container returns (or
/// ``EmptyBody`` when there is nothing to return). The delete body declares its
/// candidate set only (``WriteTargetProviding``); deletion is framework-owned.
///
/// ```swift
/// final class DeleteBerthRequest: DeleteRequest {
///     typealias RequestBody = DeleteBerthBody   // a WriteTargetProviding
///     typealias ResponseBody = BerthListVM      // remaining children (or EmptyBody)
///     // …query, init…
/// }
/// ```
public protocol DeleteRequest: ServerRequest, Stubbable where
    ResponseBody: DeleteResponseBody {}

public extension DeleteRequest {
    static var baseTypeName: String {
        "DeleteRequest"
    }

    var action: ServerRequestAction {
        .delete
    }
}

public protocol DeleteResponseBody: ServerRequestBody {}

extension EmptyBody: DeleteResponseBody {}
