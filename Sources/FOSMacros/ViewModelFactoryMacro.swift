// ViewModelFactoryMacro.swift
//
// Created by David Hunt on 12/11/24
// Copyright 2024 FOS Services, LLC
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
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum MacroError: Error {
    case invalidVersionFormat(String)
}

public struct ViewModelFactoryMacro: MemberMacro {
    // MARK: MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard node.attributeName.description == "VersionedFactory" else {
            return []
        }

        // Example:
        // @Version(.v1_0_0)
        // static func model_v1_0_0(_ req: Vapor.Request, vmRequest: Request) async throws -> Self

        // Extract the version number from the attribute and the corresponding function name
        let versionedModelFuncs = try declaration.memberBlock.members.compactMap { member throws -> (version: SystemVersion, method: String)? in
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
                throw MacroError.invalidVersionFormat("The @Version macro requires version names to be in the form of '.vX.Y.Z'")
            }

            return (version: version, method: funcDecl.name.text)
        }
        .sorted { $0.version > $1.version }
        .map { tuple in
            """
            if version >= \(tuple.version.initFuncCall) {
                return try await \(tuple.method)(req, vmRequest: vmRequest)
            }
            """
        }
        .joined(separator: "\n")

        return ["""
        public static func model(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
            let version = try req.systemVersion

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

        self.init(version)
    }

    var initFuncCall: String {
        "SystemVersion(major: \(major), minor: \(minor), patch: \(patch))"
    }
}
