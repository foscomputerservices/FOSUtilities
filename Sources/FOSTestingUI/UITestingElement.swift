// UITestingElement.swift
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
import XCTest

public extension XCUIApplication {
    /// Finds the view tagged with `uiTestingIdentifier(_:isEnabled:)` (**FOSMVVM**)
    ///
    /// ## Example
    ///
    /// ```swift
    /// func testSaves() async throws {
    ///     let app = try presentView()
    ///
    ///     app.uiTestingElement("nameField").type("Fern")
    ///     app.uiTestingElement("saveButton").tap()
    ///
    ///     XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())
    /// }
    /// ```
    ///
    /// The identifier is what a test names.  There is no XCUITest element type to choose, no
    /// query to compose, and no displayed text to match, so finding a view survives the control
    /// that renders it being replaced, and never has to be suppressed for matching against
    /// non-localized text.
    ///
    /// If no view carries the identifier, ``UITestingElement/exists`` is `false` and
    /// ``UITestingElement/tap()`` and ``UITestingElement/type(_:)`` fail the test naming the
    /// identifier they looked for.
    ///
    /// - Parameter identifier: The identifier given to `uiTestingIdentifier(_:isEnabled:)`.
    /// - Returns: The tagged view, whether or not it presently exists; ask
    ///   ``UITestingElement/exists`` or ``UITestingElement/waitForExistence(timeout:)``.
    func uiTestingElement(_ identifier: String) -> UITestingElement {
        .init(app: self, identifier: identifier)
    }
}

/// A view tagged with `uiTestingIdentifier(_:isEnabled:)` (**FOSMVVM**), as seen by an XCUITest
///
/// Obtain one from `XCUIApplication.uiTestingElement(_:)`:
///
/// ```swift
/// let saveButton = app.uiTestingElement("saveButton")
///
/// XCTAssertTrue(saveButton.isVisible)
/// saveButton.tap()
/// ```
///
/// This is **not** an **XCUIElement** — it offers the gestures and questions a test needs of
/// a tagged view, and ``xcuiElement`` reaches the element itself for anything else.
///
/// The tagged view is resolved at each use, so a single value stays correct as the screen
/// changes:
///
/// ```swift
/// let banner = app.uiTestingElement("savedBanner")
///
/// XCTAssertFalse(banner.exists)
/// app.uiTestingElement("saveButton").tap()
/// XCTAssertTrue(banner.waitForExistence())
/// ```
@MainActor public struct UITestingElement {
    private let app: XCUIApplication
    private let identifier: String

    /// Whether the tagged view is part of the view hierarchy
    ///
    /// A view that is present but scrolled off screen *exists*; ask ``isVisible`` to
    /// distinguish the two.
    public var exists: Bool {
        xcuiElement.exists
    }

    /// Whether the tagged view is on screen and able to receive a tap
    ///
    /// ```swift
    /// XCTAssertTrue(app.uiTestingElement("saveButton").isVisible)
    /// ```
    ///
    /// A view that is part of the hierarchy but scrolled out of sight is not visible; ``exists``
    /// reports that case.
    public var isVisible: Bool {
        let element = xcuiElement

        return element.exists && (element.isHittable || isOnScreen(element))
    }

    /// The tagged view's accessibility label
    ///
    /// ```swift
    /// XCTAssertEqual(app.uiTestingElement("titleLabel").label, viewModel.title)
    /// ```
    ///
    /// Each read of ``label``, ``value`` or ``isEnabled`` asks the running application, so assert
    /// the one that carries the meaning rather than sweeping all three.
    ///
    /// ``label``, ``value`` and ``isEnabled`` report the state of the tagged *control*.  Tag the
    /// control itself to assert its state: tagging a stack that groups other tagged views and
    /// asking that stack for a label reports one of the controls within it.
    public var label: String {
        taggedControl?.label ?? xcuiElement.label
    }

    /// The tagged view's accessibility value, if it has one
    public var value: String? {
        (taggedControl?.value ?? xcuiElement.value) as? String
    }

    /// Whether the tagged view accepts user interaction
    ///
    /// ```swift
    /// XCTAssertFalse(app.uiTestingElement("saveButton").isEnabled)
    /// ```
    public var isEnabled: Bool {
        taggedControl?.isEnabled ?? xcuiElement.isEnabled
    }

