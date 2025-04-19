// ViewModelFactoryMacro.swift
//
// Created by David Hunt on 12/21/24
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

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum ViewModelFactoryMacroError: Error, CustomDebugStringConvertible {
    case invalidVersionFormat(String)

    public var debugDescription: String {
        switch self {
        case .invalidVersionFormat(let value):
            "ViewModelFactoryMacroError: Invalid version format: \(value)"
        }
    }
}

public struct ViewModelFactoryMacro: MemberMacro {
    // MARK: MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard node.attributeName.description.trimmingCharacters(in: .whitespaces) == "VersionedFactory" else {
            return []
        }

        var typeAliasType: String?

        // Example:
        // @Version(.v1_0_0)
        // static func model_v1_0_0(context: Context) async throws -> Self

        // Extract the version number from the attribute and the corresponding function name
        let versionedModelFuncs = try declaration.memberBlock.members.compactMap { member throws -> (version: SystemVersion, method: String)? in

            // Capture the typealias, if we can; if not, we'll use 'Context'
            if let typeAliasDecl = member.decl.as(TypeAliasDeclSyntax.self) {
                if typeAliasType == nil {
                    typeAliasType = typeAliasDecl.initializer.value.description
                } else {
                    // There's more than one and we don't know which is correct
                    typeAliasType = nil
                }
            }

            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else {
                return nil
            }
            let attrs = funcDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }
            guard let versionAttr = attrs.filter({ $0.attributeName.description == "Version" }).first else {
                return nil
            }
            guard
                let versionArgument = versionAttr.arguments?.description.trimmingCharacters(in: .whitespacesAndNewlines),
                !versionArgument.isEmpty,
                versionArgument.starts(with: ".v"),
                let version = SystemVersion(rawVersion: versionArgument)
            else {
                throw ViewModelFactoryMacroError.invalidVersionFormat(
                    "The @Version macro requires version names to be in the form of '.vX.Y.Z'"
                )
            }

            return (version: version, method: funcDecl.name.text)
        }
        .sorted { $0.version > $1.version }
        .map { tuple in
            """
            if version >= \(tuple.version.initFuncCall) {
                return try await \(tuple.method)(context: context)
            }
            """
        }
        .joined(separator: "\n")

        return ["""
        public static func model(context: \(raw: typeAliasType ?? "Context")) async throws -> Self {
            let version = try context.systemVersion

            \(raw: versionedModelFuncs)

            throw ViewModelFactoryError.versionNotSupported(version.versionString)
        }
        """]
    }
}

private extension SystemVersion {
    init?(rawVersion version: String) {
        guard version.starts(with: ".v") else {
            return nil
        }

        let version = version
            .replacingOccurrences(of: "-", with: ".")
            .replacingOccurrences(of: "_", with: ".")
            .trimmingPrefix(".v")

        self.init(String(version))
    }

    var initFuncCall: String {
        "SystemVersion(major: \(major), minor: \(minor), patch: \(patch))"
    }
}
