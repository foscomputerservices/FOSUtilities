// RequireVersionedAppMiddleware.swift
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
import Foundation
import Vapor

/// A Vapor *Middleware* implementation that verifies that the calling application
/// is version compatible with the server
///
/// ## Example
///
/// ```swift
/// func routes(_ app: Application) throws {
///     // MARK: Versioned App Routes
///
///     let versionedGroup = unauthorizedGroup
///         .grouped(RequireVersionedAppMiddleware())
///     try versionedGroup.register(collection: MyController())
/// }
/// ```
public final class RequireVersionedAppMiddleware: AsyncMiddleware {
    // MARK: Middleware Protocol

    public func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Ensure that the application that called us is up-to-date
        try req.requireCompatibleAppVersion()

        return try await next.respond(to: req)
    }

    public init() {}
}
