// ShowRequest.swift
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

// TODO: Add Stubbable conformance
// (dgh: 27-Dec-25) - If I add this now, it will be a breaking change for ViewModelRequest.
// I'm not sure that we're ready for that yet, so just preparing for the future.

/// A ``ServerRequest`` that requests that the server **show** (retrieve) a resource.
///
/// Unlike ``ViewModelRequest`` which returns a ``ViewModel``, ``ShowRequest``
/// returns a plain data response conforming to ``ShowResponseBody``.
///
/// Use this for lightweight data retrieval that doesn't require full ViewModel machinery.
public protocol ShowRequest: ServerRequest /* , Stubbable where ResponseBody: ShowResponseBody */ {}

public extension ShowRequest {
    static var baseTypeName: String { "ShowRequest" }

    var action: ServerRequestAction { .show }

    var fragment: EmptyFragment? { nil }

    var requestBody: EmptyBody? { nil }
}

/// Response body marker protocol for ``ShowRequest``.
public protocol ShowResponseBody: ServerRequestBody {}
