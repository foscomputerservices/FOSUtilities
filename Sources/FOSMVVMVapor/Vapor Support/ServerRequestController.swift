// ServerRequestController.swift
//
// Copyright 2026 FOS Computer Services, LLC
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
///             let body = try req.content.decode(ReplaceBerthRequest.RequestBody.self)
///             return try await BerthPage(replacing: body, on: req.db)
///         }
///     ]
/// }
///
/// // boot:
/// try app.routes.register(collection: ReplaceBerthController())
/// ```
///
/// Prefer ``Vapor/RoutesBuilder/register(request:app:)`` — it instantiates this mechanism
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

    /// The actions this controller serves, registered at ``ControllerRouting/baseURL``.
    /// Each action's HTTP method and body handling fall out of the action itself, so the
    /// dispatch layer never re-derives the verb.
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

        // The route is the request's: its path components and, per action, its HTTP
        // method both fall out of TRequest — never a registration-site switch. The method
        // comes from ServerRequestAction's own string (the single source the client fetch
        // side also reads). The group attaches the binding middleware only; `.pathComponents`
        // splits a multi-segment path correctly (a single `.constant` would corrupt "a/b").
        let group = routes.grouped(VaporServerRequestMiddleware<TRequest>())
        let path = TRequest.path.pathComponents
        let bodyStrategy = TRequest.RequestBody.maxBodySize.bodyStreamStrategy

        for (action, processor) in actions {
            group.on(HTTPMethod(rawValue: action.httpMethod), path, body: bodyStrategy) { req in
                // The handler, end to end: bind the typed request, process it, encode the
                // response. A processor that needs a wire body decodes it from `req` itself
                // (its RequestBody type is concrete at registration) — nothing to decide here.
                let request: TRequest = try req.requireServerRequest()
                return try await processor(req, request).buildResponse(req)
            }
        }
    }
}

public enum ServerRequestControllerError: Error, CustomDebugStringConvertible {
    case invalidAction(ServerRequestAction)

    public var debugDescription: String {
        switch self {
        case .invalidAction(let action):
            "Invalid ServerRequestAction combination involving \(action): .delete and .destroy both map to HTTP DELETE at one URL — two deletion semantics need two request types. Register one of them on this controller."
        }
    }
}
