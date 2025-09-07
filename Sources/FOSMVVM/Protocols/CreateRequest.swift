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

/// A ``ServerRequest`` that requests that the server **create** a resource
public protocol CreateRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel, ResponseBody: CreateResponseBody {}

public extension CreateRequest {
    static var baseTypeName: String { "CreateRequest" }

    var action: ServerRequestAction { .create }
}

public protocol CreateResponseBody: ServerRequestBody {}

extension EmptyBody: CreateResponseBody {}
