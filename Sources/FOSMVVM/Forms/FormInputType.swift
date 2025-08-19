// FormInputType.swift
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

/// Form input types
///
/// > The intention of this set of values is to be exhaustive.  Not all values will map to
/// > SwiftUI controls.
///
/// - See also: https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
public enum FormInputType: String, Codable, Sendable {
    case button
    case checkbox
    case color
    case date
    case datetimeLocal = "datetime-local"
    case emailAddress = "email"
    case file
    case hidden
    case image
    case month
    case number
    case password
    case radio
    case range
    case reset
    case search
    case submit
    case tel
    case text
    case time
    case url
    case week

    // Apple values
    case name
    case namePrefix
    case givenName
    case middleName
    case familyName
    case nameSuffix
    case nickname
    case jobTitle
    case organizationName
    case location
    case fullStreetAddress
    case streetAddressLine1
    case streetAddressLine2
    case addressCity
    case addressState
    case addressCityAndState
    case subLocality
    case countryName
    case postalCode
    case telephoneNumber
    case creditCardNumber
    case userName
    case newPassword
    case oneTimeCode
}

#if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
import UIKit

extension FormInputType {
    var textContentType: UITextContentType? {
        switch self {
        case .button: nil
        case .checkbox: nil
        case .color: nil
        case .date: nil
        case .datetimeLocal: nil
        case .emailAddress: .emailAddress
        case .file: nil
        case .hidden: nil
        case .image: nil
        case .month: nil
        case .number: nil
        case .password: .password
        case .radio: nil
        case .range: nil
        case .reset: nil
        case .search: nil
        case .submit: nil
        case .tel: .telephoneNumber
        case .text: nil
        case .time: nil
        case .url: .URL
        case .week: nil
        // Apple extras
        case .name: .name
        case .namePrefix: .namePrefix
        case .givenName: .givenName
        case .middleName: .middleName
        case .familyName: .familyName
        case .nameSuffix: .nameSuffix
        case .nickname: .nickname
        case .jobTitle: .jobTitle
        case .organizationName: .organizationName
        case .location: .location
        case .fullStreetAddress: .fullStreetAddress
        case .streetAddressLine1: .streetAddressLine1
        case .streetAddressLine2: .streetAddressLine2
        case .addressCity: .addressCity
        case .addressState: .addressState
        case .addressCityAndState: .addressCityAndState
        case .subLocality: .sublocality
        case .countryName: .countryName
        case .postalCode: .postalCode
        case .telephoneNumber: .telephoneNumber
        case .creditCardNumber: .creditCardNumber
        case .userName: .username
        case .newPassword: .newPassword
        case .oneTimeCode: .oneTimeCode
        }
    }
}
#endif

#if os(watchOS)
import WatchKit

extension FormInputType {
    var textContentType: WKTextContentType? {
        switch self {
        case .button: nil
        case .checkbox: nil
        case .color: nil
        case .date: nil
        case .datetimeLocal: nil
        case .emailAddress: .emailAddress
        case .file: nil
        case .hidden: nil
        case .image: nil
        case .month: nil
        case .number: nil
        case .password: .password
        case .radio: nil
        case .range: nil
        case .reset: nil
        case .search: nil
        case .submit: nil
        case .tel: .telephoneNumber
        case .text: nil
        case .time: nil
        case .url: .URL
        case .week: nil
        // Apple extras
        case .name: .name
        case .namePrefix: .namePrefix
        case .givenName: .givenName
        case .middleName: .middleName
        case .familyName: .familyName
        case .nameSuffix: .nameSuffix
        case .nickname: .nickname
        case .jobTitle: .jobTitle
        case .organizationName: .organizationName
        case .location: .location
        case .fullStreetAddress: .fullStreetAddress
        case .streetAddressLine1: .streetAddressLine1
        case .streetAddressLine2: .streetAddressLine2
        case .addressCity: .addressCity
        case .addressState: .addressState
        case .addressCityAndState: .addressCityAndState
        case .subLocality: .sublocality
        case .countryName: .countryName
        case .postalCode: .postalCode
        case .telephoneNumber: .telephoneNumber
        case .creditCardNumber: .creditCardNumber
        case .userName: .username
        case .newPassword: .newPassword
        case .oneTimeCode: .oneTimeCode
        }
    }
}
#endif
