// FieldIdMacro.swift
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

#if os(macOS) || os(Linux) || os(Windows)
public import SwiftSyntax
public import SwiftSyntaxMacros
import SwiftDiagnostics

private struct FieldIdMacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    private init(_ id: String, _ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "FOSMacros", id: id)
        self.severity = .error
    }

    static let notAKeyPath = FieldIdMacroDiagnostic(
        "fieldIdNotAKeyPath",
        "#fieldId takes a key path literal that names its root: write #fieldId(\\Card.title)"
    )

    static let rootless = FieldIdMacroDiagnostic(
        "fieldIdRootlessKeyPath",
        "#fieldId needs the key path's root: write #fieldId(\\Card.title), or #fieldId(\\Self.title) inside the type"
    )

    static let noProperty = FieldIdMacroDiagnostic(
        "fieldIdNoPropertyComponent",
        "#fieldId needs the key path to end on a property: write #fieldId(\\Card.title)"
    )

    static let subscriptComponent = FieldIdMacroDiagnostic(
        "fieldIdSubscriptComponent",
        "#fieldId cannot name a subscript: name the property and pass the element's position, #fieldId(\\Card.tags, index: index)"
    )

    static let projectedComponent = FieldIdMacroDiagnostic(
        "fieldIdProjectedComponent",
        "#fieldId names the property, not its projection: drop the '$', #fieldId(\\Card.title)"
    )

    static let unresolvedSelf = FieldIdMacroDiagnostic(
        "fieldIdUnresolvedSelf",
        "#fieldId cannot resolve 'Self' outside a type: name the type, #fieldId(\\Card.title)"
    )

    static let namesNoProperty = FieldIdMacroDiagnostic(
        "fieldIdNamesNoProperty",
        "#fieldId reads a capitalized component as a type, so this key path names no property: add the property, #fieldId(\\Outer.Inner.title)"
    )

    static func typeAfterProperty(_ name: String) -> FieldIdMacroDiagnostic {
        FieldIdMacroDiagnostic(
            "fieldIdTypeAfterProperty",
            "#fieldId reads a capitalized component as a type and a lowercase one as a property: '\(name)' is capitalized but follows a property, so write the types first, #fieldId(\\Card.author.name)"
        )
    }
}

public struct FieldIdMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = node.arguments

        guard let keyPathArgument = arguments.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: FieldIdMacroDiagnostic.notAKeyPath)
            ])
        }

        guard let keyPath = keyPathArgument.expression.as(KeyPathExprSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(keyPathArgument.expression), message: FieldIdMacroDiagnostic.notAKeyPath)
            ])
        }

        guard let root = keyPath.root else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(keyPath), message: FieldIdMacroDiagnostic.rootless)
            ])
        }

        guard !keyPath.components.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(keyPath), message: FieldIdMacroDiagnostic.noProperty)
            ])
        }

        // The parser reads a key path's root with allowMemberTypes: false, so `\Outer.Inner.title`
        // arrives as the root `Outer` and the components `Inner`, `title`.
        let resolvedRoot = try rootName(of: root, in: context)

        var scopeNames = [String]()
        var propertyNames = [String]()
        if resolvedRoot.isType {
            scopeNames.append(resolvedRoot.name)
        } else {
            propertyNames.append(resolvedRoot.name)
        }

        for component in keyPath.components {
            let name = try propertyName(of: component)
            guard name.first?.isUppercase == true else {
                propertyNames.append(name)
                continue
            }
            guard propertyNames.isEmpty else {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(node: Syntax(component), message: FieldIdMacroDiagnostic.typeAfterProperty(name))
                ])
            }
            scopeNames.append(name)
        }

        guard !propertyNames.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(keyPath), message: FieldIdMacroDiagnostic.namesNoProperty)
            ])
        }

        let scope = scopeNames.joined(separator: ".")
        let property = propertyNames.joined(separator: ".")

        guard let index = arguments.dropFirst().first(where: { $0.label?.text == "index" }) else {
            return "FormFieldIdentifier._property(in: \(literal: scope), named: \(literal: property))"
        }

        return "FormFieldIdentifier._property(in: \(literal: scope), named: \(literal: property), index: \(index.expression))"
    }

    private static func propertyName(of component: KeyPathComponentSyntax) throws -> String {
        switch component.component {
        case .property(let property):
            let baseName = property.declName.baseName
            if baseName.tokenKind == .keyword(.self) {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(node: Syntax(component), message: FieldIdMacroDiagnostic.noProperty)
                ])
            }
            let text = stripBackticks(baseName.text)
            if text.hasPrefix("$") {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(node: Syntax(component), message: FieldIdMacroDiagnostic.projectedComponent)
                ])
            }
            return text
        case .subscript:
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(component), message: FieldIdMacroDiagnostic.subscriptComponent)
            ])
        default:
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(component), message: FieldIdMacroDiagnostic.noProperty)
            ])
        }
    }

    private static func rootName(
        of root: TypeSyntax,
        in context: some MacroExpansionContext
    ) throws -> (name: String, isType: Bool) {
        let written = stripBackticks(root.trimmedDescription)
        guard written == "Self" else {
            return (written, written.first?.isUppercase == true)
        }

        guard let enclosing = enclosingTypeName(in: context.lexicalContext) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(root), message: FieldIdMacroDiagnostic.unresolvedSelf)
            ])
        }

        // 'Self' resolves to whatever the enclosing declaration is named, so it is a type even
        // where that name breaks the convention the rest of the walk reads.
        return (enclosing, true)
    }

    /// The whole chain of enclosing type-like declarations, outermost first, so `Self` inside
    /// `Outer.Inner` scopes to "Outer.Inner" and never collides with another `Inner`.
    private static func enclosingTypeName(in lexicalContext: [Syntax]) -> String? {
        // lexicalContext is innermost-first.
        var names = [String]()
        for syntax in lexicalContext {
            if let decl = syntax.as(ExtensionDeclSyntax.self) {
                names.append(typeName(of: decl.extendedType))
            } else if let decl = syntax.as(ProtocolDeclSyntax.self) {
                names.append(stripBackticks(decl.name.text))
            } else if let decl = syntax.as(StructDeclSyntax.self) {
                names.append(stripBackticks(decl.name.text))
            } else if let decl = syntax.as(ClassDeclSyntax.self) {
                names.append(stripBackticks(decl.name.text))
            } else if let decl = syntax.as(ActorDeclSyntax.self) {
                names.append(stripBackticks(decl.name.text))
            } else if let decl = syntax.as(EnumDeclSyntax.self) {
                names.append(stripBackticks(decl.name.text))
            }
        }

        return names.isEmpty ? nil : names.reversed().joined(separator: ".")
    }

    /// A type's written name without its generic arguments: `Box<Int>` and `Box` name one scope.
    private static func typeName(of type: TypeSyntax) -> String {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return stripBackticks(identifier.name.text)
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return typeName(of: member.baseType) + "." + stripBackticks(member.name.text)
        }
        return type.trimmedDescription
    }

    private static func stripBackticks(_ name: String) -> String {
        guard name.hasPrefix("`"), name.hasSuffix("`"), name.count > 1 else {
            return name
        }
        return String(name.dropFirst().dropLast())
    }
}
#endif
