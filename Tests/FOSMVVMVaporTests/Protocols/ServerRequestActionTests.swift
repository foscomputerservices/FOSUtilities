// ServerRequestActionTests.swift
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
import FOSTesting
import FOSTestingVapor
import Foundation
import Testing
import Vapor

@Suite("ServerRequestAction Tests")
struct ServerRequestActionTests: LocalizableTestCase {
    @Test(arguments: [
        (httpMethod: HTTPMethod.GET, uri: nil as String?, expectedAction: ServerRequestAction.show),
        (httpMethod: .POST, uri: nil as String?, expectedAction: .create),
        (httpMethod: .PUT, uri: nil as String?, expectedAction: .replace),
        (httpMethod: .PATCH, uri: nil as String?, expectedAction: .update),
        (httpMethod: .DELETE, uri: nil as String?, expectedAction: .delete),
        (httpMethod: .DELETE, uri: "http://example.com/destroy", expectedAction: .destroy)
    ]) func initHTTPMethod(tuple: (httpMethod: HTTPMethod, uri: String?, expectedAction: ServerRequestAction)) async throws {
        let httpMethod = tuple.httpMethod
        let uri: URI = tuple.uri == nil
            ? .init(string: "https://example.com")
            : .init(string: tuple.uri!)
        let expectedAction = tuple.expectedAction

        let action = try ServerRequestAction(
            httpMethod: httpMethod,
            uri: uri
        )

        #expect(action == expectedAction)
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: .module,
            resourceDirectoryName: "TestYAML"
        )
    }
}
