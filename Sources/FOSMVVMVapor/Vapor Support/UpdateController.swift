// UpdateController.swift
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

public protocol ServerRequestController: AnyObject, ControllerRouting, RouteCollection {
    associatedtype TRequest: ServerRequest

    typealias ActionProcessor = (
        Vapor.Request,
        TRequest,
        TRequest.RequestBody
    ) async throws -> TRequest.ResponseBody

    var actions: [ServerRequestAction: ActionProcessor] { get }
}

// MARK: Default Implementation

public extension ServerRequestController {
    static var baseURL: String { TRequest.path }

    func boot(routes: RoutesBuilder) throws {
        let groupName = Self.baseURL == "/"
            ? ""
            : Self.baseURL

        let routeGroup = routes
            .grouped(.constant(groupName))

        let bodyStrategy = TRequest.RequestBody.maxBodySize.bodyStreamStrategy

        for pair in actions {
            switch pair.key {
            case .create:
                routeGroup.on(.POST, body: bodyStrategy) { req in
                    try await Self.run(req, processor: pair.value)
                }
            case .replace:
                routeGroup.on(.PUT, body: bodyStrategy) { req in
                    try await Self.run(req, processor: pair.value)
                }
            case .update:
                routeGroup.on(.PATCH, body: bodyStrategy) { req in
                    try await Self.run(req, processor: pair.value)
                }
            default:
                throw ServerRequestControllerError.invalidAction(pair.key)
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
            "Invalid ServerRequestAction: \(action). Only create, replace and update are allowed."
        case .missingRequestBody:
            "Server request was missing its request body."
        }
    }
}

// MARK: Private Methods

private extension ServerRequestController {
    static func run(_ req: Vapor.Request, processor: ActionProcessor) async throws -> Vapor.Response {
        let requestBody: TRequest.RequestBody = if TRequest.RequestBody.self == EmptyBody.self {
            // swiftlint:disable:next force_cast
            (EmptyBody() as! TRequest.RequestBody)
        } else {
            try req.content.decode(TRequest.RequestBody.self)
        }

        let serverRequest = TRequest(
            query: nil,
            fragment: nil,
            requestBody: requestBody,
            responseBody: nil
        )

        return try await processor(req, serverRequest, requestBody)
            .buildResponse(req)
    }
}
