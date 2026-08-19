// MissingEnvironmentDiagnostic.swift
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

// This file deliberately sits OUTSIDE `canImport(SwiftUI)`: the diagnostics are pure text, and
// keeping them portable is what lets the Linux `swift test` leg — the only leg CI actually
// executes — cover them. Everything they describe is SwiftUI-only; the messages themselves
// need not be.

/// Names the fix when a FOSMVVM view needs an object that was never installed in the
/// SwiftUI environment
///
/// When a view requires an observable from the SwiftUI environment (``MVVMEnvironment``,
/// ``Validations``), declare the `@Environment` read as optional and unwrap it through
/// ``require(_:orStop:)`` with the matching message:
///
/// ```swift
/// @Environment(MVVMEnvironment.self) private var installedEnv: MVVMEnvironment?
///
/// private var mvvmEnv: MVVMEnvironment {
///     MissingEnvironmentDiagnostic.require(
///         installedEnv,
///         orStop: MissingEnvironmentDiagnostic.missingMVVMEnvironment(
///             reader: "ViewModelView.bind()"
///         )
///     )
/// }
/// ```
///
/// A missing object then stops the app with a message that names the API the app developer
/// called and the exact `.environment(...)` installation that fixes it.
enum MissingEnvironmentDiagnostic {
    /// Writes *message* in full to stderr, then traps with it — never returns
    ///
    /// Reach for this over a bare `fatalError` whenever one of this type's messages must
    /// reach the user:
    ///
    /// ```swift
    /// guard let store = try mvvmEnv.clientLocalizationStore else {
    ///     MissingEnvironmentDiagnostic.reportAndStop(
    ///         MissingEnvironmentDiagnostic.missingLocalizationStore(
    ///             reader: "Localizable.text",
    ///             resolutionError: nil
    ///         )
    ///     )
    /// }
    /// ```
    static func reportAndStop(_ message: String) -> Never {
        // The Swift runtime folds a `fatalError` message into a single crash-report line, which
        // log viewers truncate; the stderr write is what guarantees the whole block reaches the
        // console log intact.
        FileHandle.standardError.write(Data("\n\(message)\n".utf8))
        fatalError(message)
    }

    /// Returns the installed environment object, or stops with *message* naming its fix
    ///
    /// Pair an optional `@Environment` declaration with a computed property that requires it;
    /// the view's existing reads then compile unchanged:
    ///
    /// ```swift
    /// @Environment(Validations.self) private var installedValidations: Validations?
    ///
    /// private var validations: Validations {
    ///     MissingEnvironmentDiagnostic.require(
    ///         installedValidations,
    ///         orStop: MissingEnvironmentDiagnostic.missingValidations(fieldId: fieldId.id)
    ///     )
    /// }
    /// ```
    ///
    /// SwiftUI's non-optional `@Environment(SomeObservable.self)` form stops on the same
    /// missing object with only `EXC_BREAKPOINT` and no text — never "simplify" a site back
    /// to it; the optional read routed through here is what makes the failure name its fix.
    static func require<T>(_ value: T?, orStop message: @autoclosure () -> String) -> T {
        guard let value else {
            reportAndStop(message())
        }

        return value
    }

    /// The message for a view that needed ``MVVMEnvironment`` when none is installed
    ///
    /// - Parameter reader: The public API the app developer called (`"Localizable.text"`,
    ///   `"ViewModelView.bind()"`) — never the private view type doing the read; the
    ///   developer reading the crash must recognize the name from their own code.
    static func missingMVVMEnvironment(reader: String) -> String {
        """
        ================================================================================
        FOSMVVM: MVVMEnvironment is not installed in the SwiftUI environment.

        '\(reader)' requires an MVVMEnvironment instance, but none was installed
        above it in the view hierarchy.

        To fix, install one at the application's root:

            @main struct MyApp: App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                    .environment(
                        MVVMEnvironment(
                            appBundle: Bundle.main,
                            deploymentURLs: [
                                .production: URL(string: "https://api.mywebserver.com")!,
                                .staging: URL(string: "https://staging-api.mywebserver.com")!,
                                .debug: URL(string: "http://localhost:8080")!
                            ]
                        )
                    )
                }
            }

        See the documentation for MVVMEnvironment.
        ================================================================================
        """
    }

    /// The message for a form field that wanted to display validation messages when no
    /// ``Validations`` is installed
    ///
    /// - Parameter fieldId: The affected field's ``FormFieldIdentifier/id``, so the developer
    ///   can locate the form that is missing the installation.
    static func missingValidations(fieldId: String) -> String {
        """
        ================================================================================
        FOSMVVM: Validations is not installed in the SwiftUI environment.

        The field '\(fieldId)' displays its validation messages through a Validations
        instance shared via the SwiftUI environment, but none was installed above it
        in the view hierarchy.

        To fix, install the same instance the form's validation handlers write to,
        around the form:

            @State private var validations = Validations()

            var body: some View {
                Form {
                    FormFieldView(fieldModel: viewModel.$email, focusField: $focusedField)
                }
                .environment(validations)
            }

        See the documentation for Validations and FormFieldView.
        ================================================================================
        """
    }

    /// The message for a client-side localization read that found ``MVVMEnvironment``
    /// installed but could not obtain its client localization store
    ///
    /// - Parameters:
    ///   - reader: The public API the app developer called (`"Localizable.text"`) — never
    ///     the private view type doing the read; the developer reading the crash must
    ///     recognize the name from their own code.
    ///   - resolutionError: The error thrown while resolving the store, verbatim
    ///     (`"\(error)"`); pass `nil` when the store was simply absent, which reports an
    ///     unconfigured store rather than a failure.
    static func missingLocalizationStore(reader: String, resolutionError: String?) -> String {
        let cause = resolutionError.map {
            """
            MVVMEnvironment is installed, but resolving its client localization store
            failed:

              \($0)
            """
        } ?? """
        MVVMEnvironment is installed, but it has no client localization store.
        """

        return """
        ================================================================================
        FOSMVVM: no client localization store is available.

        '\(reader)' localizes on the client, which requires the MVVMEnvironment's
        client localization store.

        \(cause)

        To fix, configure client-hosted localization when creating the MVVMEnvironment:
        pass resourceBundles: whose bundles contain the localization YAML (a
        'noResourcePaths' error means the bundles list no YAML resources), or provide
        a localizationStore: directly.

        See the documentation for MVVMEnvironment.resolveClientLocalizationStore().
        ================================================================================
        """
    }
}
