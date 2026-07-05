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
/// After the delete commits, the server re-serves a read request so the caller
/// receives the freshly-rendered screen the deletion left behind. Name that
/// read request as ``RefreshRequest`` and build it from your write query in
/// ``refreshRequest()``:
///
/// ```swift
/// typealias RefreshRequest = DockPageRequest
///
/// func refreshRequest() -> DockPageRequest {
///     DockPageRequest(query: query.map { .init(dock: $0.dock) })
/// }
/// ```
public protocol DeleteRequest: ServerRequest, Stubbable
    where ResponseBody == RefreshRequest.ResponseBody {
    /// The read request re-served after this delete commits. Its `ResponseBody`
    /// is this request's — by constraint — so the caller always receives the
    /// fresh screen.
    associatedtype RefreshRequest: ServerRequest

    /// Builds the read request the server re-serves after this delete commits.
    ///
    /// Author it as a pure value mapping from the write query's root:
    ///
    /// ```swift
    /// func refreshRequest() -> DockPageRequest {
    ///     DockPageRequest(query: query.map { .init(dock: $0.dock) })
    /// }
    /// ```
    func refreshRequest() -> RefreshRequest
}

public extension DeleteRequest {
    static var baseTypeName: String {
        "DeleteRequest"
    }

    var action: ServerRequestAction {
        .delete
    }
}
