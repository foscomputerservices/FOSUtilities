// XCTAssert+Localizable.swift
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

#if os(iOS) || os(tvOS) || os(watchOS) || os(macOS) || os(visionOS)
import FOSMVVM
import XCTest

/// Asserts that displayed text matches a *ViewModel*'s localized property
///
/// ```swift
/// let viewModel: DashboardViewModel = try localizedViewModel()
/// let app = try presentView(viewModel: viewModel)
///
/// XCTAssertEqual(app.uiTestingElement("dashboardTitle").label, viewModel.title)
/// ```
///
/// Compare against the *ViewModel* the view was given, never a string literal — a literal
/// passes in one locale and fails in the next, and it fails again when the copy is reworded.
///
/// The comparison is made against the ``Localizable``'s localized **String**.  A
/// ``Localizable`` that cannot be localized — one whose translation was never realized —
/// fails the assertion and says so, rather than throwing: a test that stops at the first
/// unrealized translation reports one problem where it could have reported all of them.
public func XCTAssertEqual(
    _ expression1: @autoclosure () -> String,
    _ expression2: @autoclosure () -> some Localizable,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(expression1(), expression2().localizedForComparison, message(), file: file, line: line)
}

/// Asserts that displayed text matches a *ViewModel*'s localized property
///
/// ```swift
/// XCTAssertEqual(app.uiTestingElement("emailField").value, viewModel.email)
/// ```
///
/// An element's `value` is optional; `nil` never matches a ``Localizable``.
public func XCTAssertEqual(
    _ expression1: @autoclosure () -> String?,
    _ expression2: @autoclosure () -> some Localizable,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(expression1(), expression2().localizedForComparison, message(), file: file, line: line)
}

/// Asserts that displayed text differs from a *ViewModel*'s localized property
///
/// ```swift
/// XCTAssertNotEqual(app.uiTestingElement("statusLabel").label, viewModel.errorStatus)
/// ```
public func XCTAssertNotEqual(
    _ expression1: @autoclosure () -> String,
    _ expression2: @autoclosure () -> some Localizable,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertNotEqual(expression1(), expression2().localizedForComparison, message(), file: file, line: line)
}

/// Asserts that displayed text differs from a *ViewModel*'s localized property
///
/// ```swift
/// XCTAssertNotEqual(app.uiTestingElement("emailField").value, viewModel.email)
/// ```
public func XCTAssertNotEqual(
    _ expression1: @autoclosure () -> String?,
    _ expression2: @autoclosure () -> some Localizable,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertNotEqual(expression1(), expression2().localizedForComparison, message(), file: file, line: line)
}

private extension Localizable {
    /// Stands in for the localized string when localization fails. It cannot match any text a
    /// view could display, so the assertion fails as it should, and it names the cause — an
    /// unrealized translation and a genuinely wrong label are different bugs that a bare
    /// string comparison reports identically.
    var localizedForComparison: String {
        do {
            return try localizedString
        } catch {
            return "<not localized: \(error)>"
        }
    }
}
#endif
