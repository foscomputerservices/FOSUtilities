// ValidationError.swift
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

public struct ValidationError: Error, CustomStringConvertible, CustomDebugStringConvertible, Codable, Sendable {
    public let validations: [ValidationResult]

    // MARK: CustomStringConvertible Protocol

    public var description: String {
        "ValidationError: \(validations)"
    }

    // MARK: CustomDebugStringConvertible Protocol

    public var debugDescription: String {
        description
    }

    // MARK: Initialization Methods

    public init(validations: [ValidationResult]) {
        self.validations = validations
    }

    public init(validation: ValidationResult) {
        self.validations = [validation]
    }

    public init(validations: Validations) {
        self.validations = validations.validations
    }
}
