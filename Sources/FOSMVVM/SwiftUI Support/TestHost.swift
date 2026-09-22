// TestHost.swift
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

import FOSFoundation
import Foundation

#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Returns the view wrapped so that it can be tested with *ViewModelViewTestCase*
    ///
    /// The *decorator* *ViewBuilder* allows the hosting application to attach additional information to the
    /// view under test.  For example, this could be environment bindings that are substituted to allow the
    /// view under test to bind to test bindings.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///
    ///    var body: some Scene {
    ///      WindowGroup {
    ///        MyMainView { ... }
    ///        #if DEBUG
    ///        .testHost { testConfiguration, testView in
    ///          switch testConfiguration {
    ///             case "ProvideBinding":
    ///                 testView
    ///                     .environment(\.binding, testValue)
    ///             default:
    ///                 testView
    ///        }
    ///        #endif
    ///      }
    ///    }
    /// }
    /// ```
    ///
    /// Every view to be tested individually must be registered from the application's `init()`
    /// with ``MVVMEnvironment/registerTestView(_:designedFor:)``; this function resolves the view under test
    /// before the first render, and stops with a diagnostic if it is not registered by then.
    ///
    /// On iOS the wrapper also plants the invisible control that
    /// `XCUIApplication.dismissKeyboard()` (**FOSTestingUI**) taps to put the software keyboard
    /// away — nothing to configure, and nothing ships in release builds.
    ///
    /// - Parameters:
    ///   - decorator: A *ViewBuilder* that can be used to attach additional test-only information to the view under test
    @MainActor @ViewBuilder func testHost(@ViewBuilder decorator: (String, AnyView) -> some View) -> some View {
        #if DEBUG
        decorator(
            ProcessInfo.processInfo.testConfiguration,
            AnyView(
                TestingView(baseView: self)
            )
        )
        #else
        self
        #endif
    }

    /// Returns the view wrapped so that it can be tested with *ViewModelViewTestCase*
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///
    ///    var body: some Scene {
    ///      WindowGroup {
    ///        MyMainView { ... }
    ///        #if DEBUG
    ///        .testHost()
    ///        #endif
    ///      }
    ///    }
    ///
    ///    init() {
    ///      MVVMEnvironment.registerTestingViews()
    ///    }
    /// }
    ///
    /// private extension MVVMEnvironment {
    ///    @MainActor static func registerTestingViews() {
    ///      #if DEBUG
    ///      registerTestView(MyMainView.self)
    ///      #endif
    ///    }
    /// }
    /// ```
    ///
    /// Every view to be tested individually must be registered from the application's `init()`
    /// with ``MVVMEnvironment/registerTestView(_:designedFor:)``; this function resolves the view under test
    /// before the first render, and stops with a diagnostic if it is not registered by then.
    @MainActor func testHost() -> some View {
        testHost(decorator: { _, view in view })
    }
}

#if DEBUG
public extension URL {
    static let testHostRequest = "test-view-request"
}

private extension ProcessInfo {
    var viewModelType: String? {
        environment["__FOS_ViewModelType"]
    }

    var testConfiguration: String {
        environment["__FOS_TestConfiguration"] ?? ""
    }

    var viewModelData: Data? {
        guard
            let aStr = environment["__FOS_ViewModel"],
            let str = aStr.reveal
        else {
            return nil
        }

        return str.data(using: .utf8)
    }

    @MainActor func view(
        registeredTypes: [String: MVVMEnvironment.TestViewRegistration]
    ) -> (view: AnyView, designedFor: ProductionParents)? {
        guard
            let vmTypeStr = viewModelType,
            let viewModelData
        else {
            return nil
        }

        guard let registration = registeredTypes[vmTypeStr] else {
            TestHostDiagnostic.reportAndStop(
                TestHostDiagnostic.unregisteredView(
                    viewModelType: vmTypeStr,
                    registered: registeredTypes.keys.sorted()
                )
            )
        }

        do {
            let view = try registration.factory(viewModelData)

            // The registration declares the view's designed parents; the harness supplies
            // what production would, innermost first. Navigation is the OUTER parent and
            // scrolling the inner one — production nests NavigationStack { ScrollView { … } },
            // and a bar inside a scroll view would scroll away with the content.
            let scrolled = registration.designedFor.contains(.scrolling)
                ? AnyView(ScrollView(.vertical) { view })
                : view
            let presented = registration.designedFor.contains(.navigation)
                ? AnyView(NavigationStack { scrolled })
                : scrolled

            return (presented, registration.designedFor)
        } catch {
            TestHostDiagnostic.reportAndStop(
                TestHostDiagnostic.undecodableViewModel(
                    viewModelType: vmTypeStr,
                    error: error
                )
            )
        }
    }
}
#endif