    // swiftformat:disable docComments
    // Not a doc comment — the customer's contract is on `label`, `value` and `isEnabled`.
    //
    // Two kinds of element carry an identifier. `TabContent.uiTestingIdentifier(_:)`, and any
    // view tagged with `accessibilityIdentifier` directly, put it on the element itself, which
    // therefore holds its own state. The `View` tag is carried beside the view instead, on an
    // element with no type and no label of its own, and the view has to be recovered from the
    // frame they share. Resolving the first kind by frame would answer with a neighbour.
    //
    // Children are walked in document order so that a repeated identifier resolves to the same
    // element `xcuiElement` returns, which takes XCUITest's `firstMatch`.
    // swiftformat:enable docComments
    private var taggedControl: XCUIElementSnapshot? {
        guard let root = try? app.snapshot() else { return nil }

        var elements: [XCUIElementSnapshot] = []
        var pending = [root]
        while let next = pending.popLast() {
            elements.append(next)
            pending.append(contentsOf: next.children.reversed())
        }

        guard let tag = elements.first(where: { $0.identifier == identifier }) else { return nil }

        guard tag.elementType == .other, tag.label.isEmpty else {
            return tag
        }

        let bounds = tag.frame
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        var match: XCUIElementSnapshot?
        var matchDistance = CGFloat.greatestFiniteMagnitude

        for candidate in elements where candidate.identifier != identifier {
            let candidateBounds = candidate.frame
            guard candidateBounds.contains(centre) else { continue }

            let distance =
                abs(candidateBounds.minX - bounds.minX) + abs(candidateBounds.minY - bounds.minY) +
                abs(candidateBounds.width - bounds.width) + abs(candidateBounds.height - bounds.height)

            // A tie goes to the real control: a container reports itself as `.other` and
            // can share its only child's bounds exactly.
            let isCloser = distance < matchDistance - 0.5
            let isEquallyCloseButMoreSpecific =
                abs(distance - matchDistance) <= 0.5 &&
                match?.elementType == .other && candidate.elementType != .other

            if isCloser || isEquallyCloseButMoreSpecific {
                matchDistance = min(distance, matchDistance)
                match = candidate
            }
        }

        return match
    }

    /// The element carrying the tag, for test operations this type does not offer
    ///
    /// ```swift
    /// let row = app.uiTestingElement("firstRow").xcuiElement
    /// let gone = XCTNSPredicateExpectation(predicate: .init(format: "exists == false"), object: row)
    /// ```
    ///
    /// This is the element the tag is on, which is not always the tagged view itself: a `View`
    /// is tagged alongside rather than on, so the element shares the view's bounds but carries
    /// none of its label, value or enablement — ask this type for those.
    public var xcuiElement: XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for the tagged view to become part of the view hierarchy
    ///
    /// ```swift
    /// app.uiTestingElement("saveButton").tap()
    ///
    /// XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())
    /// ```
    ///
    /// Wait for a view that appears in response to something the test did; ``exists`` answers
    /// whether a view is there *now*.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: `true` if the view exists before the timeout elapses.
    @discardableResult public func waitForExistence(timeout: TimeInterval = 3) -> Bool {
        xcuiElement.waitForExistence(timeout: timeout)
    }

    /// Waits for the tagged view to leave the view hierarchy
    ///
    /// ```swift
    /// app.uiTestingElement("dismissButton").tap()
    ///
    /// XCTAssertTrue(app.uiTestingElement("errorBanner").waitForDisappearance())
    /// ```
    ///
    /// Wait for a view that goes away in response to something the test did; for a view that
    /// was never there at all, ask ``exists``.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: `true` if the view is gone before the timeout elapses.
    @discardableResult public func waitForDisappearance(timeout: TimeInterval = 3) -> Bool {
        let departed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: xcuiElement
        )

        return XCTWaiter().wait(for: [departed], timeout: timeout) == .completed
    }

    /// Taps the tagged view
    ///
    /// ```swift
    /// app.uiTestingElement("saveButton").tap()
    /// ```
    public func tap(file: StaticString = #filePath, line: UInt = #line) {
        let element = xcuiElement
        guard element.exists else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        if element.isHittable {
            element.tap()
        } else if isOnScreen(element) {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            // Off screen: left to tap(), which reports it, rather than tapping nothing.
            element.tap()
        }
    }

    // swiftformat:disable docComments
    // isHittable is false for a SwiftUI menu that is on screen and perfectly tappable, so
    // geometry answers when it says no. Shared by isVisible and tap() so that the two cannot
    // disagree about whether a view can be tapped.
    // swiftformat:enable docComments
    private func isOnScreen(_ element: XCUIElement) -> Bool {
        let bounds = element.frame

        return !bounds.isEmpty && app.frame.contains(CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private static func notFound(_ identifier: String) -> String {
        "No view is tagged \"\(identifier)\". Check the identifier given to uiTestingIdentifier(_:), and that the view is on screen."
    }

    /// Types text into the tagged view
    ///
    /// The view is given keyboard focus and then receives the text:
    ///
    /// ```swift
    /// app.uiTestingElement("nameField").type("Fern")
    /// ```
    ///
    /// - Parameter text: The text to type.
    public func type(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard xcuiElement.exists else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        // Focus and typing are separate steps: the tag is carried alongside the view rather
        // than on it, so the tagged element never holds keyboard focus itself and typing into
        // it directly fails. Tapping moves focus to the field, after which the application
        // routes typed text to whatever holds it.
        tap(file: file, line: line)
        app.typeText(text)
    }

    init(app: XCUIApplication, identifier: String) {
        self.app = app
        self.identifier = identifier
    }
}
#endif
