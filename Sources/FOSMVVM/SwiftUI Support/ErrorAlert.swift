// ErrorAlert.swift
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

#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Presents a localized alert whenever an error lands in the binding
    ///
    /// ```swift
    /// @State private var error: Error?
    ///
    /// var body: some View {
    ///     DocumentForm(viewModel: viewModel, error: $error)
    ///         .alert(error: $error,
    ///                title: viewModel.errorTitle,
    ///                message: viewModel.errorMessage,
    ///                dismissButtonLabel: viewModel.dismissTitle)
    /// }
    /// ```
    ///
    /// ```yaml
    /// en:
    ///   DocumentViewModel:
    ///     errorTitle: "An Error Occurred"
    ///     errorMessage: "The operation failed: %{error}"
    ///     dismissTitle: "OK"
    /// ```
    ///
    /// The alert shows while `error` is non-`nil`; dismissing it clears the binding. If
    /// `message` contains an `%{error}` substitution point, the presented error's message
    /// fills it: a ``LocalizableError`` contributes its ``LocalizableError/localizedMessage``
    /// (a ``ClientHostedLocalizableError`` is resolved against the client store first);
    /// any other error contributes its debug description. Omitting `message` presents the
    /// error's message alone.
    ///
    /// Feed one binding from every async button on the screen — this modifier is the single
    /// presentation point the buttons' `error:` parameter is designed to pair with.
    nonisolated func alert(
        error: Binding<Error?>,
        title: some Localizable,
        message: LocalizableString? = nil,
        dismissButtonLabel: some Localizable
    ) -> some View {
        modifier(ErrorAlertModifier(
            error: error,
            title: title,
            message: message ?? .constant("%{error}"),
            dismissButtonLabel: dismissButtonLabel
        ))
    }
}

private struct ErrorAlertModifier<Title: Localizable, Dismiss: Localizable>: ViewModifier {
    let error: Binding<Error?>
    let title: Title
    let message: LocalizableString
    let dismissButtonLabel: Dismiss

    @Environment(\.locale) private var locale
    @Environment(MVVMEnvironment.self) private var installedEnv: MVVMEnvironment?

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: isPresented,
            presenting: error.wrappedValue,
            actions: { _ in
                Button(dismissButtonLabel) {
                    error.wrappedValue = nil
                }
            },
            message: { presentedError in
                Text(message.bind(substitutions: [
                    "error": ErrorAlertMessage.substitutionValue(
                        for: presentedError,
                        mvvmEnv: installedEnv,
                        locale: locale
                    )
                ]))
            }
        )
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { error.wrappedValue != nil },
            set: { showing in
                if !showing {
                    error.wrappedValue = nil
                }
            }
        )
    }
}

/// Maps the presented error to the `Localizable` that fills the message's `%{error}`
/// substitution point
///
/// > Factored off the View layer so the ladder is testable.
enum ErrorAlertMessage {
    static func substitutionValue(
        for error: any Error,
        mvvmEnv: MVVMEnvironment?,
        locale: Locale
    ) -> any Localizable {
        guard let localizable = error as? any LocalizableError else {
            return LocalizableString.constant("\(error)")
        }

        guard let mvvmEnv else {
            if localizable is any ClientHostedLocalizableError {
                print("ErrorAlert: no MVVMEnvironment installed — presenting \(type(of: error))'s debug description")
                return LocalizableString.constant("\(error)")
            }
            return localizable.localizedMessage
        }

        guard let presentable = localizable.localized(mvvmEnv: mvvmEnv, locale: locale) else {
            print("ErrorAlert: unable to localize \(type(of: error)) — presenting its debug description")
            return LocalizableString.constant("\(error)")
        }

        return presentable.localizedMessage
    }
}
#endif
