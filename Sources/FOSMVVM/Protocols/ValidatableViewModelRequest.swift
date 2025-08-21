// ValidatableViewModelRequest.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

/// Send data to, and request a ``ViewModel`` from, the server
///
/// A ``ServerRequest`` that sends data to the web services and requests a ``ViewModel`` instance in return.
///
/// By default the ``ServerRequest/action`` is set to ``ServerRequestAction/create``,
/// which with perform a **POST** HTTP request.
///
/// By default the ``ServerRequest/RequestBody`` and ``ServerRequest/Fragment``
/// are set to ``EmptyBody`` and ``EmptyFragment``, respectively.
///
/// The implementation of ``ValidatableViewModelRequest`` can provide a ``ServerRequest/Query``
/// implementation to allow the request's user to update specific resources when using
/// ``ServerRequestAction/update`` or ``ServerRequestAction/replace``.
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
/// public final class UserViewModelRequest: ValidatableViewModelRequest, @unchecked Sendable {
///   public typealias Fragment = EmptyFragment
///   public typealias Query = EmptyQuery
///   public let action = ServerRequestAction.create // **create is the default**
///   public let requestBody: NewUserModel?
///   public var responseBody: UserViewModel?
///
///   public struct NewUserModel: ServerRequestBody, ValidatableViewModel {
///       public let firstName: String
///       public let lastName: String
///       public let email: String
///   }
///
///   public struct ResponseError: ValidatableViewModelRequestError {
///       public let message: LocalizableString?
///
///       // MARK: ValidatableViewModelRequestError Protocol
///       public let validations: [ValidationResult]
///       public init(validations: [ValidationResult]) {
///           self.init(message: nil, validations: validations)
///       }
///
///       // MARK: Initialization Methods
///       public init(message: LocalizableString?, validations: [ValidationResult] = []) {
///           self.message = message
///           self.validations = validations
///       }
///   }
///
///   public init(
///       query: Query? = nil,
///       fragment: Fragment? = nil,
///       requestBody: RequestBody? = nil,
///       responseBody: ResponseBody? = nil
///   ) {
///       self.query = query;
///       self.requestBody = requestBody
///       self.responseBody = responseBody
///   }
/// }
/// ```
public protocol ValidatableViewModelRequest: ViewModelRequest
    where RequestBody: ServerRequestBody & ValidatableModel,
    ResponseBody: RequestableViewModel,
    ResponseError: ValidatableViewModelRequestError {}

public extension ValidatableViewModelRequest {
    var action: ServerRequestAction {
        .create
    }
}

/// ``ValidatableViewModelRequestError`` provides for the transmission of
public protocol ValidatableViewModelRequestError: ServerRequestError {
    var validations: [ValidationResult] { get }

    init(validations: [ValidationResult])
}
