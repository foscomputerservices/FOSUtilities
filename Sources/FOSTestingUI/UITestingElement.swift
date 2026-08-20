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
/// XCTAssertTrue(saveButton.waitForExistence())
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
/// app.uiTestingElement("dismissBanner").tap()
/// XCTAssertTrue(banner.waitForDisappearance())
/// ```
@MainActor public struct UITestingElement {
    private let app: XCUIApplication
    private let identifier: String

    /// Whether the tagged view is part of the view hierarchy
    ///
    /// `exists` answers about the hierarchy as it is *now* — assert with it only when
    /// nothing is in flight, such as a view that was never presented:
    ///
    /// ```swift
    /// XCTAssertFalse(app.uiTestingElement("errorBanner").exists)
    /// ```
    ///
    /// A view that is still *arriving* is not there yet — asserting `exists` right after a
    /// launch or a tap races the presentation. Wait instead:
    ///
    /// ```swift
    /// XCTAssertTrue(app.uiTestingElement("savedBanner").waitForExistence())
    /// ```
    ///
    /// A view that is *departing* races the same way — and mind the polarity: a departure
    /// is proven with `XCTAssertTrue`, not the instinctive `XCTAssertFalse`:
    ///
    /// ```swift
    /// XCTAssertTrue(app.uiTestingElement("errorBanner").waitForDisappearance())
    /// ```
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
    ///
    /// This answers about the screen as it is now, and a view the application has not finished
    /// presenting is not on it yet — a tab bar item is not there for the first moments after
    /// launch.  Wait for a view that is still arriving:
    ///
    /// ```swift
    /// XCTAssertTrue(app.uiTestingElement("settingsTab").waitForExistence())
    /// ```
    public var isVisible: Bool {
        let element = xcuiElement

        return element.exists && (element.isHittable || isOnScreen(element))
    }

    /// What the tagged control reads as
    ///
    /// ```swift
    /// XCTAssertEqual(app.uiTestingElement("titleLabel").label, viewModel.title)
    /// ```
    ///
    /// The same assertion holds on every platform: where a control's text lives differs between
    /// them, and this answers with the text either way.
    ///
    /// Each read of ``label``, ``value`` or ``isEnabled`` asks the running application, so assert
    /// the one that carries the meaning rather than sweeping all three.
    ///
    /// ``label``, ``value`` and ``isEnabled`` report the state of the tagged *control*.  A tag
    /// that spans a composite — a row holding a caption and a field — answers with the control
    /// the composite contains; when it holds several, the first in document order answers, so
    /// tag the control itself to address one precisely.
    public var label: String {
        let control = taggedControl()
        let label = control?.label ?? xcuiElement.label
        guard label.isEmpty else { return label }

        // AppKit carries a static text's string as its value, UIKit as its label. Only the
        // otherwise-empty answer falls through, so no control that has a label is affected.
        return (control?.value ?? xcuiElement.value) as? String ?? ""
    }

    /// The tagged view's accessibility value, if it has one
    public var value: String? {
        (taggedControl()?.value ?? xcuiElement.value) as? String
    }

    /// Whether the tagged view accepts user interaction
    ///
    /// ```swift
    /// XCTAssertFalse(app.uiTestingElement("saveButton").isEnabled)
    /// ```
    public var isEnabled: Bool {
        taggedControl()?.isEnabled ?? xcuiElement.isEnabled
    }

    /// What a resolution is for. Reads pass `none` and keep stage 1's answer unless it is a
    /// container; a hinted resolution also lets stage 2 reject a stage-1 winner that cannot
    /// serve the interaction — a StaticText cannot receive a tap meant for the field beside it.
    private enum ResolutionHint {
        case none
        case interactive
        case textEntry

        var acceptedTypes: Set<XCUIElement.ElementType> {
            self == .textEntry ? UITestingElement.textEntryTypes : UITestingElement.interactiveTypes
        }
    }

