// ServerRequest.swift
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

import Foundation

/// Interact with web server resources over HTTP
///
/// The ``ServerRequest`` protocol provides for a standardized way to interact with
/// web server resources using REST semantics.
///
/// A typical usage of ``ServerRequest`` that retrieves a model from the database
/// might look as follows:
///
/// ```swift
/// final class MyRequest: ServerRequest {
///     typealias Fragment = EmptyFragment
///     typealias RequestBody = EmptyBody
///
///     let action: ServerRequestAction = .show
///     let query: Query?
///     var responseBody: ResponseBody?
///
///     struct Query: SystemQuery {
///         let modelId: Int
///     }
///
///     struct ResponseBody: ServerRequestBody {
///         let id: Int
///         let firstName: String
///         let lastName: String
///     }
/// }
/// ```
public protocol ServerRequest: AnyObject, Identifiable, Hashable, Codable, Sendable {
    associatedtype Query: ServerRequestQuery
    associatedtype Fragment: ServerRequestFragment
    associatedtype RequestBody: ServerRequestBody
    associatedtype ResponseBody: ServerRequestBody
    associatedtype ResponseError: ServerRequestError

    static var path: String { get }
    static var baseTypeName: String { get }

    var action: ServerRequestAction { get }
    var query: Query? { get }
    var fragment: Fragment? { get }
    var requestBody: RequestBody? { get }
    var responseBody: ResponseBody? { get set }

    init(query: Query?, fragment: Fragment?, requestBody: RequestBody?, responseBody: ResponseBody?)
}

public extension ServerRequest {
    // MARK: Default Implementations

    /// The HTTP *path* of the request
    ///
    /// The default implementation uses ``path(for:)`` to generate a
    /// path based on Self.self.  This serves as the base URL for the request.
    ///
    /// The ``ServerRequest/RequestBody`` and ``ServerRequest/ResponseBody`` are then used to
    /// extend the path using the ``subPath`` property  This guarantees a unique
    /// automatically generated path for every ``ServerRequest``
    /// implementation.
    static var path: String {
        let basePath = String(describing: Self.self)
        let requestBodyPath = RequestBody.bodyPath.cleanBodyPath
        let responseBodyPath = ResponseBody.bodyPath.cleanBodyPath

        return basePath
            .replacingOccurrences(of: Self.baseTypeName, with: "")
            .cleanBasePath
            .appending(requestBodyPath + responseBodyPath)
            .snakeCased()
            .trimmingCharacters(in: .init(charactersIn: "_"))
    }

    static var baseTypeName: String { "" }
}

public extension URL {
    func appending<Request: ServerRequest>(serverRequest: Request) throws -> URL? {
        guard let extraPath = Request.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        let result = appendingPathComponent(extraPath)

        if let queryItems = try queryItems(from: serverRequest) {
            return result.appending(queryItems: queryItems)
        } else {
            return result
        }
    }

    private func queryItems(from serverRequest: some ServerRequest) throws -> [URLQueryItem]? {
        guard let query = serverRequest.query else {
            return nil
        }

        return try [.init(name: query.toJSON(), value: nil)]
    }
}

public extension ServerRequest where Query == EmptyQuery {
    var query: EmptyQuery? { nil }
}

public extension ServerRequest where Fragment == EmptyFragment {
    var fragment: EmptyFragment? { nil }
}

public extension ServerRequest where RequestBody == EmptyBody {
    var requestBody: EmptyBody? { nil }
}

public extension ServerRequest where ResponseBody == EmptyBody {
    var responseBody: EmptyBody? {
        get { nil }
        set {} // swiftlint:disable:this unused_setter_value
    }
}

// MARK: Equatable

public func == <S: ServerRequest>(lhs: S, rhs: S) -> Bool {
    lhs.id == rhs.id
}

