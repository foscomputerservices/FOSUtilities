// RetrievablePropertyNames.swift
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

/// Binds ``LocalizableId`` values to their property names
///
/// This protocol is used by ``LocalizedString`` to bind a ``LocalizableId`` to
/// its related property name to enable looking up of property names in the Yaml dictionaries.
///
/// Generally it is not necessary to implement conformance to this protocol as the
/// @ViewModel and @FieldValidationModel macros automatically provide this
/// conformance.
public protocol RetrievablePropertyNames: Codable, Sendable {
    /// The bindings of all of the conformer's LocalizableString properties
    func propertyNames() -> [LocalizableId: String]
}