    // swiftformat:disable docComments
    // Not a doc comment — the customer's contract is on `label`, `value`, `isEnabled` and
    // `tap()`.
    //
    // Two kinds of element carry an identifier. `TabContent.uiTestingIdentifier(_:)`, and any
    // view tagged with `accessibilityIdentifier` directly, put it on the element itself, which
    // therefore holds its own state. The `View` tag is carried beside the view instead, on an
    // element with no type and no label of its own, and the view has to be recovered from the
    // frame they share. Resolving the first kind by frame would answer with a neighbour.
    //
    // Recovery is two-stage. Stage 1 keeps the original match: the candidate containing the
    // tag's centre with the closest frame. A tag spanning a composite row defeats it — the
    // centre can fall in the gap between caption and field (no leaf contains it; the row's
    // container wins with the same midpoint), or inside the caption (measured 7pt from that
    // gap). Stage 2 fires when stage 1 answers with a container, or with an element the hint
    // rules out, and takes the first element in document order of an accepted type whose own
    // centre lies within the tag's bounds — stage 1 inverted: it asked who contains the tag's
    // centre; stage 2 asks whose centre the tag contains, which is what keeps a scrim or
    // full-screen overlay, which merely intersects, from qualifying. Stage 1's answer stands
    // when nothing does.
    //
    // Children are walked in document order so that a repeated identifier resolves to the same
    // element `xcuiElement` returns, which takes XCUITest's `firstMatch`; document order also
    // picks among several controls under one tag.
    // swiftformat:enable docComments
    private func taggedControl(hint: ResolutionHint = .none) -> XCUIElementSnapshot? {
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

        let descends: Bool = switch match {
        case .none:
            true
        case .some(let match) where match.elementType == .other && match.label.isEmpty:
            true
        case .some(let match) where Self.containerTypes.contains(match.elementType):
            true
        case .some(let match):
            hint != .none && !hint.acceptedTypes.contains(match.elementType)
        }

        guard descends else { return match }

        let control = elements.first { candidate in
            candidate.identifier != identifier &&
                hint.acceptedTypes.contains(candidate.elementType) &&
                bounds.contains(CGPoint(x: candidate.frame.midX, y: candidate.frame.midY))
        }

        return control ?? match
    }

    /// The types stage 2 accepts: controls a synthesized interaction can land on. XCUITest
    /// offers no "is interactive" bit, so the set is curated.
    private nonisolated static let interactiveTypes: Set<XCUIElement.ElementType> = [
        .button, .checkBox, .comboBox, .datePicker, .link, .menuButton, .menuItem,
        .picker, .pickerWheel, .popUpButton, .radioButton, .searchField,
        .secureTextField, .segmentedControl, .slider, .stepper, .switch,
        .textField, .textView
    ]

    /// Types that enclose content rather than being it. Stage 1 answers with one when nothing
    /// contains the tag's centre — a row tag whose centre falls in the caption/field gap
    /// resolves the scroll view, window, or application above it (measured: the application
    /// element, which even carries a label, so `.other`-with-empty-label cannot be the whole
    /// container test). Never the tagged control; always worth descending from.
    private nonisolated static let containerTypes: Set<XCUIElement.ElementType> = [
        .application, .browser, .collectionView, .group, .navigationBar, .outline,
        .scrollView, .table, .tabGroup, .toolbar, .window
    ]

    /// The types a text entry can land in. `secureTextField` is present so `setText` can
    /// resolve one and *teach* — its read-back is bullets, so it is rejected, loudly.
    private nonisolated static let textEntryTypes: Set<XCUIElement.ElementType> = [
        .searchField, .secureTextField, .textField, .textView
    ]

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
    @discardableResult public func waitForExistence(timeout: TimeInterval = 10) -> Bool {
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
    /// Mind the polarity: the result is `true` when the view **left**, so a disappearance
    /// is proven with `XCTAssertTrue` — the opposite of the instinctive
    /// `XCTAssertFalse(...exists)`, which races a view that is still dismissing.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: `true` if the view is gone before the timeout elapses.
    @discardableResult public func waitForDisappearance(timeout: TimeInterval = 10) -> Bool {
        let departed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: xcuiElement
        )

        return XCTWaiter().wait(for: [departed], timeout: timeout) == .completed
    }

    /// Waits for the tagged view's frame to stop moving
    ///
    /// ```swift
    /// let amount = app.uiTestingElement("amountField")
    ///
    /// XCTAssertTrue(amount.waitForStableFrame())
    /// amount.xcuiElement.doubleTap()
    /// ```
    ///
    /// A view that is still being presented — a menu row while the menu animates in, a control
    /// mid-re-render — already *exists*, so an existence wait passes, yet a coordinate computed
    /// from its in-flight frame lands where the view *was*. ``tap()`` settles on its own; call
    /// this before interactions that bypass it: a native double-tap, addressing a control's
    /// child elements, asserting a frame.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: `true` once two consecutive frame reads agree; `false` when the timeout
    ///   elapses first, or immediately when the view left the hierarchy — a view that is gone
    ///   can never settle.
    @discardableResult public func waitForStableFrame(timeout: TimeInterval = 10) -> Bool {
        let element = xcuiElement
        let deadline = Date(timeIntervalSinceNow: timeout)
        var previous: CGRect?

        repeat {
            guard element.exists else { return false }

            let frame = element.frame
            if frame == previous, !frame.isEmpty {
                return true
            }
            previous = frame

            RunLoop.current.run(until: Date(timeIntervalSinceNow: Self.settleSamplingInterval))
        } while Date() < deadline

        return false
    }

