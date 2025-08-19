// ValidationResult.swift
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

public struct ValidationResult: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Status: Int, CaseIterable, Codable, Comparable, Hashable, Sendable {
        /// The validation checks provided some information about the response
        ///
        /// > The validated value is considered acceptable.
        case info = 1

        /// The validation checks passed, but provided some suggestions
        ///
        /// > The validated value is considered acceptable, but the user is
        /// > cautioned to consider the value is acceptable.
        case warning = 2

        /// The validation checks failed
        ///
        /// > The validated value is considered unacceptable.
        case error = 3

        /// Returns **true** if ``Status`` is an error
        public var hasError: Bool {
            self == .error
        }

        // MARK: Comparable Protocol

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Correlation information that enables the user interface to present information to the
    /// user to help them to resolve any issues with the data
    public struct Message: Codable, Hashable, Sendable {
        /// The *fieldIds* indicate the field(s) involved in the issue
        ///
        /// > There may be multiple *fieldIds* present if there is an issue where fields conflict
        /// > in their data.
        public let fieldIds: [FormFieldIdentifier]

        /// A message that may be displayed to the user that describe any issues encountered
        /// with the data
        public let message: LocalizableString

        public init(fieldIds: [FormFieldIdentifier], message: LocalizableString) {
            self.fieldIds = fieldIds
            self.message = message
        }
    }

    /// The status of the validation of the involved fields
    public let status: Status

    /// Messages that may be presented to the user to help them to resolve any issues with the data
    public private(set) var messages: [Message]

    public func messages(for fieldId: FormFieldIdentifier) -> [Message]? {
        let result = messages.filter { $0.fieldIds.contains(fieldId) }
        return result.isEmpty ? nil : result
    }

    mutating func removeMessages(for fieldId: FormFieldIdentifier) {
        messages = messages.filter { !$0.fieldIds.contains(fieldId) }
    }

    public var isValid: Bool {
        !status.hasError
    }

    public var hasError: Bool {
        status.hasError
    }

    // MARK: CustomStringConvertible Protocol

    public var description: String {
        "ValidationResult(\(status), \(messages))"
    }

    // MARK: CustomDebugStringConvertible Protocol

    public var debugDescription: String {
        description
    }

    public init(status: Status, fieldId: FormFieldIdentifier, message: LocalizableString) {
        self.init(status: status, fieldIds: [fieldId], message: message)
    }

    public init(status: Status, field: FormField<some Any>, message: LocalizableString) {
        self.init(status: status, fieldIds: [field.fieldId], message: message)
    }

    public init(status: Status, fieldIds: [FormFieldIdentifier], message: LocalizableString) {
        self.init(status: status, messages: [.init(fieldIds: fieldIds, message: message)])
    }

    public init(status: Status, messages: [Message]) {
        self.status = status
        self.messages = messages
    }
}

public extension Collection<ValidationResult> {
    /// Returns **true** if none of the ``ValidationResult`` models is reporting an error
    ///
    /// > This only checks for ``hasError``.  Manual checks are required to determine if
    /// > any of the elements have any other state (e.g., info or warning).
    var isValid: Bool {
        !hasError
    }

    /// Returns **true** if any of the ``ValidationResult`` models is reporting an error
    var hasError: Bool {
        aggregate?.hasError ?? false
    }

    /// Combines a collection of Status elements into a single element
    ///
    /// > The absence of any ``ValidationResult`` models indicates no issues.
    ///
    /// - Returns: The most severe Status element of the given collection; nil => no issues
    var aggregate: ValidationResult.Status? {
        guard !isEmpty else {
            return nil
        }

        return map(\.status).reduce(into: .info) { result, status in
            result = Swift.max(result, status)
        }
    }
}
