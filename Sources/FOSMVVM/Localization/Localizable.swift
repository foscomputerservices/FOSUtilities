// Localizable.swift
//
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

import FOSFoundation
import Foundation

public typealias LocalizableId = String

/// A generalized mechanism for localizing all localizable types
///
/// The localization mechanism provided by FOS-MVVM has the following goals:
///
/// - Work on all platforms supported by Swift (e.g. iOS, macOS, Linux, Windows, ...)
/// - Work with the primitives of the Swift Foundation libraries (e.g. DateFormatter, NumberFormatter, etc.)
/// - Bind tightly and seamlessly to View-Models and Data-Models
/// - Have a file format that is easily diff-able and mergable
/// - Completely and automatically testable to ensure that no localizations are missing
/// - Have a file format that is easily understood by programmers and translators
/// - Use the swift compiler to bind between properties and localization keys
/// - Have a maintainable and scaleable file organization where it is easily understood when translations
///  are no longer needed and can be discarded
/// - Binds easily and automatically to HTML primitives (e.g. Accept-Language)
/// - Allows localization to be done automatically on the server such that all localizations are bound
///  in the View-Model before transmitting to the client application
///    - Greatly reduced footprint of the client application
///    - Typos can be fixed without deploying new updates to app
///    - New localizations can be provided without updating the app
public protocol Localizable: Codable, Hashable, Identifiable, Sendable, Stubbable {
    /// - Returns: **true** if the localized value has no output
    var isEmpty: Bool { get }

    /// The localized status of the ``Localizable``
    ///
    /// Typically localization occurs when the value is encoded via
    /// **Encodable**.
    var localizationStatus: LocalizableStatus { get }

    /// - Returns: A unique ``LocalizableId`` identifier for the ``Localizable``
    var id: LocalizableId { get }

    /// - Returns: A localized **String** version of the localizable type
    var localizedString: String { get throws }

    /// For compound types (e.g. ``LocalizableCompoundValue``), this returns
    /// each piece separately without joining. For simple types, returns a
    /// single-element array containing ``localizedString``.
    ///
    /// - Returns: An array of individually localized **String** segments
    var localizedArray: [String] { get throws }

    /// Resolves the text this value shows in *locale*
    ///
    /// The localizing encoder calls this for every ``Localizable`` it encodes. Implement it to
    /// localize a type of your own, declared in your own module, through the same encoder as
    /// the library's types:
    ///
    /// ```swift
    /// public struct LocalizableEstimate: Localizable {
    ///     public let hours: Decimal
    ///     private let text: String?
    ///
    ///     public init(hours: Decimal) {
    ///         self.hours = hours
    ///         self.text = nil
    ///     }
    ///
    ///     public func localized(in locale: Locale, store: LocalizationStore) throws -> String? {
    ///         let formatter = NumberFormatter()
    ///         formatter.locale = locale
    ///         formatter.numberStyle = .decimal
    ///         return formatter.string(for: hours)
    ///     }
    ///
    ///     public func encode(to encoder: Encoder) throws {
    ///         var container = encoder.container(keyedBy: CodingKeys.self)
    ///         try container.encode(hours, forKey: .hours)
    ///         try container.encode(text ?? encoder.localizeString(self) ?? "", forKey: .text)
    ///     }
    ///
    ///     // init(from:), isEmpty, localizationStatus, id, localizedString and stub()
    ///     // as for any Localizable
    /// }
    /// ```
    ///
    /// Encode with ``FOSMVVM/JSONEncoder/localizingEncoder(in:store:strictLocalization:)`` and
    /// the value arrives localized, exactly as a ``LocalizableDouble`` or ``LocalizableString`` does.
    /// A value that needs words from the YAML can resolve a ``LocalizableString`` the same way:
    /// `try LocalizableString.localized(case: kind).localized(in: locale, store: store)`.
    ///
    /// > Return **nil** when the store has no text for the value. A strict encoder then fails
    /// > the encode with ``LocalizerError/missingTranslation(_:locale:)``, just as it does for
    /// > the library's own types.
    ///
    /// - Parameters:
    ///   - locale: The **Locale** to localize into
    ///   - store: The ``LocalizationStore`` that holds the translations
    /// - Returns: The localized text, or **nil** when *store* cannot resolve it
    func localized(in locale: Locale, store: LocalizationStore) throws -> String?
}

public extension Localizable {
    /// Resolves the text of the library's own ``Localizable`` types
    ///
    /// ``LocalizableString``, ``LocalizableInt``, ``LocalizableDouble``, ``LocalizableDate``,
    /// ``LocalizableSubstitutions`` and ``LocalizableCompoundValue`` of ``LocalizableString``
    /// resolve here. Any other type throws ``LocalizerError/unknownLocalizationType(_:)``;
    /// implement this method on your own ``Localizable`` to localize it.
    func localized(in locale: Locale, store: LocalizationStore) throws -> String? {
        try locale.localizeLibraryValue(self, localizationStore: store)
    }
}

extension Localizable {
    func defaultedLocalizedString(defaultValue: String? = nil) -> String {
        (try? localizedString) ?? defaultValue ?? "<missing>"
    }
}

public extension Localizable {
    var localizedArray: [String] {
        get throws { try [localizedString] }
    }
}

/// The status of a ``Localizable``
///
/// A ``Localizable`` can be in one of two states.  When it is
/// first initialized, generally it is initialized with information about
/// how to localize the value, but not the fully localized value.  In
/// this case, it will be in the **localizationPending** state.
///
/// Once localization has taken place, the ``Localizable``
/// will be placed in the **localized** state.
///
/// > It is possible that values are immediately placed in the
/// > **localized** state.  This occurs when the value is
/// > a constant and no localization is needed.
public enum LocalizableStatus: Codable {
    /// The ``Localizable`` is initialized, but has not been localized
    case localizationPending

    /// The ``Localizable`` has been localized and the localized value is available
    case localized
}