    /// Taps the tagged view
    ///
    /// ```swift
    /// app.uiTestingElement("settingsTab").tap()
    /// ```
    ///
    /// The view is waited for, so a tap lands on a view the application is still presenting — a
    /// tab bar item in the first moments after launch, a screen mid-transition — rather than
    /// racing it, and the test does not open with a wait of its own.
    ///
    /// A tag that spans a composite — a row holding a caption and a field — taps the control
    /// within it rather than the row's midpoint, which can fall on the caption or in the gap
    /// between the two.
    ///
    /// A view the raised software keyboard covers is scrolled clear before the tap, so no
    /// scrolling or keyboard dismissal is needed between a text entry and a tap on a control
    /// beneath the keyboard:
    ///
    /// ```swift
    /// app.uiTestingElement("amountField").setText("42")  // the keyboard is now up
    /// app.uiTestingElement("saveButton").tap()           // covered by it — cleared, then tapped
    /// ```
    public func tap(file: StaticString = #filePath, line: UInt = #line) {
        // Waiting through the public wait keeps one default governing both it and the call site.
        guard waitForExistence() else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        let element = xcuiElement

        #if os(iOS)
        // A settled frame can still be an occluded one: hittability and app-frame
        // containment are both blind to the software keyboard (measured: taps dispatched
        // into the keys and the action silently never fired). Clear the target before
        // choosing any strategy, so every branch below aims from a cleared frame. The
        // existence checks honor the sharp edge: resolving .frame on an element that left
        // the tree (a menu row mid-scroll) fails the test hard, not degenerately.
        if element.exists, !isAimable(element.frame) {
            var lastFrame = element.frame
            scrollIntoBand {
                if element.exists {
                    lastFrame = element.frame
                }
                return lastFrame
            }
        }
        #endif

        // A tag spanning a composite covers caption and control alike, and the tag's midpoint
        // can miss the control entirely (measured: 1pt into the caption/field gap). The miss
        // is the same whether the tap is native — a hittable overlay's hit point IS the tag
        // midpoint — or a synthesized coordinate, so the aim decision precedes the branch
        // choice: only a resolved control that is genuinely a control, and genuinely
        // elsewhere, redirects the tap.
        let control = taggedControl(hint: .interactive)
        let aimsElsewhere = control.map { control in
            Self.interactiveTypes.contains(control.elementType) &&
                (abs(control.frame.midX - element.frame.midX) > 1 ||
                    abs(control.frame.midY - element.frame.midY) > 1)
        } ?? false

        if aimsElsewhere, let control {
            // Settle (temporal) before re-resolving to aim (spatial) — aiming from an
            // in-flight frame reintroduces the miss through the side door.
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            let target = taggedControl(hint: .interactive) ?? control

            // The premise can evaporate during that settle: dispatches were measured whose
            // computed coordinate equaled the tag's own midpoint — the disagreement that
            // justified the coordinate path was gone by dispatch time, and the element
            // path's built-in quiescence waiting had been forfeited for nothing. Re-check —
            // but reroute ONLY onto a path that actually exists: a native tap needs a
            // hittable element (measured: an element-anchored coordinate tap on the
            // non-hittable tag overlay dispatched and fired nothing, where this aimed
            // dispatch was green).
            let premiseGone =
                abs(target.frame.midX - element.frame.midX) <= 1 &&
                abs(target.frame.midY - element.frame.midY) <= 1

            if premiseGone, element.isHittable {
                element.tap()
                return
            }

            let centre = CGPoint(x: target.frame.midX, y: target.frame.midY)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: centre.x, dy: centre.y))
                .tap()
            return
        }

        if element.isHittable {
            element.tap()
        } else if isOnScreen(element) {
            // A not-hittable element is often one SwiftUI is still presenting, and a coordinate
            // computed from an in-flight frame taps where the element *was*. On timeout the tap
            // still goes to the last-known frame — a frame that never settles (a repeating
            // animation) must not become a new failure mode — under a budget deliberately
            // shorter than waitForStableFrame's default so it stalls a tap by ~2s, not 10s.
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            // Off screen: left to tap(), which reports it, rather than tapping nothing.
            element.tap()
        }
    }

    // Two consecutive agreeing samples ~150ms apart is the settled criterion the design
    // validated in the field; the ~2s budget is the coordinate branch's cap on a frame
    // that never settles.
    private static let settleSamplingInterval: TimeInterval = 0.15
    private static let coordinateSettleBudget: TimeInterval = 2
    private static let selectionCommitBudget: TimeInterval = 4
    private static let textCommitBudget: TimeInterval = 4
    private static let focusProofBudget: TimeInterval = 2

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

    /// Types text into the tagged view, appending at the caret
    ///
    /// The view is given keyboard focus and then receives the text:
    ///
    /// ```swift
    /// app.uiTestingElement("nameField").type("Fern")
    /// ```
    ///
    /// The field is waited for, as it is for ``tap()``. What the field ends up reading is not
    /// verified — appending has no general answer to "what should the value be now"; it
    /// depends on what the field held and where the caret sat. When the intent is the field
    /// ending up with an exact value, reach for ``setText(_:expecting:)``, which replaces and
    /// verifies.
    ///
    /// - Parameter text: The text to type.
    public func type(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard waitForExistence() else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        // Focus and typing are separate steps: the tag is carried alongside the view rather
        // than on it, so the tagged element never holds keyboard focus itself and typing into
        // it directly fails. Tapping moves focus to the field, after which the application
        // routes typed text to whatever holds it.
        tap(file: file, line: line)

        #if os(iOS)
        // typeText's own no-focus failure is opaque; fail naming the tag instead.
        guard waitForFocus() else {
            XCTFail(
                """
                Tapping "\(identifier)" never established keyboard focus — the tap may have \
                landed on a view that does not accept text.
                """,
                file: file, line: line
            )
            return
        }
        #endif

        app.typeText(text)
    }

    /// Replaces the tagged field's value with `text`, verifying the result
    ///
    /// ```swift
    /// app.uiTestingElement("quantityField").setText("42")
    /// app.uiTestingElement("priceField").setText("45", expecting: "45.00") // formatter-backed
    /// ```
    ///
    /// Resolves the real text control the tag marks — a tag spanning a caption + field row
    /// finds the field — focuses it, replaces the value with no caret or selection
    /// assumptions, and does not return until the field reads back exactly the expected
    /// text. A miss retries the whole sequence once with a different gesture strategy, and
    /// failure is loud: the identifier, the entered text, and what the field actually reads.
    ///
    /// `expecting:` serves fields that normalize what they display — a formatter-backed
    /// field renders "45" as "45.00", and the formatter runs when the entry commits, so
    /// passing `expecting:` also commits the entry (via ``XCUIApplication/dismissKeyboard``)
    /// before verifying. The default expects `text` verbatim and leaves the field focused.
    ///
    /// A field the raised keyboard occludes — behind it, or pushed past the viewport's
    /// bottom — is scrolled clear before any aim, so entering into one field and then the
    /// next needs no scrolling or dismissal in between.
    ///
    /// `SecureField`s are not served: bullets defeat any honest read-back, and the failure
    /// says so rather than mystifying.
    public func setText(
        _ text: String,
        expecting expectedValue: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(iOS)
        guard waitForExistence() else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        let expected = expectedValue ?? text

        _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
        guard let control = taggedControl(hint: .textEntry),
              Self.textEntryTypes.contains(control.elementType) else {
            XCTFail(
                """
                No text control resolved for "\(identifier)". Tag a text field or text view — \
                or a composite containing one — and if the control is buried under sibling \
                views when presented bare, register its view as designed for a scrolling \
                parent: registerTestView(_:scrollable:).
                """,
                file: file, line: line
            )
            return
        }
        guard control.elementType != .secureTextField else {
            XCTFail(
                """
                "\(identifier)" resolves to a SecureField, whose value reads back as bullets — \
                there is no honest way to verify the entry, so setText does not serve \
                SecureFields.
                """,
                file: file, line: line
            )
            return
        }

        // Two gesture strategies, because field evidence shows each reaches fields the other
        // cannot: the framework tap (native when hittable, aimed coordinate otherwise), then
        // a direct coordinate tap at the resolved control's centre.
        for useCoordinate in [false, true] {
            if useCoordinate {
                _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
                guard let focusTarget = taggedControl(hint: .textEntry) else { continue }

                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(
                        dx: focusTarget.frame.midX,
                        dy: focusTarget.frame.midY
                    ))
                    .tap()
            } else {
                tap(file: file, line: line)
            }

            guard waitForFocus() else { continue }

            // Aim only AFTER focus is established: the keyboard's arrival reflows the
            // layout (measured: a vertically centered scene shifts up 147pt), so any frame
            // read before it is stale and every gesture from it lands rows away. The settle
            // waits out that reflow — the same in-flight-frame contract as tap()'s.
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            guard var target = taggedControl(hint: .textEntry) else { continue }

            // A settled frame can still be an occluded one: a scroll parent that does not
            // auto-avoid the keyboard leaves the focused field under it — frame honest and
            // stable (measured: field at y=761 beneath a keyboard topping at 590), every
            // aim from it landing on keys. One native tap on the tagged element rides
            // XCUITest's scroll-to-visible with the keyboard staying up; the band scroll
            // clears what remains.
            if !isAimable(target.frame) {
                xcuiElement.tap()
                _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
                if let fresh = taggedControl(hint: .textEntry) {
                    target = fresh
                }

                scrollIntoBand {
                    if let fresh = taggedControl(hint: .textEntry) {
                        target = fresh
                    }
                    return target.frame
                }
            }

            // Replace without caret arithmetic: a double-tap ON the text selects it and
            // raises the edit menu — the menu is the proof a selection was made. Where the
            // text sits depends on the field's width and alignment (measured: a full-width
            // leading-aligned field has nothing under its midpoint, and the double-tap
            // there selects nothing), so the double-tap probes leading, centre, trailing —
            // stopping the moment a menu rises. "Select All" present means the selection
            // is partial: take it; absent means the whole value is already selected. An
            // empty field has nothing to select, and typing simply inserts.
            if let existing = value, !existing.isEmpty {
                // Over existing text the menu's rise is the arbiter, not geometry: the
                // reported keyboard frame understated occlusion twice (a field below the
                // keyboard's bottom edge, and one 15pt above its reported top — both swept
                // menuless while typing appended). A menuless sweep is occlusion evidence:
                // one stroke away from the keyboard, re-resolve, re-probe. Typing over an
                // unproven selection appends — never fall through to it.
                var selectionProven = false
                for retry in 0..<2 {
                    let inset = min(20, target.frame.width / 4)

                    for x in [target.frame.minX + inset, target.frame.midX, target.frame.maxX - inset] {
                        app.coordinate(withNormalizedOffset: .zero)
                            .withOffset(CGVector(dx: x, dy: target.frame.midY))
                            .doubleTap()

                        guard app.menuItems.firstMatch.waitForExistence(timeout: 1) else { continue }

                        let selectAll = app.menuItems["Select All"]
                        if selectAll.exists {
                            selectAll.tap()
                        }
                        selectionProven = true
                        break
                    }
                    if selectionProven {
                        break
                    }

                    if retry == 0 {
                        dragWithinBand(raisingTarget: true)
                        if let fresh = taggedControl(hint: .textEntry) {
                            target = fresh
                        }
                    }
                }
                guard selectionProven else { continue }
            }
            app.typeText(text)

            // A declared normalization runs when the entry commits, so commit before
            // verifying; the verbatim default leaves the field focused. Committing means
            // Return — a formatter-backed TextField parses on submit and DISCARDS the entry
            // on plain focus loss (measured: dismissing reverted "45" to "0.00") — with
            // dismissal only for keyboards that have no Return key at all (.numberPad).
            if expectedValue != nil {
                // The element-subscript match (identifier "Return", measured) is the form
                // that resolves; a compound IN-predicate over the same attributes came back
                // empty against the identical keyboard.
                let returnKey = app.keyboards.buttons["Return"]
                if returnKey.exists {
                    returnKey.tap()
                } else {
                    app.dismissKeyboard(file: file, line: line)
                }
            }

            let deadline = Date(timeIntervalSinceNow: Self.textCommitBudget)
            while Date() < deadline {
                if value == expected {
                    return
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: Self.settleSamplingInterval))
            }
        }

        XCTFail(
            """
            The field tagged "\(identifier)" reads "\(value ?? "nil")" after attempting to \
            enter "\(text)"; expected "\(expected)". A formatter-backed field normalizes its \
            value when the entry commits — pass expecting: with the field's rendering \
            ("45" → expecting: "45.00"). An unchanged value can also mean no selection was \
            ever proven: the edit menu never rose over the field's text.
            """,
            file: file, line: line
        )
        #else
        XCTFail(
            """
            setText(_:expecting:) is not yet certified on this platform — its focus proof and \
            replace mechanics are pinned by fixture on iOS only. Use type(_:) with an explicit \
            clear, or bring the platform evidence to FOSUtilities.
            """,
            file: file, line: line
        )
        #endif
    }

    /// Focus proof: the software keyboard arriving, or any element reporting keyboard focus.
    /// The keyboard is waited for natively and first — the focused-element scan walks the
    /// whole tree (expensive enough to eat a polling budget on its own; measured burning the
    /// focus window on a scene of six fields) and serves only the simulator-with-hardware-
    /// keyboard case, so it runs once, as the fallback.
    private func waitForFocus() -> Bool {
        if app.keyboards.firstMatch.waitForExistence(timeout: Self.focusProofBudget) {
            return true
        }

        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch.exists
    }

    init(app: XCUIApplication, identifier: String) {
        self.app = app
        self.identifier = identifier
    }
}

