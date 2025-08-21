// ViewModelFactoryMacroTests.swift
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

#if os(macOS)
import FOSFoundation
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class ViewModelFactoryMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "VersionedFactory": ViewModelFactoryMacro.self,
        "Version": ViewModelFactoryMethodMacro.self
    ]

    func testViewModelFactoryMethodMacro() throws {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }

            @VersionedFactory
            extension TestViewModel: ViewModelFactory {
                typealias Context = Int

                @Version(.v1_0_0)
                static func model_v1_0_0(context: Context) async throws -> Self {
                    .stub()
                }

                @Version(.v2_0_0)
                static func model_v2_0_0(context: Context) async throws -> Self {
                    .stub()
                }
            }
            """#,
            expandedSource: #"""
            @ViewModel struct TestViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }
            extension TestViewModel: ViewModelFactory {
                typealias Context = Int
                static func model_v1_0_0(context: Context) async throws -> Self {
                    .stub()
                }
                static func model_v2_0_0(context: Context) async throws -> Self {
                    .stub()
                }

                public static func model(context: Int) async throws -> Self {
                    let version = try context.appVersion

                    if version >= SystemVersion(major: 2, minor: 0, patch: 0) {
                    return try await model_v2_0_0(context: context)
                    }
                    if version >= SystemVersion(major: 1, minor: 0, patch: 0) {
                        return try await model_v1_0_0(context: context)
                    }

                    throw ViewModelFactoryError.versionNotSupported(version.versionString)
                }
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testVaporViewModelFactoryMethodMacro() throws {
        assertMacroExpansion(
            #"""
            struct TestViewModel: ViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }

            final class TestViewModelRequest: ViewModelRequest {
                typealias Query = EmptyQuery
                let responseBody: TestViewModel?

                init(query: FOSMVVM.EmptyQuery? = nil, fragment: FOSMVVM.EmptyFragment? = nil, requestBody: FOSMVVM.EmptyBody? = nil, responseBody: TestViewModel? = nil) {
                    self.responseBody = responseBody
                }
            }

            @VersionedFactory
            extension TestViewModel: VaporViewModelFactory {
                typealias VMRequest = TestViewModelRequest

                @Version(.v1_0_0)
                static func model_v1_0_0(context: VaporModelFactoryContext<VMRequest>) async throws -> Self {
                    .stub()
                }

                @Version(.v2_0_0)
                static func model_v2_0_0(context: VaporModelFactoryContext<VMRequest>) async throws -> Self {
                    .stub()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel: ViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }

            final class TestViewModelRequest: ViewModelRequest {
                typealias Query = EmptyQuery
                let responseBody: TestViewModel?

                init(query: FOSMVVM.EmptyQuery? = nil, fragment: FOSMVVM.EmptyFragment? = nil, requestBody: FOSMVVM.EmptyBody? = nil, responseBody: TestViewModel? = nil) {
                    self.responseBody = responseBody
                }
            }
            extension TestViewModel: VaporViewModelFactory {
                typealias VMRequest = TestViewModelRequest
                static func model_v1_0_0(context: VaporModelFactoryContext<VMRequest>) async throws -> Self {
                    .stub()
                }
                static func model_v2_0_0(context: VaporModelFactoryContext<VMRequest>) async throws -> Self {
                    .stub()
                }

                public static func model(context: Context) async throws -> Self {
                    let version = try context.appVersion

                    if version >= SystemVersion(major: 2, minor: 0, patch: 0) {
                    return try await model_v2_0_0(context: context)
                    }
                    if version >= SystemVersion(major: 1, minor: 0, patch: 0) {
                        return try await model_v1_0_0(context: context)
                    }

                    throw ViewModelFactoryError.versionNotSupported(version.versionString)
                }
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
