// ServerRequestController.swift
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

import FOSFoundation
import FOSMVVM
import Vapor

/// The general dispatch layer for serving a ``ServerRequest``: conform, supply one
/// processor per ``ServerRequestAction``, and register the controller as a route
/// collection — grouping, HTTP-method mapping, body decoding, and typed request
/// binding are derived for you, once.
///
/// ```swift
/// final class ReplaceBerthController: ServerRequestController {
///     typealias TRequest = ReplaceBerthRequest
///
///     let actions: [ServerRequestAction: ActionProcessor] = [
///         .replace: { req, bound in
///             guard let body = bound.requestBody else {
///                 throw ServerRequestControllerError.missingRequestBody
///             }
///             return try await BerthPage(replacing: body, on: req.db)
///         }
///     ]
/// }
///
/// // boot:
/// try app.routes.register(collection: ReplaceBerthController())
/// ```
///
/// Prefer ``Vapor/Application/register(request:)`` — it instantiates this mechanism
/// pre-specialized with the framework's guarded pipelines (declared loads, write
/// gates, the refresh fall-through). Reach for a hand-written controller when an
/// operation falls outside the guarded verbs (e.g. `ReplaceRequest`, multi-record
/// operations): the same general mechanism serves both.
public protocol ServerRequestController: AnyObject, ControllerRouting, RouteCollection, SendableMetatype {
    associatedtype TRequest: ServerRequest

    /// Serves one action: receives the raw `Vapor.Request` (full request power) and
    /// the **bound** typed request — query and sort parsed from the URL, and, on a
    /// body-carrying verb, the decoded `requestBody`.
    typealias ActionProcessor = @Sendable (
        Vapor.Request,
        TRequest
    ) async throws -> TRequest.ResponseBody

    /// The actions this controller serves, each mapped to its HTTP method at
    /// ``ControllerRouting/baseURL`` (`.show` GET · `.create` POST · `.replace` PUT ·
    /// `.update` PATCH · `.delete`/`.destroy` DELETE).
    var actions: [ServerRequestAction: ActionProcessor] { get }
}

public extension ServerRequestController {
    static var baseURL: String {
        TRequest.path
    }

    func boot(routes: RoutesBuilder) throws {
        // One URL carries one handler per HTTP method: .delete and .destroy both ride
        // DELETE, so one controller may register only one of them (two deletion
        // semantics are two request types — two URLs).
        if actions.keys.contains(.delete), actions.keys.contains(.destroy) {
            throw ServerRequestControllerError.invalidAction(.destroy)
        }

        let groupName = Self.baseURL == "/" ? "" : Self.baseURL
        let group = routes
            .grouped(.constant(groupName))
            .grouped(VaporServerRequestMiddleware<TRequest>())
        let bodyStrategy = TRequest.RequestBody.maxBodySize.bodyStreamStrategy

        for (action, processor) in actions {
            switch action {
            case .show:
                group.get { req in
                    try await runServerRequest(req, decodesBody: false, processor: processor)
                }
            case .create:
                group.on(.POST, body: bodyStrategy) { req in
                    try await runServerRequest(req, decodesBody: true, processor: processor)
                }
            case .replace:
                group.on(.PUT, body: bodyStrategy) { req in
                    try await runServerRequest(req, decodesBody: true, processor: processor)
                }
            case .update:
                group.on(.PATCH, body: bodyStrategy) { req in
                    try await runServerRequest(req, decodesBody: true, processor: processor)
                }
            case .delete, .destroy:
                group.on(.DELETE) { req in
                    try await runServerRequest(req, decodesBody: false, processor: processor)
                }
            }
        }
    }
}

public enum ServerRequestControllerError: Error, CustomDebugStringConvertible {
    case invalidAction(ServerRequestAction)
    case missingRequestBody

    public var debugDescription: String {
        switch self {
        case .invalidAction(let action):
            "Invalid ServerRequestAction combination involving \(action): .delete and .destroy both map to HTTP DELETE at one URL — two deletion semantics need two request types. Register one of them on this controller."
        case .missingRequestBody:
            "Server request was missing its request body."
        }
    }
}

// MARK: Private Methods

/// Binds the complete typed request (the middleware parsed query + sort; a body verb
/// decodes `RequestBody` here) and runs the processor. `EmptyBody` requests decode
/// nothing — `requestBody` stays nil.
private func runServerRequest<TRequest: ServerRequest>(
    _ req: Vapor.Request,
    decodesBody: Bool,
    processor: @Sendable (Vapor.Request, TRequest) async throws -> TRequest.ResponseBody
) async throws -> Vapor.Response {
    let bound: TRequest = try req.requireServerRequest()

    let request: TRequest = if decodesBody, TRequest.RequestBody.self != EmptyBody.self {
        try TRequest(
            query: bound.query,
            sort: bound.sort,
            fragment: bound.fragment,
            requestBody: req.content.decode(TRequest.RequestBody.self),
            responseBody: nil
        )
    } else {
        bound
    }

    return try await processor(req, request)
        .buildResponse(req)
}
