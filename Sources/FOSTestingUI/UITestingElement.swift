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
    public func tap(file: StaticString = #filePath, line: UInt = #line) {
        // Waiting through the public wait keeps one default governing both it and the call site.
        guard waitForExistence() else {
            XCTFail(Self.notFound(identifier), file: file, line: line)
            return
        }

        let element = xcuiElement

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
            let centre = CGPoint(x: target.frame.midX, y: target.frame.midY)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: centre.x, dy: centre.y))
                .tap()
        } else if element.isHittable {
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
    /// one with ``tap()`` and assert the action's effect instead. An item that exists but
    /// sits scrolled out of the presented menu is not reachable in this version; the failure
    /// names the item so the case is diagnosable.
    public func selectPickerItem(
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

            // The commit signal, pinned by fixture: the collapsed Picker's native control
            // carries the selected item's tag as its identifier.
            let deadline = Date(timeIntervalSinceNow: Self.selectionCommitBudget)
            while Date() < deadline {
                if taggedControl()?.identifier == itemIdentifier {
                    return
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: Self.settleSamplingInterval))
            }
        }

        XCTFail(
            itemAppeared
                ? """
                The control tagged "\(identifier)" never reported "\(itemIdentifier)" as its \
                selection. If the tagged view is a Menu of action buttons rather than a Picker, \
                this API cannot verify it — a Menu has no selection; drive it with tap() and \
                assert the action's effect instead.
                """
                : """
                No item tagged "\(itemIdentifier)" appeared in the menu presented by \
                "\(identifier)". Check the uiTestingIdentifier on the Picker's items, and that \
                the item is not scrolled out of the presented menu — in-menu scrolling is not \
                supported in this version.
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
            guard let target = taggedControl(hint: .textEntry) else { continue }
            let centre = CGPoint(x: target.frame.midX, y: target.frame.midY)

            // Replace without caret arithmetic: a double-tap ON the text selects it and
            // raises the edit menu — the menu is the proof a selection was made. Where the
            // text sits depends on the field's width and alignment (measured: a full-width
            // leading-aligned field has nothing under its midpoint, and the double-tap
            // there selects nothing), so the double-tap probes leading, centre, trailing —
            // stopping the moment a menu rises. "Select All" present means the selection
            // is partial: take it; absent means the whole value is already selected. An
            // empty field has nothing to select, and typing simply inserts.
            if let existing = value, !existing.isEmpty {
                let inset = min(20, target.frame.width / 4)

                for x in [target.frame.minX + inset, centre.x, target.frame.maxX - inset] {
                    app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: x, dy: centre.y))
                        .doubleTap()

                    guard app.menuItems.firstMatch.waitForExistence(timeout: 1) else { continue }

                    let selectAll = app.menuItems["Select All"]
                    if selectAll.exists {
                        selectAll.tap()
                    }
                    break
                }
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
            The field tagged "\(identifier)" reads "\(value ?? "nil")" after entering \
            "\(text)"; expected "\(expected)". A formatter-backed field normalizes its value \
            when the entry commits — pass expecting: with the field's rendering \
            ("45" → expecting: "45.00").
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
#endif
