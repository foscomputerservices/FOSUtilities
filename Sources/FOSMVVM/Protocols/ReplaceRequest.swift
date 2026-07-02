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

/// A ``ServerRequest`` that requests that the server **replace** a resource
///
/// `ReplaceRequest` is the PUT verb of the write-protocol family: unlike
/// ``UpdateRequest`` (PATCH, a partial modification of an existing resource),
/// a replace supplies the resource's full desired state. It mirrors
/// ``UpdateRequest``'s contract — its ``ServerRequest/RequestBody`` is a
/// ``ValidatableModel`` so the same ``Fields`` validation applies at every layer.
public protocol ReplaceRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel, ResponseBody: ReplaceResponseBody {}

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