extension ViewModelView {
    static var vmTypeStr: String {
        String(describing: type(of: self))
    }
}

#if DEBUG
@MainActor
private struct TestingView<BaseView: View>: View {
    private let testView: AnyView
    private let resolvedParents: ProductionParents?

    var body: some View {
        ZStack {
            testView

            // Fronting the host, 1x1, hit-testing refused: TestDataTransporter's shape, for
            // TestDataTransporter's reason — a zero-sized element behind opaque content
            // inside a ScrollView is culled from the accessibility tree and its value
            // becomes unreadable, which is exactly when a diagnostic is most needed.
            if let resolvedParents {
                Text(verbatim: "")
                    .accessibilityIdentifier(TestHostFacts.accessibilityIdentifier)
                    .accessibilityValue(TestHostFacts.value(for: resolvedParents))
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(false)
            }
        }
        #if os(iOS)
        .onAppear {
            DismissKeyboardWindow.install()
        }
        #endif
    }

    init(baseView: BaseView) {
        let resolved = ProcessInfo.processInfo.view(
            registeredTypes: MVVMEnvironment.registeredTestTypes
        )
        self.testView = resolved?.view ?? AnyView(baseView)
        // Only a view the harness actually resolved has declared parents to report. The
        // application's own tree — the probe's case, and any app launched without the
        // __FOS_ environment — plants nothing, so an absent element means "not under test"
        // rather than "declared nothing", and the reader is told nothing rather than
        // something wrong.
        self.resolvedParents = resolved?.designedFor
    }
}

#if os(iOS)
/// The tap target for XCUIApplication.dismissKeyboard() (FOSTestingUI). XCUITest has no API to
/// put the software keyboard away, and a .numberPad keyboard offers no Return key to tap, so
/// the test process's only route is something tappable that resigns first responder.
///
/// The control lives in its own tiny window above the application's, not in the view tree:
/// when the focused field would be covered and no scroll container absorbs it, keyboard
/// avoidance shifts the application's whole content upward, and no modifier opts a child out
/// of an ancestor's offset — a top-leading overlay was measured riding that shift to y = -48,
/// off screen. A separate window sits outside the application's layout entirely, so nothing
/// the content does can displace or cover it. The window is only up while the keyboard is, so
/// with the keyboard down its corner belongs to the application.
@MainActor
private enum DismissKeyboardWindow {
    private static var window: UIWindow?
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        let center = NotificationCenter.default
        center.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { show() } }
        center.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { hide() } }
    }

    private static func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.isHidden = false
    }

    private static func hide() {
        window?.isHidden = true
    }

    /// How much of the top of the screen the system has spoken for. One window's
    /// safeAreaInsets is not the answer: on the iPhone Duo's cover screen the scene's FIRST
    /// window reports a top inset of 0 while the status bar is 24pt tall, which put the
    /// control inside the status-bar strip, where a synthesized tap is taken as a status-bar
    /// gesture and never reaches the button. Measured 2026-09-22: the control landed at y 0
    /// on the Duo and y 62 on an iPhone 17 Pro, and dismissKeyboard() failed on the Duo only.
    /// Asking every window and the status-bar manager, and taking the largest, puts the
    /// control below everything the scene reserves rather than below one window's idea of it.
    private static func topReservedInset(in scene: UIWindowScene) -> CGFloat {
        let statusBar = scene.statusBarManager?.statusBarFrame.height ?? 0
        let insets = scene.windows.map(\.safeAreaInsets.top).max() ?? 0

        return max(statusBar, insets)
    }

    private static func makeWindow() -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return nil // Retried on the next keyboardWillShow
        }

        let window = UIWindow(windowScene: scene)
        // Below every region the scene reserves at the top, so a synthesized tap cannot be
        // read as a status-bar gesture; the top of the screen is the one place a keyboard can
        // never reach.
        let topInset = Self.topReservedInset(in: scene)
        window.frame = CGRect(x: 0, y: topInset, width: 24, height: 24)
        window.windowLevel = .alert + 1

        let controller = UIViewController()
        controller.view.backgroundColor = .clear

        let button = UIButton(type: .custom)
        button.frame = controller.view.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.backgroundColor = .clear
        // Mirrors the literal in FOSTestingUI's XCUIApplication.dismissKeyboard(); the two
        // modules share no target, so the name is tethered by comment, as the __FOS_ launch
        // environment keys are.
        button.accessibilityIdentifier = "__FOS_DismissKeyboard"
        button.addAction(
            UIAction { _ in
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            },
            for: .touchUpInside
        )
        controller.view.addSubview(button)

        window.rootViewController = controller
        return window
    }
}
#endif
#endif
#endif

