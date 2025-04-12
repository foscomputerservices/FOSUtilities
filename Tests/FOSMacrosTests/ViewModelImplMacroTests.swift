// ViewModelImplMacroTests.swift
//
// Created by David Hunt on 4/12/25
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

#if os(macOS) || os(Linux)
import FOSFoundation
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class ViewModelImplMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "ViewModelImpl": ViewModelImplMacro.self
    ]

    func testBlankExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModelImpl struct TestViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestViewModel: ViewModel {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testSimpleLocalizedStringExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModelImpl struct TestViewModel {
                @LocalizedString public var name
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                @LocalizedString public var name
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_name.localizationId: "name"]
                }
            }

            extension TestViewModel: ViewModel {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testSkipViewModelExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModelImpl struct TestViewModel: ViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
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

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testComplexLocalizableStringExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModelImpl
            struct TestViewModel: RequestableViewModel {
                typealias Request = TestViewModelRequest

                @LocalizedString var aLocalizedString
                @LocalizedString(parentKeys: "aField") var title
                @LocalizedString(parentKeys: "aField", propertyName: "title") var aFieldTitle
                @LocalizedString(parentKeys: "aField", "validationMessages") var error1
                @LocalizedString(parentKeys: "aField", "validationMessages") var error2
                @LocalizedString(propertyName: "pieces", index: 0) var firstPiece
                @LocalizedInt(value: 42) var aLocalizedInt
                @LocalizedStrings var pieces
                @LocalizedString var separator
                @LocalizedCompoundString(pieces: \._pieces) var aLocalizedCompoundNoSep
                @LocalizedCompoundString(pieces: \._pieces, separator: \Self._separator) var aLocalizedCompoundSep

                @LocalizedSubs(substitutions: \.substitutions) var aLocalizedSubstitution
                private let substitutions: [String: LocalizableInt]

                var vmId = ViewModelId()

                public var displayName: LocalizableString { .constant("TestVM") }

                init() {
                    self.substitutions = [
                        "aSub": .init(value: 42)
                    ]
                }

                public static func stub() -> Self {
                    fatalError()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel: RequestableViewModel {
                typealias Request = TestViewModelRequest

                @LocalizedString var aLocalizedString
                @LocalizedString(parentKeys: "aField") var title
                @LocalizedString(parentKeys: "aField", propertyName: "title") var aFieldTitle
                @LocalizedString(parentKeys: "aField", "validationMessages") var error1
                @LocalizedString(parentKeys: "aField", "validationMessages") var error2
                @LocalizedString(propertyName: "pieces", index: 0) var firstPiece
                @LocalizedInt(value: 42) var aLocalizedInt
                @LocalizedStrings var pieces
                @LocalizedString var separator
                @LocalizedCompoundString(pieces: \._pieces) var aLocalizedCompoundNoSep
                @LocalizedCompoundString(pieces: \._pieces, separator: \Self._separator) var aLocalizedCompoundSep

                @LocalizedSubs(substitutions: \.substitutions) var aLocalizedSubstitution
                private let substitutions: [String: LocalizableInt]

                var vmId = ViewModelId()

                public var displayName: LocalizableString { .constant("TestVM") }

                init() {
                    self.substitutions = [
                        "aSub": .init(value: 42)
                    ]
                }

                public static func stub() -> Self {
                    fatalError()
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_aLocalizedString.localizationId: "aLocalizedString", _title.localizationId: "title", _aFieldTitle.localizationId: "aFieldTitle", _error1.localizationId: "error1", _error2.localizationId: "error2", _firstPiece.localizationId: "firstPiece", _aLocalizedInt.localizationId: "aLocalizedInt", _pieces.localizationId: "pieces", _separator.localizationId: "separator", _aLocalizedCompoundNoSep.localizationId: "aLocalizedCompoundNoSep", _aLocalizedCompoundSep.localizationId: "aLocalizedCompoundSep", _aLocalizedSubstitution.localizationId: "aLocalizedSubstitution"]
                }
            }

            extension TestViewModel: ViewModel {
            }

            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
