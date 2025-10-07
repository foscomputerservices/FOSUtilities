// ViewModelViewTestCase.swift
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

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS) || os(visionOS)
import FOSFoundation
import FOSMVVM
import Foundation
import XCTest

/// A specialization of **XCTestCase** that can be used to proxy *ViewModel*s and *ViewModelOperations*
/// over the *XCTest* proxy
///
/// ``ViewModelViewTestCase`` provides for the ability to test each *ViewModelView* independently of all
/// other *ViewModelView* implementations.  Communication is handled automatically given a few pieces of configuration.
///
/// ## Application Configuration
///
/// ... Formal Specification TBD ...
///
/// ## Test Configuration
///
/// It is suggested to make a single subclass of ``ViewModelViewTestCase`` as follows:
///
/// ```swift
/// import FOSFoundation
/// import FOSMVVM
/// import FOSTesting
/// import Foundation
/// import XCTest
///
/// class MyViewModelViewTestCase<VM: ViewModel, VMO: ViewModelOperations>: ViewModelViewTestCase<VM, VMO>, @unchecked Sendable {
///
///     override func setUp() async throws {
///         try await super.setUp(
///             bundle: Bundle.main,
///             resourceDirectoryName: ""
///         )
///
///         continueAfterFailure = false // Stop the test and move on
///     }
/// }
/// ```
///
/// All other UI test implementations should then inherit from this class:
///
/// ```swift
/// import MyViewModels
/// import FOSFoundation
/// import FOSMVVM
/// import FOSTesting
/// import Foundation
/// import XCTest
///
/// final class MyViewUITests: MyViewModelViewTestCase<MyViewModel, MyViewModelStubOperations>, @unchecked Sendable {
///     func testSomething() async throws {
///         let app = try await presentView()
///
///         app.aField.tap()
///         app.aField.typeText("some text")
///
///         app.saveButton.tap()
///
///         let stubOps = try viewModelOperations()
///
///         XCTAssertTrue(stubOps.dataSaved)
///         XCTAssertEqual(stubOps.data, "some text")
///     }
/// }
/// ```
@MainActor open class ViewModelViewTestCase<VM: ViewModel, VMO: ViewModelOperations>: XCTestCase, @unchecked Sendable {
    private var app: XCUIApplication?

    private var locStore: LocalizationStore?

    /// Returns the `LocalizationStore` used to localize `ViewModel`
    ///
    /// - Throws: ``RunError.setupNotCalled`` if the test case's
    ///    setup method has not yet been called.
    public var localizationStore: LocalizationStore {
        get throws {
            guard let locStore else {
                throw RunError.setupNotCalled
            }
            return locStore
        }
    }

    /// Returns the `Locale`s that are known to the `XCTestCase`
    public var locales: Set<Locale>?

    /// Returns a localized version of `ViewModel`
    ///
    /// - Parameters:
    ///   - viewModel: A `ViewModel` to localize (default: .stub())
    ///   - locale: The `Locale` to localize the `ViewModel` to (default: nil)
    public func localizedViewModel(
        _ viewModel: VM = .stub(),
        locale: Locale? = nil
    ) throws -> VM {
        try viewModel.toJSON(
            encoder: encoder(locale: locale)
        ).fromJSON()
    }

    /// Presents a *ViewModelView* associated with the given *ViewModel*
    ///
    /// The *testConfiguration* name is passed to the application under test via the *testHost* function.
    /// ## Example - XCUITestCase
    ///
    /// ```swift
    /// func testShowBPoP_Connected() async throws {
    ///     let app = try presentView(
    ///         testConfiguration: "ProvideBinding",
    ///         viewModel: .stub(bPoPId: .stub(), isBPoPConnected: true),
    ///     )
    ///
    ///     ...
    /// }
    /// ```
    ///
    /// ## Example - Test Host
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
    /// - Parameters:
    ///   - testConfiguration: A name for the configuration under test
    ///   - viewModel: A *ViewModel* instance to use to populate a corresponding *ViewModelView* (default: .stub())
    ///   - locale: The *Locale* to use to encode the *ViewModel* (default: Self.en)
    ///   - timeout: The number of seconds to wait for the application to respond (default: 3)
    /// - Returns: The *XCUIApplication* that proxies the *ViewModelView*
    @MainActor public func presentView(
        testConfiguration: String = "",
        viewModel: VM = .stub(),
        locale: Locale? = nil,
        timeout: TimeInterval = 3
    ) throws -> XCUIApplication {
        guard let app else {
            throw RunError.setupNotCalled
        }

        app.launchEnvironment["__FOS_ViewModelType"] = String(describing: VM.self)
        app.launchEnvironment["__FOS_ViewModel"] =
            try localizedViewModel(viewModel, locale: locale)
                .toJSON()
                .obfuscate
        app.launchEnvironment["__FOS_TestConfiguration"] = testConfiguration
        app.launch()
        guard app.wait(for: .runningForeground, timeout: timeout) else {
            XCTFail("Application did not reach the running state!")
            throw RunError.didntStart
        }

        return app
    }

