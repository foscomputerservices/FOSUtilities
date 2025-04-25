// ServerRequest.swift
//
// Created by David Hunt on 9/4/24
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
/// A typical usage of ``ServerRequest`` that retrieves a record from the database
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
///         let recordId: Int
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

    static var path: String { get }

    var action: ServerRequestAction { get }
    var query: Query? { get }
    var fragment: Fragment? { get }
    var requestBody: RequestBody? { get }
    var responseBody: ResponseBody? { get }

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
            .cleanBasePath
            .appending(requestBodyPath + responseBodyPath)
            .snakeCased()
            .trimmingCharacters(in: .init(charactersIn: "_"))
    }
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

        return try [.init(name: "query", value: query.toJSON())]
    }
}

public extension ServerRequest where Query == EmptyQuery {
    var query: EmptyQuery { .init() }
}

public extension ServerRequest where Fragment == EmptyFragment {
    var fragment: EmptyFragment { .init() }
}

public extension ServerRequest where RequestBody == EmptyBody {
    var requestBody: EmptyBody { .init() }
}

public extension ServerRequest where ResponseBody == EmptyBody {
    var responseBody: EmptyBody { .init() }
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
    /// Returns a nil ``Query``
    var query: Query? { nil }

    /// Returns a nil ``Fragment``
    var fragment: Fragment? { nil }

    /// Returns a nil ``RequestBody``
    var requestBody: RequestBody? { nil }

    /// Returns a nil ``ResponseBody``
    var responseBody: ResponseBody? {
        get { nil }
        set {} // swiftlint:disable:this unused_setter_value
    }

    // MARK: Hashable Protocol

    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

/// A `ServerRequestAction` tells the server how to handle the data that is submitted
public enum ServerRequestAction: String, Codable, CaseIterable, Hashable {
    /// Retrieve the requested information
    ///
    /// - Note: Creates a **GET** HTTP Request
    case show

    /// Create a new record from the given data
    ///
    /// - Note: Creates a **POST** HTTP Request
    case create

    /// The server should destroy an existing record
    ///
    /// - Note: Creates a **DELETE** HTTP Request
    case delete

    /// The server should update an existing record with the given data
    ///
    /// - Note: Creates a **PATCH** HTTP Request
    case update

    /// Replace an existing record with the given data
    ///
    /// - Note: Creates a **PUT** HTTP Request
    case replace

    public static var GET: Self { .show }
    public static var POST: Self { .create }
    public static var PUT: Self { .replace }
    public static var PATCH: Self { .update }
    public static var DELETE: Self { .delete }
}

/// Data that will be encoded into the HTTP Query
public protocol ServerRequestQuery: Codable, Hashable, Sendable {}

/// Represents an empty query
///
/// When implementing a *SystemRequest* that does not
/// have a query element, the request can be defined as:
///
/// ```swift
/// final class MyRequest: SystemRequest {
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
/// When implementing a *SystemRequest* that does not
/// have a query element, the request can be defined as:
///
/// ```swift
/// final class MyRequest: SystemRequest {
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
}

public extension ServerRequestBody {
    static var bodyPath: String {
        Self.bodyPath(for: Self.self)
    }

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
/// final class MyRequest: SystemRequest {
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
