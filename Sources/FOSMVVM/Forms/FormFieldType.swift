// FormFieldType.swift
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

import Foundation

/// Describes the type of the each form's field
public enum FormFieldType: Codable, Sendable {
    /// A simple text field
    case text(inputType: FormInputType)

    /// A text area field (multiple lines of text)
    case textArea(inputType: FormInputType)

    /// A checkbox field
    case checkbox

    /// A color picker field
    case colorPicker

    /// A drop-down style field allowing the user to select a single option from a list
    case select
}