    /// Retrieves the *ViewModelOperations* that were sent using **TestDataTransporter**
    @MainActor public func viewModelOperations() throws -> VMO {
        guard let app else {
            throw RunError.didntStart
        }

        // It is possible that there are multiple TestsDataTransporter instances available.
        // This occurs when child views are testable, which can happen a lot.
        let _vmoDataItems = app.staticTexts
            .matching(.staticText, identifier: TestDataTransporter.accessibilityIdentifier)
        for i in 0..<_vmoDataItems.count {
            let _vmoData = _vmoDataItems.element(boundBy: i)
            if let vmoData = (_vmoData.value as? String)?.reveal,
               let vmoResult = try? vmoData.fromJSON() as VMO {
                return vmoResult
            }
        }

        throw RunError.cannotRetrieveOperationsData
    }

    /// Sets up the application for each test pass
    ///
    /// This method should be called from the subclass's setup() method.
    ///
    /// ## Example
    ///
    /// ```
    /// @MainActor
    /// class MyViewModelViewTestCase<VM: ViewModel, VMO: ViewModelOperations>: ViewModelViewTestCase<VM, VMO> {
    ///
    ///     override func setUp() async throws {
    ///         try await super.setUp(
    ///             bundle: Bundle.main,
    ///             resourceDirectoryName: "",
    ///             appBundleIdentifier: "com.mycompany.myapp"
    ///         )
    ///
    ///         continueAfterFailure = false // Stop the test and move on
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - bundle: The test harness's application bundle
    ///   - resourceDirectoryName: The directory in the bundle to search for localizations (default: "")
    ///   - appBundleIdentifier: The application's bundle identifier
    ///   - locales: The locales to test (default: en)
    public func setUp(
        bundle: Bundle,
        resourceDirectoryName: String = "",
        appBundleIdentifier: String,
        locales: Set<Locale>? = nil
    ) async throws {
        try await super.setUp()

        locStore = try bundle.yamlLocalization(
            resourceDirectoryName: resourceDirectoryName
        )
        self.locales = locales ?? [Self.en]

        let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)

        // Shutdown the application on each pass.  It is re-launched
        // when presentView() is called so that a fresh view and
        // view state is used on each test pass.
        app.terminate()
        self.app = app
    }

    override public func tearDown() async throws {
        app = nil

        try await super.tearDown()
    }

    public static var en: Locale {
        Locale(identifier: "en")
    }

    public var en: Locale {
        Self.en
    }

    public static var enUS: Locale {
        Locale(identifier: "en-US")
    }

    public var enUS: Locale {
        Self.enUS
    }

    public static var enGB: Locale {
        Locale(identifier: "en-GB")
    }

    public var enGB: Locale {
        Self.enGB
    }

    public static var es: Locale {
        Locale(identifier: "es")
    }

    public var es: Locale {
        Self.es
    }

    private func encoder(locale: Locale? = nil) -> JSONEncoder {
        guard let locStore else {
            fatalError("setUpWithError not called")
        }
        return JSONEncoder.localizingEncoder(
            locale: locale ?? en,
            localizationStore: locStore
        )
    }
}

public enum RunError: Error, CustomDebugStringConvertible {
    case didntStart
    case setupNotCalled
    case badUrlString(_ str: String)
    case cannotRetrieveOperationsData

    public var debugDescription: String {
        switch self {
        case .didntStart:
            "RunError: Run did not start"
        case .setupNotCalled:
            "RunError: setup() was not called"
        case .badUrlString(let str):
            "RunError: Bad URL string: \(str)"
        case .cannotRetrieveOperationsData:
            "RunError: Cannot retrieve operations data"
        }
    }
}
#endif
