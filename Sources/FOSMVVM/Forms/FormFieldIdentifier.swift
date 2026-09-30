// FormFieldIdentifier.swift
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

/// An identifier that uniquely identifies a field in a form
///
/// Mint one with ``fieldId(_:)`` over the property it identifies:
///
/// ```swift
/// static var emailField: FormField<String?> { .init(
///     fieldId: #fieldId(\Self.email),
///     title: .localized(for: Self.self, parentKeys: "email", propertyName: "title"),
///     placeholder: .localized(for: Self.self, parentKeys: "email", propertyName: "placeholder"),
///     type: .text(inputType: .emailAddress),
///     options: []
/// )}
/// ```
///
/// > ``fieldId(_:)`` is the only mint, and the value it answers is opaque — nothing to read,
/// > compose or parse. Two identifiers minted from the same property of the same type — and the
/// > same index, for a repeated field — are equal, and the value round-trips through `Codable`.
public struct FormFieldIdentifier: Hashable, Codable, Sendable {
    let id: String

    /// What ``fieldId(_:)`` expands to; write the macro instead
    ///
    /// ```swift
    /// fieldId: #fieldId(\CardFields.title)
    /// ```
    @_documentation(visibility: internal)
    public static func _property(in scope: String, named name: String, index: Int? = nil) -> FormFieldIdentifier {
        // No initializer is declared on the type: the synthesized memberwise one is internal, so
        // #fieldId is the wall rather than a convention, and this is how the macro reaches it from
        // the consumer's module. The composition below is the identifier's representation: pinned
        // by FieldIdMacroTests, never stated on a customer-visible surface.
        let property = "\(scope).\(name)"
        return .init(id: index.map { "\(property)[\($0)]" } ?? property)
    }
}

public extension [FormFieldIdentifier] {
    func contains(_ field: FormField<some Any>) -> Bool {
        contains(where: { $0.id == field.fieldId.id })
    }
}
