// ViewModelOperations.swift
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

/// Operations that can be performed by the ``ViewModel``
///
/// # Overview
///
/// Factoring operations from the ``ViewModel`` implementation provides for
/// the opportunity for mocking and testing.
///
/// ## Example
///
/// Here's an example of how this might be employed:
///
/// ```swift
/// @ViewModel struct ButtonViewModel {
///   @LocalizedString var buttonTitle
///
///   private let isStub: Bool
///
///   public var operations: any ButtonViewModelOperations {
///       isStub ? ButtonStubOps() : ButtonOps()
///   }
///
///   let vmId: ViewModelId
///
///   init() {
///     self.init(isStub: false)
///   }
///
///   private init(isStub: Bool) {
///     self.isStub = isStub
///     self.vmId = .init(type: Self.self)
///   }
///
///   static func stub() -> Self {
///       self.init(isStub: true)
///   }
/// }
///
/// public protocol ButtonViewModelOperations: ViewModelOperations {
///     func buttonClicked()
/// }
///
/// public struct ButtonOps: ButtonViewModelOperations {
///     public func buttonClicked() {
///         // Do something awesome!
///     }
/// }
///
/// public final class ButtonStubOps: ButtonViewModelOperations {
///     public private(set) var buttonClickedCalled: Bool = false
///
///     public func buttonClicked() {
///         buttonClickedCalled = true
///     }
///
///     public init() {}
/// }
///
/// // NOTE: For full details on how to configure testing see
/// // Testing Overview in the documentation.
///
/// final class ButtonViewUITests {
///     // MARK: Operation Tests
///
///     func testButtonClicked() async throws {
///         let app = try presentView()
///
///         app.myButton.tap()
///
///         let stubOps: ButtonStubOps = try viewModelOperations()
///
///         XCTAssertTrue(stubOps.buttonClickedCalled)
///     }
/// }
///
/// private extension XCUIApplication {
///     var myButton: XCUIElement {
///         buttons.element(matching: .button, identifier: "myButton")
///     }
/// }
/// ```
public protocol ViewModelOperations: Sendable, Codable {}