// MARK: Aimable-band occlusion guard

#if os(iOS)
private extension UITestingElement {
    /// The accessory/input-assistant bar sits above the keyboard's reported frame and
    /// intercepts aims that clear the reported top (measured: an aim 15pt above it raised
    /// no edit menu); the band demands this much clearance above the keyboard.
    private static let keyboardClearance: CGFloat = 44
    /// Stroke endpoints stay inside the band: below the system chrome at the top, above
    /// the home indicator at the bottom.
    private static let bandTopInset: CGFloat = 100
    private static let bandBottomInset: CGFloat = 20
    private static let bandScrollAttempts = 6

    // swiftformat:disable docComments
    // The aimable band: the app frame clipped at the keyboard's top edge, less clearance.
    // One predicate for both occlusion geometries — a target behind the keyboard and one
    // beyond the viewport bottom are equally dead to every gesture, and a settled frame
    // says nothing about either (the frame is honest and stable precisely because nothing
    // moves). Keyboard-frame reads stay behind `exists`: resolving .frame on a
    // non-existent firstMatch fails the test hard rather than returning a degenerate rect.
    // swiftformat:enable docComments
    private func aimableBand() -> CGRect {
        var band = app.frame
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            band.size.height = max(0, keyboard.frame.minY - Self.keyboardClearance - band.origin.y)
        }

