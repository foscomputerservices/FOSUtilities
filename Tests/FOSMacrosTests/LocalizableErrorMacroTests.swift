// LocalizableErrorMacroTests.swift
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

#if os(macOS)
import FOSFoundation
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class LocalizableErrorMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "LocalizableError": LocalizableErrorMacro.self
    ]

    func testLocalizedStringExpansion() {
        assertMacroExpansion(
            #"""
            @LocalizableError struct TestError {
                @LocalizedString public var errorMessage
            }
            """#,
            expandedSource: #"""
            struct TestError {
                @LocalizedString public var errorMessage

                public func propertyNames() -> [LocalizableId: String] {
                    [_errorMessage.localizationId: "errorMessage"]
                }
            }

            extension TestError: LocalizableError {
            }

            extension TestError: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testLocalizedSubsExpansion() {
        assertMacroExpansion(
            #"""
            @LocalizableError struct TestError {
                @LocalizedSubs(substitutions: \.subs) public var errorMessage
                private var subs: [String: any Localizable] { [:] }
            }
            """#,
            expandedSource: #"""
            struct TestError {
                @LocalizedSubs(substitutions: \.subs) public var errorMessage
                private var subs: [String: any Localizable] { [:] }

                public func propertyNames() -> [LocalizableId: String] {
                    [_errorMessage.localizationId: "errorMessage"]
                }
            }

            extension TestError: LocalizableError {
            }

            extension TestError: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testClientHostedOptionEmitsTheMarkerConformance() {
        assertMacroExpansion(
            #"""
            @LocalizableError(options: [.clientHosted]) struct TestError {
                @LocalizedString public var errorMessage
            }
            """#,
            expandedSource: #"""
            struct TestError {
                @LocalizedString public var errorMessage

                public func propertyNames() -> [LocalizableId: String] {
                    [_errorMessage.localizationId: "errorMessage"]
                }
            }

            extension TestError: LocalizableError, ClientHostedLocalizableError {
            }

            extension TestError: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testExplicitConformancesAreNotDuplicated() {
        assertMacroExpansion(
            #"""
            @LocalizableError struct TestError: LocalizableError, RetrievablePropertyNames {
                @LocalizedString public var errorMessage
            }
            """#,
            expandedSource: #"""
            struct TestError: LocalizableError, RetrievablePropertyNames {
                @LocalizedString public var errorMessage

                public func propertyNames() -> [LocalizableId: String] {
                    [_errorMessage.localizationId: "errorMessage"]
                }
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testEnumIsRejected() {
        assertMacroExpansion(
            #"""
            @LocalizableError enum TestError {
                case boom
            }
            """#,
            expandedSource: #"""
            enum TestError {
                case boom
            }
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "LocalizableErrorMacroError: @LocalizableError can only be applied to structs",
                    line: 1,
                    column: 1
                ),
                DiagnosticSpec(
                    message: "LocalizableErrorMacroError: @LocalizableError can only be applied to structs",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
