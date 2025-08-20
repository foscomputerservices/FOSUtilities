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

/// A ``ServerRequest`` that requests that the server **destroy** a resource
///
/// > **destroy** indicates **permanent destruction** of the resource as
/// > opposed to *delete* that performs a "soft deletion" of the resource
public protocol DestroyRequest: ServerRequest, Stubbable {}

public extension DestroyRequest {
    static var baseTypeName: String { "DestroyRequest" }

    var action: ServerRequestAction { .destroy }
}
