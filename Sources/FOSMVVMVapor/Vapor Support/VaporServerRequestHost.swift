// VaporServerRequestHost.swift
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
import Foundation
import Vapor

final class VaporServerRequestHost<Request: ServerRequest>: Sendable {
    init() {}
}

// MARK: RouteCollection Protocol

extension VaporServerRequestHost: RouteCollection where Request.ResponseBody: VaporViewModelFactory {
    func boot(routes: any Vapor.RoutesBuilder) throws {
        let groupName = Request.path != "/"
            ? Request.path
            : "" // When requesting '/', then there's no path

        let group = routes
            // Name the route according to the Request's
            // path
            .grouped(.constant(groupName))
            // Use VaporServerRequestMiddleware to bind the Request
            // to the Vapor.Request
            .grouped(VaporServerRequestMiddleware<Request>())

        group.get { req in
            try await Request.ResponseBody.model(
                req,
                vmRequest: req.requireServerRequest()
            )
        }
    }
}