private extension String {
    var cleanBasePath: String {
        // REVIEWED dgh: throw should not occur as we are parsing
        //      a constant string.  If the string is not parsable, it
        //      will be caught through testing.

        // swiftlint:disable:next force_try
        try! replacingOccurrences(of: "Request", with: "")
            .replacing(pattern: "<(.+)>", with: "$1")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    var cleanBodyPath: String {
        isEmpty || self == "empty_body" || self == "request_body"
            ? ""
            : "_\(self)"
    }
}

public extension ServerRequest {
    // MARK: Hashable Protocol

    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

/// A `ServerRequestAction` tells the server how to handle the data that is submitted
public enum ServerRequestAction: String, Codable, CaseIterable, Hashable, Sendable {
    /// Retrieve the requested information
    ///
    /// - Note: Creates a **GET** HTTP Request
    case show

    /// Create a new model from the given data
    ///
    /// - Note: Creates a **POST** HTTP Request
    case create

    /// The server should "soft" delete an existing model
    ///
    /// - Note: Creates a **DELETE** HTTP Request
    case delete

    /// The server should destroy an existing model
    ///
    /// - Note: Creates a **DELETE** HTTP Request
    case destroy

    /// The server should update an existing model with the given data
    ///
    /// - Note: Creates a **PATCH** HTTP Request
    case update

    /// Replace an existing model with the given data
    ///
    /// - Note: Creates a **PUT** HTTP Request
    case replace

    public static var GET: Self { .show }
    public static var POST: Self { .create }
    public static var PUT: Self { .replace }
    public static var PATCH: Self { .update }
    public static var DELETE: Self { .delete }
    public static var DESTROY: Self { .destroy }
}

/// Data that will be encoded into the HTTP Query
public protocol ServerRequestQuery: Codable, Hashable, Sendable {}

/// Represents an empty query
///
/// When implementing a *ServerRequest* that does not
/// have a query element, the request can be defined as:
///
/// ```swift
/// final class MyRequest: ServerRequest {
///     ...
///     typealias Query = EmptyQuery
///     ...
/// }
/// ```
public struct EmptyQuery: ServerRequestQuery {
    public init() {}
}

/// Represents data that will be encoded into the HTTP Fragment
public protocol ServerRequestFragment: Codable, Hashable, Sendable {}

/// Represents an empty query
///
/// When implementing a *ServerRequest* that does not
/// have a query element, the request can be defined as:
///
/// ```swift
/// final class MyRequest: ServerRequest {
///     ...
///     typealias Fragment = EmptyFragment
///     ...
/// }
/// ```
public struct EmptyFragment: ServerRequestFragment {}

/// Data that will be encoded into the HTTP request's body and/or response
public protocol ServerRequestBody: Codable, Sendable {
    /// Describes a sub-path that is used to request the body
    ///
    /// By default the type name of the ``ServerRequestBody`` is used
    /// to create a unique path for each ``ServerRequestBody`` type.
    ///
    /// For example, if the type is MyBody, then the bodyPath will be "my_body".
    /// If the type is generic, then the generic constraints will be added to the path
    /// (e.g. MyBody<String> will be "my_body_string").
    static var bodyPath: String { get }

    /// Maximum body size for collection by the server
    ///
    /// When set, the server will collect the entire request body up to this
    /// size before processing. This is required for large uploads that exceed
    /// the server's default streaming threshold.
    ///
    /// - Note: If `nil`, the server's default collection behavior is used.
    static var maxBodySize: ServerRequestBodySize? { get }
}

public extension ServerRequestBody {
    static var bodyPath: String {
        Self.bodyPath(for: Self.self)
    }

    static var maxBodySize: ServerRequestBodySize? { nil }

    static func bodyPath<Model: ServerRequestBody>(for model: Model.Type) -> String {
        let path = String(describing: Model.self)
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .snakeCased()

        return "\(path)"
    }
}

/// A ``ServerRequestBody`` that can be used when no request/response body is
/// required for the ``ServerRequest``
///
/// When implementing a ``ServerRequestBody`` that does not
/// have a body, the request can be defined as:
///
/// ```swift
/// final class MyRequest: ServerRequest {
///     ...
///     typealias RequestBody = EmptyQuery
///     typealias ResponseBody = EmptyQuery
///     ...
/// }
/// ```
public struct EmptyBody: ServerRequestBody {
    public init() {}

