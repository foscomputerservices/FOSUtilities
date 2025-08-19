// FieldValidationModelMacroTests.swift
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

#if os(macOS) || os(Linux)
import FOSFoundation
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class FieldValidationModelMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "FieldValidationModel": FieldValidationModelMacro.self
    ]

    func testBlankExpansion() throws {
        assertMacroExpansion(
            #"""
            @FieldValidationModel struct TestFieldValidationModel {
                var name: String { "TestFieldValidationModel" }
            }
            """#,
            expandedSource: #"""
            struct TestFieldValidationModel {
                var name: String { "TestFieldValidationModel" }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestFieldValidationModel: FieldValidationModel {
            }

            extension TestFieldValidationModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testSimpleLocalizedStringExpansion() throws {
        assertMacroExpansion(
            #"""
            @FieldValidationModel struct TestFieldValidationModel {
                @LocalizedString public var name
            }
            """#,
            expandedSource: #"""
            struct TestFieldValidationModel {
                @LocalizedString public var name

                public func propertyNames() -> [LocalizableId: String] {
                    [_name.localizationId: "name"]
                }
            }

            extension TestFieldValidationModel: FieldValidationModel {
            }

            extension TestFieldValidationModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testSkipFieldValidationModelExpansion() throws {
        assertMacroExpansion(
            #"""
            @FieldValidationModel struct TestFieldValidationModel: FieldValidationModel {
                var name: String { "TestFieldValidationModel" }
            }
            """#,
            expandedSource: #"""
            struct TestFieldValidationModel: FieldValidationModel {
                var name: String { "TestFieldValidationModel" }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestFieldValidationModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testComplexLocalizableStringExpansion() throws {
        assertMacroExpansion(
            #"""
            @FieldValidationModel
            struct TestFieldValidationModel: FieldValidationModel {
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

                init() {
                    self.substitutions = [
                        "aSub": .init(value: 42)
                    ]
                }
            }
            """#,
            expandedSource: #"""
            struct TestFieldValidationModel: FieldValidationModel {
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

                init() {
                    self.substitutions = [
                        "aSub": .init(value: 42)
                    ]
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_aLocalizedString.localizationId: "aLocalizedString", _title.localizationId: "title", _aFieldTitle.localizationId: "aFieldTitle", _error1.localizationId: "error1", _error2.localizationId: "error2", _firstPiece.localizationId: "firstPiece", _aLocalizedInt.localizationId: "aLocalizedInt", _pieces.localizationId: "pieces", _separator.localizationId: "separator", _aLocalizedCompoundNoSep.localizationId: "aLocalizedCompoundNoSep", _aLocalizedCompoundSep.localizationId: "aLocalizedCompoundSep", _aLocalizedSubstitution.localizationId: "aLocalizedSubstitution"]
                }
            }

            extension TestFieldValidationModel: RetrievablePropertyNames {
            }

            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testComplexExpansion() throws {
        assertMacroExpansion(
            #"""
            @FieldValidationModel
            public struct InfoFieldValidationModel: FieldValidationModel {
                // MARK: FieldValidationModel Properties

                @LocalizedSubs(substitutions: \.substitutions) public var Title
                private var substitutions: [String: LocalizableString] { [
                    "exid": .constant(exid.string(includeCompanyCode: true))
                ] }

                @LocalizedString public var connectionTitle
                @LocalizedString public var onTitle
                @LocalizedString public var offTitle
                @LocalizedString public var batteryTitle
                @LocalizedString public var connectTitle
                @LocalizedString public var disconnectTitle
                @LocalizedString public var deleteTitle
                @LocalizedString public var errorTitle
                @LocalizedString public var errorMessage
                @LocalizedString public var errorDismissButtonTitle
            }
            """#,
            expandedSource: #"""
            public struct InfoFieldValidationModel: FieldValidationModel {
                // MARK: FieldValidationModel Properties

                @LocalizedSubs(substitutions: \.substitutions) public var Title
                private var substitutions: [String: LocalizableString] { [
                    "exid": .constant(exid.string(includeCompanyCode: true))
                ] }

                @LocalizedString public var connectionTitle
                @LocalizedString public var onTitle
                @LocalizedString public var offTitle
                @LocalizedString public var batteryTitle
                @LocalizedString public var connectTitle
                @LocalizedString public var disconnectTitle
                @LocalizedString public var deleteTitle
                @LocalizedString public var errorTitle
                @LocalizedString public var errorMessage
                @LocalizedString public var errorDismissButtonTitle

                public func propertyNames() -> [LocalizableId: String] {
                    [_Title.localizationId: "Title", _connectionTitle.localizationId: "connectionTitle", _onTitle.localizationId: "onTitle", _offTitle.localizationId: "offTitle", _batteryTitle.localizationId: "batteryTitle", _connectTitle.localizationId: "connectTitle", _disconnectTitle.localizationId: "disconnectTitle", _deleteTitle.localizationId: "deleteTitle", _errorTitle.localizationId: "errorTitle", _errorMessage.localizationId: "errorMessage", _errorDismissButtonTitle.localizationId: "errorDismissButtonTitle"]
                }
            }

            extension InfoFieldValidationModel: RetrievablePropertyNames {
            }

            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