        return band
    }

    private func isAimable(_ frame: CGRect) -> Bool {
        // The band narrows only under a raised keyboard; without one there is no occlusion
        // evidence, and every pre-existing aim path must stay untouched — the guard firing
        // keyboardless was measured scrolling an open menu and failing rows that had left
        // the tree.
        guard app.keyboards.firstMatch.exists else { return true }

        let band = aimableBand()

        return band.contains(CGPoint(x: frame.midX, y: frame.midY)) && frame.maxY <= band.maxY
    }

    // swiftformat:disable docComments
    // One scroll stroke whose endpoints derive from the band, not the screen: fixed
    // offsets undershoot on short screens (measured: three fixed strokes left a target
    // 190pt outside the band), and a normalized start point drifts onto the keyboard as
    // device height shrinks. Dragging raises the target when the stroke runs bottom→top.
    // swiftformat:enable docComments
    private func dragWithinBand(raisingTarget: Bool) {
        let band = aimableBand()
        let topY = band.minY + Self.bandTopInset
        let bottomY = max(topY + 40, band.maxY - Self.bandBottomInset)
        let fromY = raisingTarget ? bottomY : topY
        let toY = raisingTarget ? topY : bottomY

        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: band.midX, dy: fromY))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: band.midX, dy: toY))
            )
        _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
    }

    // swiftformat:disable docComments
    // Scrolls the target into the aimable band, band membership as the arbiter, bounded.
    // frame() re-reads the target each attempt — the scroll is what moves it.
    // swiftformat:enable docComments
    private func scrollIntoBand(of frame: () -> CGRect) {
        var attempts = 0
        while attempts < Self.bandScrollAttempts, !isAimable(frame()) {
            dragWithinBand(raisingTarget: frame().midY > aimableBand().midY)
            attempts += 1
        }
    }
}
#endif

