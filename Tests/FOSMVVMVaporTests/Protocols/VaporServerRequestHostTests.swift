// VaporServerRequestHostTests.swift
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

import FOSFoundation
import FOSMVVM
import FOSTesting
import Foundation
import Testing
import Vapor

// TODO: Resolve odd NSTreatUnknownArgumentsAsOpen error

// As of Swift 6.0 beta, running this test yields: 🤷‍♂️
//
// Test performBasicRequest() recorded an issue at
// VaporServerRequestHostTests.swift:28:6: Caught error:
// Unknown command `-NSTreatUnknownArgumentsAsOpen`

// @Suite("Vapor Server Request Host Tests")
// struct VaporServerRequestHostTests {
//    @Test func performBasicRequest() async throws {
//        let response = try await serverRequestTest.test(
//            request: .init(),
//            locale: Locale(identifier: "en")
//        )
//
//        #expect(try response.aLocalizedString.localizedString != "")
//    }
//
//    private let serverRequestTest: VaporServerRequestTest<TestViewModelRequest>
//    init() async throws {
//        self.serverRequestTest = try .init(
//            for: TestViewModelRequest.self,
//            bundle: Bundle.module,
//            resourceDirectoryName: "TestYAML"
//        )
//    }
// }
