// ViewModelViewTestCase.swift
//
// Created by David Hunt on 1/15/25
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
///             resourceDirectoryName: "",
///             urlAppHost: "myapphostname",
///             appBundleIdentifier: "com.mycompany.myapp"
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
/// import Testing
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
    private var urlAppHost: String?
    private var locStore: LocalizationStore?
    private var locales: Set<Locale>?

    /// Presents a *ViewModelView* associated with the given *ViewModel*
    ///
    /// - Parameters:
    ///   - viewModel: A *ViewModel* instance to use to populate a corresponding *ViewModelView* (default: .stub())
    ///   - timeout: The number of seconds to wait for the application to respond (default: 3)
    /// - Returns: The *XCUIApplication* that proxies the *ViewModelView*
    @MainActor public func presentView(viewModel: VM = .stub(), timeout: TimeInterval = 3) throws -> XCUIApplication {
        guard let app, let urlAppHost else {
            throw RunError.setupNotCalled
        }

        // NOTE: I've tried app.open(), but have been unable to get it to work.  This
        //       method of using launchArguments seems to work very well.

        let url = try url(for: viewModel, urlAppHost: urlAppHost, locale: Self.en)
        app.launchArguments.append(url.absoluteString)
        app.activate()
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

        let _vmoData = app.staticTexts
            .element(matching: .staticText, identifier: TestDataTransporter.accessibilityIdentifier)
            .value
        guard let vmoData = (_vmoData as? String)?.reveal else {
            throw RunError.cannotRetrieveOperationsData
        }

        return try vmoData.fromJSON() as VMO
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
    ///             urlAppHost: "myapphostname",
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
    ///   - urlAppHost: The host of the URL that the test application registered as a URLType
    ///   - appBundleIdentifier: The application's bundle identifier
    ///   - locales: The locales to test (default: en)
    public func setUp(bundle: Bundle, resourceDirectoryName: String = "", urlAppHost: String, appBundleIdentifier: String, locales: Set<Locale>? = nil) async throws {
        try await super.setUp()

        self.urlAppHost = urlAppHost
        locStore = try await bundle.yamlLocalization(
            resourceDirectoryName: resourceDirectoryName
        )
        self.locales = locales ?? [Self.en]

        let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
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

    private func url(for viewModel: VM, urlAppHost: String, locale: Locale) throws -> URL {
        let encoder = encoder(locale: locale)
        let viewModelStr = try viewModel.toJSON(encoder: encoder).obfuscate

        let urlStr = "\(urlAppHost)://test-view-request?viewModelType=\(String(describing: VM.self))&viewModel=\(viewModelStr)"
        guard let url = URL(string: urlStr) else {
            throw RunError.badUrlString(urlStr)
        }

        return url
    }
}

public enum RunError: Error {
    case didntStart
    case setupNotCalled
    case badUrlString(_ str: String)
    case cannotRetrieveOperationsData
}
#endif
