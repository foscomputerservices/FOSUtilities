// LocalizableError.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

/// Give an error a localized, user-presentable message — compose it like a ViewModel, and
/// the `alert(error:title:message:dismissButtonLabel:)` View modifier presents it in the
/// user's language
///
/// ## Example
///
/// Declare the message with the same `@Localized…` vocabulary a ViewModel uses; the
/// `@LocalizableError` macro provides the localization plumbing:
///
/// ```swift
/// @LocalizableError
/// public struct DocumentSaveError: ServerRequestError {
///     @LocalizedString public var errorMessage
///
///     public var localizedMessage: any Localizable { errorMessage }
///
///     public init() {}
/// }
/// ```
///
/// ```yaml
/// en:
///   DocumentSaveError:
///     errorMessage: "The document could not be saved"
/// ```
///
/// A message that carries the error's own values uses `@LocalizedSubs`, again exactly as a
/// ViewModel would:
///
/// ```swift
/// @LocalizableError
/// public struct QuotaError: ServerRequestError {
///     public let requested: Int
///     public let maximum: Int
///
///     @LocalizedSubs(substitutions: \.subs) public var errorMessage
///
///     public var localizedMessage: any Localizable { errorMessage }
///
///     private var subs: [String: any Localizable] { [
///         "requested": LocalizableInt(value: requested),
///         "maximum": LocalizableInt(value: maximum)
///     ] }
///
///     public init(requested: Int, maximum: Int) {
///         self.requested = requested
///         self.maximum = maximum
///     }
/// }
/// ```
///
/// Localization happens exactly as it does for a ViewModel — during the localizing
/// encode. The server throws the error, `ErrorMiddleware` encodes it (resolving every
/// `@Localized…` property in the request's locale), and the client decodes a message that
/// is *already localized* — which is what ``localizedMessage``'s name promises.
///
/// An error type belongs to exactly **one** localization domain: its YAML lives where the
/// error is thrown. A server-domain error arrives resolved as above. A **client-domain**
/// error — created in an app that hosts its own localization YAML — declares itself with
/// `@LocalizableError(options: [.clientHosted])` and is resolved at presentation (see
/// ``ClientHostedLocalizableError``). The same type never straddles domains — an error
/// reaching presentation unresolved surfaces as its debug description, the symptom of a
/// domain violation.
///
/// Errors that do not conform are presented with their debug description — conforming is
/// what turns an error from developer output into user-facing copy.
public protocol LocalizableError: Error, RetrievablePropertyNames {
    /// The error's user-facing message — named for the expectation that by the time
    /// anyone reads it, localization has already happened (the localizing encode
    /// resolved it, as with every ViewModel property)
    var localizedMessage: any Localizable { get }
}

/// A ``LocalizableError`` created — and therefore localized — on the client
///
/// Declared via the macro flag, never by hand:
///
/// ```swift
/// @LocalizableError(options: [.clientHosted])
/// public struct ImportInterruptedError {
///     @LocalizedString public var errorMessage
///
///     public var localizedMessage: any Localizable { errorMessage }
///
///     public init() {}
/// }
/// ```
///
/// A client-created error never rides the server's localizing encode, so presentation
/// localizes it instead: ``LocalizableError/localized(mvvmEnv:locale:)`` runs the same
/// round-trip a `ClientHostedViewModelFactory` runs for a ViewModel, against the app's
/// own localization YAML (`MVVMEnvironment.resourceBundles`). The
/// `alert(error:title:message:dismissButtonLabel:)` modifier does this automatically.
public protocol ClientHostedLocalizableError: LocalizableError {}

public extension LocalizableError {
    /// A copy of the error with its `@Localized…` properties resolved for the locale —
    /// the client-domain twin of the wire's `ErrorMiddleware` encode
    ///
    /// ```swift
    /// let localized = try error.localized(locale: locale, localizationStore: store)
    /// Text(localized.localizedMessage)
    /// ```
    ///
    /// This is the same localizing round-trip a `ClientHostedViewModelFactory` performs
    /// for a ViewModel. Presentation code usually wants
    /// ``localized(mvvmEnv:locale:)`` instead, which selects the store and degrades
    /// gracefully.
    func localized(locale: Locale, localizationStore: LocalizationStore) throws -> Self {
        try toJSON(encoder: .localizingEncoder(
            locale: locale,
            localizationStore: localizationStore
        ))
        .fromJSON()
    }

    /// The error, ready to present — client-hosted errors are resolved against the
    /// client's localization store; everything else (wire-localized already) passes
    /// through unchanged
    ///
    /// ```swift
    /// guard let presentable = error.localized(mvvmEnv: mvvmEnv, locale: locale) else {
    ///     // present error's debug description instead
    /// }
    /// Text(presentable.localizedMessage)
    /// ```
    ///
    /// Returns `nil` when a ``ClientHostedLocalizableError`` cannot be resolved (no
    /// client localization store, or its keys are absent) — a message you can read is
    /// only ever the localized one, so present the error's debug description in that
    /// case.
    func localized(mvvmEnv: MVVMEnvironment, locale: Locale) -> Self? {
        guard self is any ClientHostedLocalizableError else {
            return self
        }
        guard let store = (try? mvvmEnv.clientLocalizationStore) ?? nil else {
            print("LocalizableError: \(type(of: self)) is clientHosted but no client localization store is configured — see MVVMEnvironment.resourceBundles")
            return nil
        }

        return try? localized(locale: locale, localizationStore: store)
    }
}
