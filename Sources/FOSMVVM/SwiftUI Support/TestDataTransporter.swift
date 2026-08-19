// TestDataTransporter.swift
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

#if canImport(SwiftUI)
import SwiftUI

/// ``TestDataTransporter`` provides a mechanism for transporting ``ViewModelOperations`` data
/// from the client application back to the testing host application
///
/// ``TestDataTransporter`` can be used to verify values that were sent to ``ViewModelOperations``
/// via XCUITests.  This is accomplished by encoding the given ``ViewModelOperations`` to JSON and
/// attaching it to a blank static text element via accessibility.  *ViewModelTestCase* provides a method
/// *viewModelOperations(app:)* to retrieve this JSON data from the static text element and to restore it to
/// the given ``ViewModelOperations`` type, which can be used with various XCTAssert() methods
/// to verify proper operation of the user interface elements.
///
/// ## Example
///
/// ### View
///
/// ```swift
/// struct MyView: ViewModelView {
///    @State private var data = ""
///
///    let myViewModel: MyViewModel
///    private let operations: any MyViewModelOperations
///
///    #if DEBUG
///    @State private var repaintToggle = false
///    #endif
///
///   var body: some View {
///
///     VStack {
///       TextField("", text: $data)
///         .uiTestingIdentifier("dataTextField")
///
///       Button(action: save) {
///         Text("Tap Me")
///       }
///       .uiTestingIdentifier("saveButton")
///     }
///     #if DEBUG
///     .testDataTransporter(viewModelOps: operations, repaintToggle: $repaintToggle)
///     #endif
///   }
///
///   private func save() {
///     operations.saveData(data: data)
///     toggleRepaint()
///   }
///
///   private func toggleRepaint() {
///     #if DEBUG
///     repaintToggle.toggle()
///     #endif
///   }
/// }
///
/// public final class MyViewModelStubOps: MyViewModelOperations, @unchecked Sendable {
///     public private(set) var data: String?
///     public private(set) var saveDataCalled: Bool
///
///     public func saveData(data: String) {
///         self.data = data
///         saveDataCalled = true
///     }
///
///     public init() {
///         self.data = nil
///         self.saveDataCalled = false
///     }
/// }
/// ```
///
/// ### UITests
/// ```swift
/// @testable import MyViewModels
/// import FOSFoundation
/// import FOSMVVM
/// import FOSTesting
/// import Foundation
/// @testable import MyApp
/// import XCTest
///
/// final class LandingPageViewUITests: MyViewModelViewTestCase<MyViewModel, MyViewModelStubOps> {
///     func testSomething() async throws {
///         let app = try presentView()
///
///         app.dataTextField.tap()
///         app.dataTextField.typeText("some text")
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
public struct TestDataTransporter: View {
    public static let accessibilityIdentifier = "__testing_view_data__"

    private let viewModelOps: any ViewModelOperations
    private let repaintToggle: Binding<Bool>

    public var body: some View {
        // ********** SECURITY, SECURITY, SECURITY **********
        //
        // This data should *** never *** be presented in production.
        // Doing so would leak the user's data into publicly visible
        // ui elements in the application.
        #if DEBUG
        if repaintToggle.wrappedValue {
            Text("")
                .accessibilityIdentifier(Self.accessibilityIdentifier)
                // swiftlint:disable:next force_try
                .accessibilityValue(try! viewModelOps.toJSON().obfuscate)
                // A zero-sized empty Text inside a ScrollView is culled from the
                // accessibility tree, making the payload unreadable (measured on iOS 27;
                // 1×1 survives). Hit-testing is refused and accessibility pinned visible
                // so the footprint stays inert for the UI under test.
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(false)
        } else {
            Text("")
                .accessibilityIdentifier(Self.accessibilityIdentifier)
                // swiftlint:disable:next force_try
                .accessibilityValue(try! viewModelOps.toJSON().obfuscate)
                // Same footprint as the sibling branch above — see its comment.
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(false)
        }
        #else
        EmptyView()
        #endif
    }

    public init(viewModelOps: any ViewModelOperations, repaintToggle: Binding<Bool>) {
        self.viewModelOps = viewModelOps
        self.repaintToggle = repaintToggle
    }
}

public extension View {
    @ViewBuilder func testDataTransporter(viewModelOps: any ViewModelOperations, repaintToggle: Binding<Bool>) -> some View {
        #if DEBUG
        ZStack {
            self
            // The transporter fronts the host view: behind an opaque card inside a
            // ScrollView it is pruned from the accessibility tree; in front it survives.
            // It draws nothing and refuses hit-testing, so fronting is inert for the UI
            // under test.
            TestDataTransporter(
                viewModelOps: viewModelOps,
                repaintToggle: repaintToggle
            )
        }
        #else
        self
        #endif
    }
}
#endif