// MARK: Verified Picker selection

public extension UITestingElement {
    /// Selects an item in a `Picker` and does not return until the selection committed
    ///
    /// ```swift
    /// app.uiTestingElement("programPicker").selectPickerItem("optionB")
    ///
    /// XCTAssertFalse(app.uiTestingElement("saveButton").isEnabled) // no wait needed
    /// ```
    ///
    /// `self` is the tagged `Picker`; `itemIdentifier` is the `uiTestingIdentifier` of the
    /// item inside the Picker's content. Opening the menu, waiting out its presentation,
    /// tapping the item, and verifying the collapsed control reports the selection are all
    /// internal — any state SwiftUI derives from the selection is committed by the time this
    /// returns, so the very next read is safe without a wait. A missed gesture is retried
    /// once and re-verified; the retry cannot mask a wrong selection because the
    /// postcondition, not the tap, is what lets this return.
    ///
    /// Serves `Picker` only: a `Menu` of action buttons has no selection to verify — drive
    /// one with ``tap()`` and assert the action's effect instead. An item clipped behind a
    /// long menu's internal scroll is reached by scrolling within the presented menu, bounded
    /// in both directions from the checked item — the postcondition, not any gesture, is
    /// still what lets this return.
    func selectPickerItem(
        _ itemIdentifier: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(iOS)
        var itemAppeared = false

        for _ in 0..<2 {
            // tap() settles the menu opener; the item row, mid-presentation, is settled by
            // its own tap() below. A retried attempt re-opens the menu the same way — if the
            // failed attempt left it open, this tap lands on the presented menu's scrim and
            // closes it, and the attempt burns; bounded, and the postcondition stays honest.
            tap(file: file, line: line)

            let item = app.uiTestingElement(itemIdentifier)
            guard item.waitForExistence() else { continue }
            itemAppeared = true

            item.tap(file: file, line: line)

            if selectionCommitted(itemIdentifier) {
                return
            }
        }

        // The fold: a menu longer than its presented card clips rows behind the menu's
        // internal scroll, but the accessibility tree keeps reporting the clipped rows with
        // on-screen frames at the positions they would occupy — every frame-based visibility
        // signal passes and the plain tap above lands on the scrim, dismissing the menu
        // without selecting. Rows clipped deep enough leave the tree entirely. What is
        // honest here, measured on the overflow fixture: a menu row's isHittable, and
        // app-level flings, which scroll the open menu without dismissing it or committing
        // a selection. (Element-scoped swipes on rows can commit one — never swipe those.)
        for _ in 0..<2 {
            // Re-opening re-anchors the menu's scroll at the checked item, so each attempt
            // scans from a known origin: up-leg first (tail clipped below the anchor), then
            // a doubled down-leg that undoes the up-leg and reaches above the anchor.
            tap(file: file, line: line)

            let item = app.uiTestingElement(itemIdentifier)
            var tapped = false
            for step in 0..<(Self.menuSwipesPerDirection * 3) {
                if item.exists, item.xcuiElement.isHittable {
                    itemAppeared = true
                    item.tap(file: file, line: line)
                    tapped = true
                    break
                }
                if step < Self.menuSwipesPerDirection {
                    app.swipeUp()
                } else {
                    app.swipeDown()
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: Self.menuScrollSettle))
            }

            // isHittable steered the scan; it does not gate the tap. If the hint never
            // fired but the row exists, tap() decides how to reach it — the postcondition
            // cannot be fooled either way.
            if !tapped, item.exists {
                itemAppeared = true
                item.tap(file: file, line: line)
            }

            if selectionCommitted(itemIdentifier) {
                return
            }
        }