// This block deliberately sits OUTSIDE `canImport(SwiftUI)`: the diagnostics are pure text, and
// keeping them portable is what lets the Linux `swift test` leg — the only leg CI actually
// executes — cover them. Everything they describe is SwiftUI-only; the messages themselves
// need not be.

/// Names the fix when `testHost()` cannot present the view under test because the consumer
/// app is misconfigured
///
/// When a `testHost()` resolution step hits a dead end the consumer must repair (a view that
/// was never registered, a payload its ViewModel cannot decode), stop through the matching
/// message rather than a bare `fatalError`:
///
/// ```swift
/// guard let registration = registeredTypes[vmTypeStr] else {
///     TestHostDiagnostic.reportAndStop(
///         TestHostDiagnostic.unregisteredView(
///             viewModelType: vmTypeStr,
///             registered: registeredTypes.keys.sorted()
///         )
///     )
/// }
/// ```
///
/// The run then stops with a message that names the misconfiguration and the exact
/// registration that fixes it.
enum TestHostDiagnostic {
    /// Writes *message* in full to stderr, then traps with it — never returns
    ///
    /// Reach for this over a bare `fatalError` whenever one of this type's messages must
    /// reach the `xcodebuild` test log (see the type's example).
    static func reportAndStop(_ message: String) -> Never {
        // The Swift runtime folds a `fatalError` message into a single crash-report line, which
        // log viewers truncate; the stderr write is what guarantees the whole block reaches an
        // `xcodebuild` test log intact.
        FileHandle.standardError.write(Data("\n\(message)\n".utf8))
        fatalError(message)
    }

    /// The message for a `testHost()` presentation whose view under test was never registered
    ///
    /// - Parameters:
    ///   - viewModelType: The ViewModel type name the test harness asked for, so the developer
    ///     reading the log can match it to their test.
    ///   - registered: Every currently registered ViewModel type name; listed in the message so
    ///     the developer can spot a near-miss registration.
    static func unregisteredView(viewModelType: String, registered: [String]) -> String {
        let registeredList = registered.isEmpty
            ? "  (none — no test views have been registered)"
            : registered.map { "  - \($0)" }.joined(separator: "\n")

        let cause = registered.isEmpty
            ? """
            No test views are registered at all. Either the registration calls are missing, or they \
            run too late: testHost() resolves the view under test before the first render, so calls \
            made from a computed property (such as `var mvvmEnv`), from .onAppear, or from .task \
            never arrive in time.
            """
            : """
            Some test views are registered, but not this one. Add the view whose ViewModel is \
            '\(viewModelType)' to the registration list.
            """

        return """
        ================================================================================
        FOSMVVM testHost(): cannot present the view under test.\n
        The test harness asked for the view whose ViewModel is:
          \(viewModelType)\n
        Registered ViewModels:
        \(registeredList)\n
        \(cause)\n
        To fix, register the *View* (not the ViewModel) from your App's init():\n
            @main struct MyApp: App {
                init() {
                    MVVMEnvironment.registerTestingViews()
                }
            }\n
            private extension MVVMEnvironment {
                @MainActor static func registerTestingViews() {
                    #if DEBUG
                    registerTestView(MyView.self)   // where MyView.VM == \(viewModelType)
                    #endif
                }
            }\n
        See the documentation for MVVMEnvironment.registerTestView(_:).
        ================================================================================
        """
    }

    /// The message for a registered view whose ViewModel could not be decoded from the
    /// payload the test sent
    ///
    /// - Parameters:
    ///   - viewModelType: The ViewModel type name the test harness asked for, so the developer
    ///     reading the log can match it to their test.
    ///   - error: The decoding error, surfaced verbatim in the message.
    static func undecodableViewModel(viewModelType: String, error: any Error) -> String {
        """
        ================================================================================
        FOSMVVM testHost(): cannot decode the ViewModel for the view under test.\n
        ViewModel type requested by the test harness:
          \(viewModelType)\n
        Decoding error:
          \(error)\n
        The view registered for '\(viewModelType)' has a different VM associated type than the
        payload the test sent, or that payload is not valid JSON for it. Check that the view passed
        to MVVMEnvironment.registerTestView(_:) is the one whose VM is '\(viewModelType)', and that
        the test's ViewModel generic argument matches it.\n
        See the documentation for MVVMEnvironment.registerTestView(_:).
        ================================================================================
        """
    }
}
