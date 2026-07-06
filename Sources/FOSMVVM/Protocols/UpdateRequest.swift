// UpdateRequest.swift
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

/// A ``ServerRequest`` that requests that the server **update** a resource.
///
/// An update returns a ``ServerRequest/ResponseBody`` like any request — normally the
/// container's updated children, the same type a read of that container returns. Give
/// the request that `ResponseBody`; the framework loads the writer's candidate scope,
/// resolves and mutates the target, commits, then builds the response from the
/// refreshed records.
///
/// ```swift
/// final class UpdateBerthRequest: UpdateRequest {
///     typealias RequestBody = UpdateBerthBody   // a DataModelWriter
///     typealias ResponseBody = BerthListVM      // the container's children
///     // …query, init…
/// }
/// ```
public protocol UpdateRequest: ServerRequest, Stubbable
    where RequestBody: ValidatableModel,
    ResponseBody: UpdateResponseBody {}

public extension UpdateRequest {
    static var baseTypeName: String {
        "UpdateRequest"
    }

    var action: ServerRequestAction {
        .update
    }
}

public protocol UpdateResponseBody: ServerRequestBody {}

extension EmptyBody: UpdateResponseBody, ValidatableModel {
    public func validate(
        fields: [any FormFieldBase]?,
        validations: Validations
    ) -> ValidationResult.Status? {
        nil
    }
}