        XCTFail(
            itemAppeared
                ? """
                The control tagged "\(identifier)" never reported "\(itemIdentifier)" as its \
                selection, including after scrolling within the presented menu \
                (\(Self.menuSwipesPerDirection) flings in each direction from the checked \
                item — a deeper item is out of this API's bounded reach). If the tagged view \
                is a Menu of action buttons rather than a Picker, this API cannot verify it — \
                a Menu has no selection; drive it with tap() and assert the action's effect \
                instead.
                """
                : """
                No item tagged "\(itemIdentifier)" appeared in the menu presented by \
                "\(identifier)", including after scrolling within the presented menu \
                (\(Self.menuSwipesPerDirection) flings in each direction from the checked \
                item). Check the uiTestingIdentifier on the Picker's items.
                """,
            file: file, line: line
        )
        #else
        XCTFail(
            """
            selectPickerItem(_:) is not yet certified on this platform — its selection-commit \
            signal is pinned by fixture on iOS only. Drive the picker with tap() and assert \
            the selection's effect, or bring the platform evidence to FOSUtilities.
            """,
            file: file, line: line
        )
        #endif
    }
}

#if os(iOS)
private extension UITestingElement {
    // One app-level fling scrolls a menu's list by roughly a card height (~12 rows measured);
    // two per direction reaches ~24 rows past the checked anchor, and the down leg doubles to
    // first undo the up leg. Deeper menus fail loudly through the fold-teaching message.
    static let menuSwipesPerDirection = 2
    static let menuScrollSettle: TimeInterval = 0.4

