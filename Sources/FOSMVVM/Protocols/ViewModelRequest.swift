// ViewModelRequest.swift
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

/// Request a ``ViewModel`` from the server
///
/// A ``ServerRequest`` that requests a ``ViewModel`` instance from the web service.
///
/// By default the ``ServerRequest/action`` is set to ``ServerRequestAction/show``,
/// which with perform a **GET** HTTP request.
///
/// By default the ``ServerRequest/RequestBody`` and ``ServerRequest/Fragment``
/// are set to ``EmptyBody`` and ``EmptyFragment``, respectively.
///
/// The implementation of ``ViewModelRequest`` can provide a ``ServerRequest/Query``
/// implementation to allow the request's user to request specific resources.
///
/// ## Example
///
/// ```swift
///  public struct UserViewModel: ViewModel {
///      public let userId: Int
///      public let firstName: String
///      public let lastName: String
///      public let email: String
///  }
///
/// public final class UserViewModelRequest: ViewModelRequest, @unchecked Sendable {
///   public typealias Fragment = EmptyFragment
///   public let query: Query?
///   public var responseBody: UserViewModel?
///
///   public struct Query: ServerRequestQuery {
///       public let userId: Int
///
///       public init(userId: Int) {
///         self.userId = userId
///       }
///   }
///
///   public struct ResponseError: ServerRequestQuery {
///       public let userId: Int
///
///       public init(userId: Int) {
///         self.userId = userId
///       }
///   }
///
///   public init(
///       query: Query? = nil,
///       fragment: Fragment? = nil,
///       requestBody: RequestBody? = nil,
///       responseBody: ResponseBody? = nil
///   ) {
///       self.query = query; self.responseBody = responseBody
///   }
/// }
/// ```
public protocol ViewModelRequest: ServerRequest where ResponseBody: RequestableViewModel {}

public extension ViewModelRequest {
    var action: ServerRequestAction {
        .show
    }

    var fragment: EmptyFragment? { nil }

    var requestBody: EmptyBody? { nil }

    var viewModel: ResponseBody {
        responseBody ?? .stub()
    }
}
