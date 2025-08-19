// FormInputOption.swift
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

public enum FormInputOption<Value>: Codable, Sendable where Value: Codable & Hashable {
    /// The default field size, in characters, for a date field
    ///
    /// > This value is used if no ``size(value:)`` is specified for a date field
    public static var defaultDateSize: Int { 25 }

    /// The default field size, in characters, for date-time field
    ///
    /// > This value is used if no ``size(value:)`` is specified for a date-time field
    public static var defaultDateTimeSize: Int { 30 }

    /// The availability of the field
    case disabled(value: Bool)

    /// For the user to enter a value
    case required(value: Bool)

    /// The number of characters to show in a text field
    case size(value: Int)

    /// The input's autocomplete value
    case autocomplete(value: Autocomplete)

    /// The input's autocapitalize value
    case autocapitalize(value: Autocapitalize)

    /// The number of columns for a text area field
    case cols(value: Int)

    /// The minimum value for a number field
    case minValue(value: Int)

    /// The maximum value for a number field
    case maxValue(value: Int)

    /// The minimum number of characters allowed in a text field
    case minLength(value: Int)

    /// The maximum number of characters allowed in a text field
    case maxLength(value: Int)

    /// Generates ``minLength(value:)`` and ``maxLength(value:)`` from
    /// the given range
    ///
    /// - Parameter range: The lower and upper bounds of the length
    public static func rangeLength(_ range: ClosedRange<Int>) -> [Self] { [
        .minLength(value: range.lowerBound),
        .maxLength(value: range.upperBound)
    ] }

    /// The minimum value for a date field
    case minDate(date: Date)

    /// The maximum value for a date field
    case maxDate(date: Date)
}

public extension FormInputOption {
    enum Autocapitalize: String, Codable, CaseIterable, Sendable {
        case characters
        case sentences
        case words
        case never
    }

    /// The input's autocomplete  value
    ///
    /// - See also: https://developer.mozilla.org/en-US/docs/Web/HTML/Attributes/autocomplete
    enum Autocomplete: String, Codable, CaseIterable, Sendable {
        case off
        case on
        case name
        case honorificPrefix = "honorific-prefix"
        case givenName = "given-name"
        case additionalName = "additional-name"
        case familyName = "family-name"
        case honorificSuffix = "honorific-suffix"
        case nickname
        case email
        case username
        case newPassword = "new-password"
        case currentPassword = "current-password"
        case oneTimeCode = "one-time-code"
        case organizationTitle = "organization-title"
        case organization
        case streetAddress = "street-address"
        case addressLine1 = "address-line-1"
        case addressLine2 = "address-line-2"
        case addressLine3 = "address-line-3"
        case addressLevel1 = "address-level-1"
        case addressLevel2 = "address-level-2"
        case addressLevel3 = "address-level-3"
        case addressLevel4 = "address-level-4"
        case country
        case country_name = "country-name"
        case postal_code = "postal-code"
        case ccName = "cc-name"
        case ccGivenName = "cc-given-name"
        case ccFamilyName = "cc-family-name"
        case ccNumber = "cc-number"
        case ccExp = "cc-exp"
        case ccExpMonth = "cc-exp-month"
        case ccExpYear = "cc-exp-year"
        case ccCSC = "cc-csc"
        case ccType = "cc-type"
        case transactionCurrency = "transaction-currency"
        case transactionAmount = "transaction-amount"
        case language
        case birthDay = "bday"
        case birthDayDay = "bday-day"
        case birthDayMonth = "bday-month"
        case birthDayYear = "bday-year"
        case sex
        case telephone = "tel"
        case telephoneCountryCode = "tel-country-code"
        case telephoneNational = "tel-national"
        case telephoneAreaCode = "tel-area-code"
        case telephoneLocal = "tel-local"
        case telephoneExtension = "tel-extension"
        case instantMessagingProtocolEndpoint = "impp"
        case url
        case photo
    }
}

#if canImport(SwiftUI) && !os(macOS)
import SwiftUI

public extension FormInputOption<String>.Autocapitalize {
    var textAutocapitalizationType: TextInputAutocapitalization {
        switch self {
        case .characters: .characters
        case .sentences: .sentences
        case .words: .words
        case .never: .never
        }
    }
}

public extension FormInputOption<String?>.Autocapitalize {
    var textAutocapitalizationType: TextInputAutocapitalization {
        switch self {
        case .characters: .characters
        case .sentences: .sentences
        case .words: .words
        case .never: .never
        }
    }
}
#endif