    // swiftformat:disable docComments
    // The commit signal, pinned by fixture: the collapsed Picker's native control carries
    // the selected item's tag as its identifier.
    // swiftformat:enable docComments
    func selectionCommitted(_ itemIdentifier: String) -> Bool {
        let deadline = Date(timeIntervalSinceNow: Self.selectionCommitBudget)
        while Date() < deadline {
            if taggedControl()?.identifier == itemIdentifier {
                return true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: Self.settleSamplingInterval))
        }
        return false
    }
}
#endif

// MARK: Verified Toggle flipping

public extension UITestingElement {
    /// Sets a `Toggle` and does not return until the switch reports the state
    ///
    /// ```swift
    /// app.uiTestingElement("notificationsToggle").setToggle(true)
    ///
    /// XCTAssertTrue(app.uiTestingElement("saveButton").isEnabled) // no wait needed
    /// ```
    ///
    /// A `Toggle` with a leading label exposes one accessibility element spanning label and
    /// switch, so a midpoint tap — XCUITest's default aim — lands beside the switch and
    /// flips nothing. `setToggle` aims at the switch itself, verifies the reported state
    /// before returning, and retries a missed gesture — the reported state, not the tap, is
    /// what lets it return, so a retry can never mask a wrong flip. A `Toggle` already in
    /// the requested state is a verified no-op, so the call is idempotent.
    ///
    /// Any state SwiftUI derives from the flip is committed by the time this returns, so
    /// the very next read is safe without a wait.
    func setToggle(
        _ on: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(iOS)
        guard waitForExistence() else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        let target = on ? "1" : "0"
        if switchState() == target {
            return
        }

        // Two proven aims, measured on the leading-label fixture: the switch element's own
        // tap() lands on its activation point (the knob) even when the element spans the
        // whole row; the trailing-edge coordinate is the fallback for a switch the query
        // cannot resolve. Midpoint coordinates are exactly the miss this API exists to fix.
        for attempt in 0..<3 {
            if attempt < 2, let control = resolvedSwitch() {
                control.tap()
            } else {
                _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
                xcuiElement.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }

            let deadline = Date(timeIntervalSinceNow: Self.toggleCommitBudget)
            while Date() < deadline {
                if switchState() == target {
                    return
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: Self.settleSamplingInterval))
            }
        }

        let lastRead = switchState().map { $0 == "1" ? "on" : "off" } ?? "no switch resolved"
        XCTFail(
            """
            The switch tagged "\(identifier)" never reported \(on ? "on" : "off") \
            (last read: \(lastRead)). Check that the Toggle is enabled and not covered; \
            if the tagged view is not a Toggle, this API cannot verify it.
            """,
            file: file, line: line
        )
        #else
        XCTFail(
            """
            setToggle(_:) is not yet certified on this platform — its aim and state signal \
            are pinned by fixture on iOS only. Drive the toggle with tap() and assert the \
            state's effect, or bring the platform evidence to FOSUtilities.
            """,
            file: file, line: line
        )
        #endif
    }
}

#if os(iOS)
private extension UITestingElement {
    static let toggleCommitBudget: TimeInterval = 4

    // swiftformat:disable docComments
    // Stage-2 philosophy on the switch axis: the first switch whose own centre lies within
    // the tag's bounds — containment of the candidate's centre keeps a scrim or unrelated
    // switch from qualifying. A leading-label Toggle exposes two (the merged row and the
    // knob); document order answers with the merged row, whose native tap is the proven aim.
    // swiftformat:enable docComments
    func resolvedSwitch() -> XCUIElement? {
        let bounds = xcuiElement.frame
        let switches = app.switches
        for index in 0..<switches.count {
            let candidate = switches.element(boundBy: index)
            let frame = candidate.frame
            if bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return candidate
            }
        }
        return nil
    }

    func switchState() -> String? {
        resolvedSwitch()?.value as? String
    }
}
#endif
#endif
