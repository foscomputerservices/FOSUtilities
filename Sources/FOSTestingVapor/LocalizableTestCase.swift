// LocalizableTestCase.swift
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

#if canImport(Vapor)
import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Vapor

public extension LocalizableTestCase {

    /// The port that the test server runs on
    var testServerPort: Int { 8888 }

    /// Returns a localized *Vapor.Application* to use with tests
    ///
    /// - Parameter localizationStore: The **LocalizationStore** containing localized values to use for the tests (default: self.locStore)
    func vaporApplication(localizationStore: LocalizationStore? = nil) async throws -> Vapor.Application {
        let result = try await Application.make(.testing)
        result.http.server.configuration.port = testServerPort
        result.localizationStore = localizationStore ?? locStore

        return result
    }

    /// Returns a *Vapor.Request*
    ///
    /// - Parameter application: The *Vapor.Application* from which to retrieve the *Vapor.Request*
    /// - Parameter locale: The *Locale* to bind the *Vapor.Request* to (default: Self.en)
    func vaporRequest(
        application: Vapor.Application? = nil,
        locale: Locale = Self.en
    ) async throws -> Vapor.Request {
        let localApp: Application = if let application {
            application
        } else {
            try await vaporApplication()
        }

        return Vapor.Request(
            application: localApp,
            method: .GET,
            headers: [
                HTTPHeaders.Name.acceptLanguage.description: locale.identifier
            ],
            on: localApp.eventLoopGroup.next()
        )
    }
}
#endif
