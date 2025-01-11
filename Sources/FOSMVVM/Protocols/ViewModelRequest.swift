// ViewModelRequest.swift
//
// Created by David Hunt on 9/11/24
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
/// public final class UserViewModelRequest: ViewModelRequest {
///   public let query: Query?
///   public let responseBody: UserViewModel?
///
///   public struct Query: ServerRequestQuery {
///       public let userId: Int
///
///       public init(userId: Int) {
///         self.userId = userId
///       }
///   }
///
///   public init(query: Query? = nil, fragment: Fragment? = nil, requestBody: RequestBody? = nil, responseBody: ResponseBody? = nil) {
///     self.query = query; self.responseBody = responseBody
///   }
/// }
/// ```
public protocol ViewModelRequest: ServerRequest where ResponseBody: RequestableViewModel {}

public extension ViewModelRequest {
    var action: ServerRequestAction {
        .show
    }

    var viewModel: ResponseBody {
        responseBody ?? .stub()
    }
}

#if canImport(Vapor)
import Vapor

public extension RoutesBuilder {
    // NOTE: At this time, an overload that registers a
    //   ViewModelRequest directly is not provided.  The
    //   thinking is that by keeping ViewModel and its
    //   ViewModelRequest tightly bound vai RequestableViewModel,
    //   the entire suite of types corresponding to a ViewModel
    //   is type bound and thus checked at compile time.  This
    //   directs the user to the types that they need to implement.

    /// Enables a ``ViewModel`` instance to be available via
    /// Vapor's [routing](https://docs.vapor.codes/basics/routing/)
    ///
    /// ## Example
    ///
    /// ```swift
    /// func routes(_ app: Application) throws {
    ///    try app.routes.register(model: LandingPageViewModel.self)
    /// }
    /// ```
    ///
    /// > Note: ``ServerRequest`` provides a protocol extension that
    /// >   sets ``ServerRequest/path`` based on the ``ServerRequest/RequestBody``
    /// >   and ``ServerRequest/ResponseBody`` types.   Thus, the route's path is
    /// >   automatically maintained and there is never a path collision or confusion between
    /// >   the client and server.
    ///
    /// - Parameter viewModel: A ``RequestableViewModel`` to register
    func register<Model>(viewModel: Model.Type) throws where Model: RequestableViewModel & VaporViewModelFactory, Model.Request.ResponseBody == Model {
        try register(collection: VaporServerRequestHost<Model.Request>())
    }
}

#endif
