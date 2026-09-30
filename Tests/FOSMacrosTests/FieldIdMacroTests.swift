// FieldIdMacroTests.swift
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
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class FieldIdMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "fieldId": FieldIdMacro.self
    ]

    func testPropertyExpansionScopesByTheRootType() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.title)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Card", named: "title")
            """#,
            macros: testMacros
        )
    }

    func testAProtocolRootedKeyPathScopesByTheProtocol() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\CardFields.title)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "CardFields", named: "title")
            """#,
            macros: testMacros
        )
    }

    func testTwoRootsWithTheSamePropertyScopeApart() {
        assertMacroExpansion(
            #"""
            let card = #fieldId(\Card.title)
            let board = #fieldId(\Board.title)
            """#,
            expandedSource: #"""
            let card = FormFieldIdentifier._property(in: "Card", named: "title")
            let board = FormFieldIdentifier._property(in: "Board", named: "title")
            """#,
            macros: testMacros
        )
    }

    func testAQualifiedRootKeepsItsSpelling() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Outer.Inner.title)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Outer.Inner", named: "title")
            """#,
            macros: testMacros
        )
    }

    func testANestedPropertyIsOneFieldOfTheRootType() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.author.name)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Card", named: "author.name")
            """#,
            macros: testMacros
        )
    }

    func testAGenericRootKeepsItsArguments() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Box<Card>.title)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Box<Card>", named: "title")
            """#,
            macros: testMacros
        )
    }

    func testSelfResolvesToTheExtendedProtocol() {
        assertMacroExpansion(
            #"""
            extension CardFields {
                static var titleFieldId: FormFieldIdentifier {
                    #fieldId(\Self.title)
                }
            }
            """#,
            expandedSource: #"""
            extension CardFields {
                static var titleFieldId: FormFieldIdentifier {
                    FormFieldIdentifier._property(in: "CardFields", named: "title")
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testTheSameLineInAnotherFieldsExtensionScopesToThatProtocol() {
        assertMacroExpansion(
            #"""
            extension BoardFields {
                static var titleFieldId: FormFieldIdentifier {
                    #fieldId(\Self.title)
                }
            }
            """#,
            expandedSource: #"""
            extension BoardFields {
                static var titleFieldId: FormFieldIdentifier {
                    FormFieldIdentifier._property(in: "BoardFields", named: "title")
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testSelfKeepsTheSpellingOfANestedExtendedType() {
        assertMacroExpansion(
            #"""
            extension Outer.Inner {
                static var titleFieldId: FormFieldIdentifier {
                    #fieldId(\Self.title)
                }
            }
            """#,
            expandedSource: #"""
            extension Outer.Inner {
                static var titleFieldId: FormFieldIdentifier {
                    FormFieldIdentifier._property(in: "Outer.Inner", named: "title")
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testSelfResolvesToTheEnclosingEnum() {
        assertMacroExpansion(
            #"""
            enum Card {
                static let titleFieldId = #fieldId(\Self.title)
            }
            """#,
            expandedSource: #"""
            enum Card {
                static let titleFieldId = FormFieldIdentifier._property(in: "Card", named: "title")
            }
            """#,
            macros: testMacros
        )
    }

    func testSelfResolvesToTheEnclosingStruct() {
        assertMacroExpansion(
            #"""
            struct Card {
                static let titleFieldId = #fieldId(\Self.title)
            }
            """#,
            expandedSource: #"""
            struct Card {
                static let titleFieldId = FormFieldIdentifier._property(in: "Card", named: "title")
            }
            """#,
            macros: testMacros
        )
    }

    func testSelfResolvesToTheWholeEnclosingChain() {
        assertMacroExpansion(
            #"""
            struct Outer {
                struct Inner {
                    static let titleFieldId = #fieldId(\Self.title)
                }
            }
            """#,
            expandedSource: #"""
            struct Outer {
                struct Inner {
                    static let titleFieldId = FormFieldIdentifier._property(in: "Outer.Inner", named: "title")
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testANestedTypeInAnExtensionCarriesTheExtendedTypeToo() {
        assertMacroExpansion(
            #"""
            extension Board {
                struct Inner {
                    static let titleFieldId = #fieldId(\Self.title)
                }
            }
            """#,
            expandedSource: #"""
            extension Board {
                struct Inner {
                    static let titleFieldId = FormFieldIdentifier._property(in: "Board.Inner", named: "title")
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testSelfInAGenericExtensionDropsTheGenericArguments() {
        assertMacroExpansion(
            #"""
            extension Box<Card> {
                static var titleFieldId: FormFieldIdentifier {
                    #fieldId(\Self.title)
                }
            }
            """#,
            expandedSource: #"""
            extension Box<Card> {
                static var titleFieldId: FormFieldIdentifier {
                    FormFieldIdentifier._property(in: "Box", named: "title")
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testBackticksAreNotPartOfTheScopeOrTheProperty() {
        assertMacroExpansion(
            #"""
            struct `Card` {
                static let classFieldId = #fieldId(\Self.`class`)
            }
            """#,
            expandedSource: #"""
            struct `Card` {
                static let classFieldId = FormFieldIdentifier._property(in: "Card", named: "class")
            }
            """#,
            macros: testMacros
        )
    }

    func testABacktickedRootScopesByItsBareName() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\`Card`.title)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Card", named: "title")
            """#,
            macros: testMacros
        )
    }

    func testSelfWithNoEnclosingTypeDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Self.title)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Self.title)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId cannot resolve 'Self' outside a type: name the type, #fieldId(\Card.title)"#,
                    line: 1,
                    column: 25
                )
            ],
            macros: testMacros
        )
    }

    func testIndexedExpansion() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.tags, index: 2)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Card", named: "tags", index: 2)
            """#,
            macros: testMacros
        )
    }

    func testIndexedExpansionCarriesTheIndexExpression() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.tags, index: index + 1)
            """#,
            expandedSource: #"""
            let fieldId = FormFieldIdentifier._property(in: "Card", named: "tags", index: index + 1)
            """#,
            macros: testMacros
        )
    }

    func testIndexedSelfResolvesToTheExtendedProtocol() {
        assertMacroExpansion(
            #"""
            extension CardFields {
                static func tagFieldId(_ index: Int) -> FormFieldIdentifier {
                    #fieldId(\Self.tags, index: index)
                }
            }
            """#,
            expandedSource: #"""
            extension CardFields {
                static func tagFieldId(_ index: Int) -> FormFieldIdentifier {
                    FormFieldIdentifier._property(in: "CardFields", named: "tags", index: index)
                }
            }
            """#,
            macros: testMacros
        )
    }

    func testRootlessKeyPathDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\.title)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\.title)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId needs the key path's root: write #fieldId(\Card.title), or #fieldId(\Self.title) inside the type"#,
                    line: 1,
                    column: 24
                )
            ],
            macros: testMacros
        )
    }

    func testSubscriptComponentDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.tags[0])
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Card.tags[0])
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId cannot name a subscript: name the property and pass the element's position, #fieldId(\Card.tags, index: index)"#,
                    line: 1,
                    column: 34
                )
            ],
            macros: testMacros
        )
    }

    func testProjectedComponentDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.$title)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Card.$title)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId names the property, not its projection: drop the '$', #fieldId(\Card.title)"#,
                    line: 1,
                    column: 29
                )
            ],
            macros: testMacros
        )
    }

    func testNoPropertyComponentDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.self)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Card.self)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId needs the key path to end on a property: write #fieldId(\Card.title)"#,
                    line: 1,
                    column: 29
                )
            ],
            macros: testMacros
        )
    }

    func testOptionalChainComponentDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.title?)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Card.title?)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId needs the key path to end on a property: write #fieldId(\Card.title)"#,
                    line: 1,
                    column: 35
                )
            ],
            macros: testMacros
        )
    }

    func testATypeComponentAfterAPropertyDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.author.Name)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Card.author.Name)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId reads a capitalized component as a type and a lowercase one as a property: 'Name' is capitalized but follows a property, so write the types first, #fieldId(\Card.author.name)"#,
                    line: 1,
                    column: 36
                )
            ],
            macros: testMacros
        )
    }

    func testATypeComponentAfterALowercaseRootDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\card.Thing.x)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\card.Thing.x)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId reads a capitalized component as a type and a lowercase one as a property: 'Thing' is capitalized but follows a property, so write the types first, #fieldId(\Card.author.name)"#,
                    line: 1,
                    column: 29
                )
            ],
            macros: testMacros
        )
    }

    func testAllTypeComponentsNameNoPropertyDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(\Card.Inner)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(\Card.Inner)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId reads a capitalized component as a type, so this key path names no property: add the property, #fieldId(\Outer.Inner.title)"#,
                    line: 1,
                    column: 24
                )
            ],
            macros: testMacros
        )
    }

    func testNonKeyPathArgumentDiagnostic() {
        assertMacroExpansion(
            #"""
            let fieldId = #fieldId(keyPath)
            """#,
            expandedSource: #"""
            let fieldId = #fieldId(keyPath)
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: #"#fieldId takes a key path literal that names its root: write #fieldId(\Card.title)"#,
                    line: 1,
                    column: 24
                )
            ],
            macros: testMacros
        )
    }
}
#endif
