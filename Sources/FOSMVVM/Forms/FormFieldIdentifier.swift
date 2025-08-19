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
/// Typically a simple field name is sufficient for initializing this value.
///
/// ## Example
///
/// ```swift
/// static var emailField: FormField<String?> { .init(
///     fieldId: .init(id: "email"),
///     title: .localized(for: Self.self, parentKeys: "email", propertyName: "title"),
///     placeholder: .localized(for: Self.self, parentKeys: "email", propertyName: "placeholder"),
///     type: .text(inputType: .emailAddress),
///     options: []
/// )}
/// ```
public struct FormFieldIdentifier: Hashable, Codable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public extension [FormFieldIdentifier] {
    func contains(_ id: String) -> Bool {
        contains(where: { $0.id == id })
    }

    func contains(_ field: FormField<some Any>) -> Bool {
        contains(where: { $0.id == field.fieldId.id })
    }
}
