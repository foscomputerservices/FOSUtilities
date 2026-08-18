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
    /// with ``MVVMEnvironment/registerTestView(_:scrollable:)``; this function resolves the view under test
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
    /// with ``MVVMEnvironment/registerTestView(_:scrollable:)``; this function resolves the view under test
    /// before the first render, and stops with a diagnostic if it is not registered by then.
    @MainActor func testHost() -> some View {
        testHost(decorator: { _, view in view })
    }
}

#if DEBUG
public extension URL {
    static let testHostRequest = "test-view-request"
}
#endif

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

    @MainActor func view(registeredTypes: [String: MVVMEnvironment.TestViewRegistration]) -> AnyView? {
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

            // The registration declares the view is designed for a scrolling parent;
            // the harness supplies the parent production would.
            return registration.scrollable
                ? AnyView(ScrollView(.vertical) { view })
                : view
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

extension ViewModelView {
    static var vmTypeStr: String {
        String(describing: type(of: self))
    }
}

#if DEBUG
@MainActor
private struct TestingView<BaseView: View>: View {
    private let testView: AnyView

    var body: some View {
        testView
        #if os(iOS)
        .onAppear {
            DismissKeyboardWindow.install()
        }
        #endif
    }

    init(baseView: BaseView) {
        self.testView = ProcessInfo.processInfo.view(
            registeredTypes: MVVMEnvironment.registeredTestTypes
        ) ?? AnyView(baseView)
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

    private static func makeWindow() -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return nil // Retried on the next keyboardWillShow
        }

        let window = UIWindow(windowScene: scene)
        // Below the status-bar region, so a synthesized tap cannot be read as a status-bar
        // gesture; the top of the screen is the one place a keyboard can never reach.
        let topInset = scene.windows.first?.safeAreaInsets.top ?? 0
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

/// The diagnostics deliberately sit OUTSIDE `canImport(SwiftUI)`: they are pure text, and keeping
/// them portable is what lets the Linux `swift test` leg — the only leg CI actually executes —
/// cover them. Everything they describe is SwiftUI-only; the messages themselves need not be.
enum TestHostDiagnostic {
    /// Reports to stderr *and* traps.
    ///
    /// The Swift runtime folds a `fatalError` message into a single crash-report line, which log
    /// viewers truncate; the stderr write is what guarantees the whole block reaches an
    /// `xcodebuild` test log intact.
    static func reportAndStop(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\n\(message)\n".utf8))
        fatalError(message)
    }

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
        FOSMVVM testHost(): cannot present the view under test.

        The test harness asked for the view whose ViewModel is:
          \(viewModelType)

        Registered ViewModels:
        \(registeredList)

        \(cause)

        To fix, register the *View* (not the ViewModel) from your App's init():

            @main struct MyApp: App {
                init() {
                    MVVMEnvironment.registerTestingViews()
                }
            }

            private extension MVVMEnvironment {
                @MainActor static func registerTestingViews() {
                    #if DEBUG
                    registerTestView(MyView.self)   // where MyView.VM == \(viewModelType)
                    #endif
                }
            }

        See the documentation for MVVMEnvironment.registerTestView(_:).
        ================================================================================
        """
    }

    static func undecodableViewModel(viewModelType: String, error: any Error) -> String {
        """
        ================================================================================
        FOSMVVM testHost(): cannot decode the ViewModel for the view under test.

        ViewModel type requested by the test harness:
          \(viewModelType)

        Decoding error:
          \(error)

        The view registered for '\(viewModelType)' has a different VM associated type than the
        payload the test sent, or that payload is not valid JSON for it. Check that the view passed
        to MVVMEnvironment.registerTestView(_:) is the one whose VM is '\(viewModelType)', and that
        the test's ViewModel generic argument matches it.

        See the documentation for MVVMEnvironment.registerTestView(_:).
        ================================================================================
        """
    }
}