    public static var bodyPath: String { "" }
}

/// Represents a byte size for request body collection limits
///
/// Use this to specify the maximum size of request bodies that should
/// be collected before processing. This is particularly useful for
/// file uploads or large form submissions.
///
/// ## Example
///
/// ```swift
/// struct FileUploadBody: ServerRequestBody {
///     static var maxBodySize: ServerRequestBodySize? { .mb(50) }
///
///     let fileName: String
///     let fileData: Data
/// }
/// ```
public enum ServerRequestBodySize: Equatable, Hashable, Sendable {
    /// Raw bytes
    case bytes(_ count: UInt)
    /// Kilobytes (× 1,024)
    case kb(_ count: UInt)
    /// Megabytes (× 1,048,576)
    case mb(_ count: UInt)
    /// Gigabytes (× 1,073,741,824)
    case gb(_ count: UInt)

    /// The size in bytes
    public var byteCount: UInt {
        switch self {
        case .bytes(let count): count
        case .kb(let count): count << 10
        case .mb(let count): count << 20
        case .gb(let count): count << 30
        }
    }
}

/// A custom *Error* implementation that the server will send in the event of an error
///
/// If the server encounters an error, it can return JSON in the response body.  If
/// the response body cannot be converted into ``ServerRequest/responseBody->ResponseBody?``,
/// then an attempt will be made to convert it to ``ServerRequest/ResponseError``.  The resulting
/// error will be thrown by the requesting api.
///
/// ## Simple Errors
///
/// For errors without associated values, use ``LocalizableString`` for user-facing messages:
///
/// ```swift
/// struct MyError: ServerRequestError {
///     let code: ErrorCode
///     let message: LocalizableString
///
///     enum ErrorCode: String, Codable, Sendable {
///         case serverFailed
///         case applicationFailed
///
///         var message: LocalizableString {
///             .localized(for: Self.self, parentType: MyError.self, propertyName: rawValue)
///         }
///     }
///
///     init(code: ErrorCode) {
///         self.code = code
///         self.message = code.message
///     }
/// }
/// ```
///
/// With YAML localization:
///
/// ```yaml
/// en:
///   MyError:
///     ErrorCode:
///       serverFailed: "The server failed"
///       applicationFailed: "The application failed"
/// ```
///
/// ## Errors with Associated Values
///
/// For errors that need dynamic data in their messages, use ``LocalizableSubstitutions``:
///
/// ```swift
/// struct QuotaError: ServerRequestError {
///     let code: ErrorCode
///     let message: LocalizableSubstitutions
///
///     enum ErrorCode: Codable, Sendable {
///         case quotaExceeded(requested: Int, maximum: Int)
///
///         var message: LocalizableSubstitutions {
///             switch self {
///             case .quotaExceeded(let requested, let maximum):
///                 .init(
///                     baseString: .localized(for: Self.self, parentType: QuotaError.self, propertyName: "quotaExceeded"),
///                     substitutions: [
///                         "requested": LocalizableInt(value: requested),
///                         "maximum": LocalizableInt(value: maximum)
///                     ]
///                 )
///             }
///         }
///     }
///
///     init(code: ErrorCode) {
///         self.code = code
///         self.message = code.message
///     }
/// }
/// ```
///
/// With YAML localization using `%{key}` substitution points:
///
/// ```yaml
/// en:
///   QuotaError:
///     ErrorCode:
///       quotaExceeded: "Requested %{requested} exceeds maximum %{maximum}"
/// ```
///
/// ## Usage
///
/// ```swift
/// final class MyRequest: ServerRequest {
///     typealias ResponseError = MyError
///     // ...
/// }
///
/// // Type-safe error handling
/// do {
///     try await request.processRequest(mvvmEnv: mvvmEnv)
/// } catch let error as MyError {
///     showAlert(error.message)
/// }
/// ```
public protocol ServerRequestError: Error, Codable, Sendable {}

/// Represents that no error is expected
///
/// When implementing a *ServerRequest* that does not
/// have a well defined error result, the request can be defined ad:
///
/// ```swift
/// final class MyRequest: ServerRequest {
///     ...
///     typealias ResponseError = EmptyError
///     ...
/// }
/// ```
public struct EmptyError: ServerRequestError {
    public init() {}
}
