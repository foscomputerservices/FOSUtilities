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
import FOSMVVM
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

// 368 lines against a 350 limit. Splitting the text-entry group (type/setText/
// waitForFocus) into an extension clears it mechanically — worth doing next time
// this file is open, rather than as drive-by churn under an unrelated change.
// swiftlint:disable type_body_length

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
    ///
    /// > Note: Text that appears *beside* the control inside the tag does not become the
    /// reading — a validation message rendered under a failing field leaves the field the one
    /// that answers, so a test can still read what it typed and correct it.
    public var label: String {
        let control = taggedControl()
        let label = control?.label ?? xcuiElement.label
        guard label.isEmpty else { return label }

        // AppKit carries a static text's string as its value, UIKit as its label. Only the
        // otherwise-empty answer falls through, so no control that has a label is affected.
        return (control?.value ?? xcuiElement.value) as? String ?? ""
    }

    /// What the tagged control currently holds
    ///
    /// ```swift
    /// let amount = app.uiTestingElement("amountField")
    /// amount.setText("42")
    ///
    /// XCTAssertEqual(amount.value, "42")
    /// ```
    ///
    /// This is what the control *holds* — a field's text, a slider's position — where
    /// ``label`` is what it is *called*.  Reach for it to prove an entry arrived, or that a
    /// screen presented the value it was given.
    ///
    /// A control that holds nothing answers `nil`, and so does a view that is not a control
    /// at all — a caption reads through ``label``.
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

    /// Which control a resolution is looking for. Every resolution — a read as much as a
    /// gesture — wants the tag's control, so stage 2 may reject a stage-1 winner that is not
    /// one: a StaticText is neither a tap's target nor the reading of the field beside it.
    private enum ResolutionTarget {
        case control
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
    // tag's centre with the closest frame. A match that shares the tag's frame is the tagged
    // view itself — a Text, an Image, or a bare control — and resolution stops there. A tag
    // spanning a composite row defeats it — the centre can fall in the gap between caption
    // and field (no leaf contains it; the row's container wins with the same midpoint), or
    // inside the caption (measured 7pt from that gap). Stage 2 fires when stage 1 answers
    // with a container, or with an element the target rules out, and takes the first element in document order of an accepted type whose own
    // centre lies within the tag's bounds — stage 1 inverted: it asked who contains the tag's
    // centre; stage 2 asks whose centre the tag contains, which is what keeps a scrim or
    // full-screen overlay, which merely intersects, from qualifying. Stage 1's answer stands
    // when nothing does.
    //
    // Reads take the same two stages as gestures, and must: a tag that grows to enclose a
    // validation footnote puts a labelled StaticText under its centre, so a read stopping at
    // stage 1 answers with the footnote while `setText` types into the field — measured as a
    // field that could never be corrected once it had failed. A tag holding no control at all
    // still reads as itself; stage 2 finds nothing and stage 1's answer stands.
    //
    // Children are walked in document order so that a repeated identifier resolves to the same
    // element `xcuiElement` returns, which takes XCUITest's `firstMatch`; document order also
    // picks among several controls under one tag.
    // swiftformat:enable docComments
    private func taggedControl(seeking target: ResolutionTarget = .control) -> XCUIElementSnapshot? {
        guard let root = try? app.snapshot() else { return nil }

        var elements: [XCUIElementSnapshot] = []
        var pending = [root]
        while let next = pending.popLast() {
            elements.append(next)
            pending.append(contentsOf: next.children.reversed())
        }

        guard let tag = elements.first(where: { $0.identifier == identifier }) else { return nil }

        // A control tagged directly holds its own state. An `.other` tag does not, whether it
        // is the `View` tag beside the view or a wrapper that mirrors the view's label (a
        // toolbar item's hosting element carries the identifier and the label, but not the
        // Disabled trait): both resolve to the view sharing their frame.
        guard tag.elementType == .other else {
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

        // A match sharing the tag's frame IS the tagged view — a `Text`, an `Image`, or the
        // control a wrapper mirrors — and stage 2 must not look past it: anything behind a
        // popup whose centre falls inside the frame would otherwise win (measured: a list row
        // behind a sheet answering `label` for the sheet's own text). A frame that differs is
        // a composite, and the descent below applies. A labelled wrapper that resolves nothing
        // this way still reads as itself.
        if let match, Self.sharesFrame(match.frame, bounds),
           target.acceptedTypes.union(Self.taggedDirectlyTypes).contains(match.elementType) {
            return match
        }
        guard tag.label.isEmpty else {
            return tag
        }

        let descends: Bool = switch match {
        case .none:
            true
        case .some(let match) where match.elementType == .other && match.label.isEmpty:
            true
        case .some(let match) where Self.containerTypes.contains(match.elementType):
            true
        case .some(let match):
            !target.acceptedTypes.contains(match.elementType)
        }

        guard descends else { return match }

        // Enclosed, not merely centred: a composite's control lies within the tag's bounds,
        // while a list row behind a sheet — its centre under the sheet's own text, its width
        // the whole list — does not (measured as that row answering `label` for the text).
        let enclosure = bounds.insetBy(dx: -1, dy: -1)
        let control = elements.first { candidate in
            candidate.identifier != identifier &&
                target.acceptedTypes.contains(candidate.elementType) &&
                enclosure.contains(candidate.frame)
        }

        return control ?? match
    }

    /// Non-interactive views a tag can sit on directly; sharing the tag's frame, they are the
    /// tagged view itself, not a composite to descend from.
    private nonisolated static let taggedDirectlyTypes: Set<XCUIElement.ElementType> = [
        .staticText, .image
    ]

    /// Whether two frames agree within layout rounding (measured: a tagged `Text` and its
    /// tag differ by 0.2pt; a toolbar item's wrapper and its button agree exactly).
    private nonisolated static func sharesFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1 &&
            abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
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

    // swiftformat:disable docComments
    // An app-anchored coordinate that lands on `point` as element frames report it.
    // Element frames are app-origin-relative on iOS (the app frame starts at zero) but
    // SCREEN-relative on macOS, where the app's frame origin is nonzero — anchoring at
    // the app origin and offsetting by raw frame coordinates applies that origin twice,
    // and the synthesized gesture lands off-target, silently (measured: tap() dispatched,
    // no failure raised, and the tapped control's action never fired, while a raw
    // element click on the same control was green). Subtracting the app origin yields
    // the same point on both platforms; on iOS the arithmetic is inert.
    // swiftformat:enable docComments
    private func appCoordinate(at point: CGPoint) -> XCUICoordinate {
        // app.frame.origin is (0,0) on iOS and can be non-finite on macOS (measured:
        // (inf, inf) on 27 beta) — only a finite, nonzero origin participates.
        let origin = app.frame.origin
        let dx = origin.x.isFinite ? point.x - origin.x : point.x
        let dy = origin.y.isFinite ? point.y - origin.y : point.y
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: dx, dy: dy))
    }

    // swiftformat:disable docComments
    // The platform's native pointer gesture. On macOS, tap() synthesizes an event that
    // does not land (measured on 27 beta: a native tap() on the live, hittable, resolved
    // control dispatched and the action never fired, while click() on the same control
    // was green) — every native dispatch goes through the platform verb.
    // swiftformat:enable docComments
    private func nativeTap(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    // swiftformat:disable docComments
    // Resolves a snapshot back to a live element by type and frame — the snapshot has
    // geometry but no gestures, and on macOS a native element tap is the only dispatch
    // that lands (coordinate-synthesized taps fire nothing there, measured on 27 beta).
    // The frame tolerance absorbs sub-point rendering differences between the snapshot
    // pass and the live query.
    // swiftformat:enable docComments
    private func liveElement(matching snapshot: XCUIElementSnapshot) -> XCUIElement? {
        let candidates = app.descendants(matching: snapshot.elementType)
        let frame = snapshot.frame
        for index in 0..<min(candidates.count, 50) {
            let candidate = candidates.element(boundBy: index)
            guard candidate.exists else { continue }
            let cf = candidate.frame
            if abs(cf.midX - frame.midX) <= 1, abs(cf.midY - frame.midY) <= 1 {
                return candidate
            }
        }
        return nil
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
    /// Taps the tagged view and proves the tap landed by the effect it causes,
    /// re-tapping once inside the dropped-first-event window
    ///
    /// ```swift
    /// presentButton.tap(provenBy: { dismissButton.exists })
    /// ```
    ///
    /// A freshly launched app can discard its first synthesized event, so a tap is proven
    /// by the UI change it causes — a view appearing, a transported operations recording
    /// becoming readable — never assumed from dispatch:
    ///
    /// ```swift
    /// addButton.tap(provenBy: { try viewModelOperations().createCardCalled })
    /// ```
    ///
    /// > The witness poll absorbs dispatch-and-transport observability — the moments
    /// > between the synthesized event and its effect becoming readable from the test
    /// > process — never operation behavior. A stub operation records the call
    /// > synchronously; one that "does work" the witness must wait out is being held wrong.
    ///
    /// - Parameters:
    ///   - witness: Returns `true` once the tap's effect is observable.
    ///   - timeout: Total time to prove the tap, in seconds; the single re-tap happens at
    ///     the halfway point.
    /// - Returns: `true` if the witness proved the tap before the timeout elapsed.
    @discardableResult public func tap(
        provenBy witness: () throws -> Bool,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) rethrows -> Bool {
        tap(file: file, line: line)
        if try Self.poll(witness, until: Date(timeIntervalSinceNow: timeout / 2)) {
            return true
        }
        tap(file: file, line: line)
        return try Self.poll(witness, until: Date(timeIntervalSinceNow: timeout / 2))
    }

    private static func poll(
        _ witness: () throws -> Bool,
        until deadline: Date
    ) rethrows -> Bool {
        while Date() < deadline {
            if try witness() {
                return true
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        return try witness()
    }

    public func tap(file: StaticString = #filePath, line: UInt = #line) {
        // Waiting through the public wait keeps one default governing both it and the call site.
        guard waitForExistence() else {
            XCTFail(notFound(identifier), file: file, line: line)
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
        if element.exists, !isAimable(element.frame, hittable: element.isHittable) {
            var last = (frame: element.frame, hittable: element.isHittable)
            scrollIntoBand {
                if element.exists {
                    last = (element.frame, element.isHittable)
                }
                return last
            }
        }
        #endif

        // A tag spanning a composite covers caption and control alike, and the tag's midpoint
        // can miss the control entirely (measured: 1pt into the caption/field gap). The miss
        // is the same whether the tap is native — a hittable overlay's hit point IS the tag
        // midpoint — or a synthesized coordinate, so the aim decision precedes the branch
        // choice: only a resolved control that is genuinely a control, and genuinely
        // elsewhere, redirects the tap.
        let control = taggedControl(seeking: .control)
        let aimsElsewhere = control.map { control in
            Self.interactiveTypes.contains(control.elementType) &&
                (abs(control.frame.midX - element.frame.midX) > 1 ||
                    abs(control.frame.midY - element.frame.midY) > 1)
        } ?? false
        if aimsElsewhere, let control {
            // Settle (temporal) before re-resolving to aim (spatial) — aiming from an
            // in-flight frame reintroduces the miss through the side door.
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            let target = taggedControl(seeking: .control) ?? control

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
                nativeTap(element)
                return
            }

            // The resolved control is a snapshot — geometry, no gestures — so prefer
            // resolving it back to a LIVE element and tapping that natively. On macOS
            // this is the only dispatch that lands: coordinate-synthesized taps —
            // app-anchored and overlay-anchored alike — dispatch without failure and
            // fire nothing (measured on 27 beta via the probe's composite row: "fired 0"
            // both ways, while a native click on the same control was green). On iOS the
            // native tap on the resolved control is equivalent to the aimed coordinate
            // when hittable; when live resolution fails, fall back to the app-anchored
            // dispatch iOS has always measured green (appCoordinate keeps it correct
            // should element frames ever be screen-relative).
            let centre = CGPoint(x: target.frame.midX, y: target.frame.midY)
            guard app.frame.contains(centre) else {
                tapScrollingIntoWindow()
                return
            }
            let live = liveElement(matching: target)
            if let live, live.isHittable {
                nativeTap(live)
            } else {
                appCoordinate(at: centre).tap()
            }
            return
        }

        if element.isHittable {
            nativeTap(element)
        } else if isOnScreen(element) {
            // A not-hittable element is often one SwiftUI is still presenting, and a coordinate
            // computed from an in-flight frame taps where the element *was*. On timeout the tap
            // still goes to the last-known frame — a frame that never settles (a repeating
            // animation) must not become a new failure mode — under a budget deliberately
            // shorter than waitForStableFrame's default so it stalls a tap by ~2s, not 10s.
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            tapScrollingIntoWindow()
        }
    }

    // swiftformat:disable docComments
    // Off screen. XCUITest's native tap would scroll the target in, but then hit-tests it,
    // and which of the tag overlay and the control wins that test depends on the view's
    // shape — measured both ways: the overlay refused over a glass capsule while its field
    // was hittable; the field refused under its overlay in a plain row. Absorbing the
    // refusal was measured to cost a runner relaunch per tap under retryOnFailure, and
    // reading back whether the native tap had fired re-resolved an index-bound query onto
    // another element once a menu had closed. So the framework brings the target into the
    // window with its own strokes and aims one coordinate at the control where it settled:
    // nothing is recorded, and nothing is dispatched twice. A target no stroke moves is
    // handed to the native gesture, which reports it.
    // swiftformat:enable docComments
    private func tapScrollingIntoWindow() {
        let element = xcuiElement
        #if os(iOS)
        if scrollIntoWindow() {
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            let frame = taggedControl(seeking: .control)?.frame ?? element.frame
            appCoordinate(at: CGPoint(x: frame.midX, y: frame.midY)).tap()
            return
        }
        #endif
        nativeTap(element)
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

    /// An instance method, not static, because the hypotheses need `app`: each is true only
    /// of a particular state of the running application, and asking it is the only way to
    /// know that from this process.
    ///
    /// The two hypotheses cannot both fire. A shed toolbar needs a navigation bar in the
    /// tree, which means a navigation parent was declared; the missing-parent hypothesis
    /// fires only when one was not.
    private func notFound(_ identifier: String) -> String {
        let base = "No view is tagged \"\(identifier)\". Check the identifier given to " +
            "uiTestingIdentifier(_:), and that the view is on screen."

        if let shedToolbar = shedToolbarHypothesis(identifier) {
            return base + "\n\n" + shedToolbar
        }

        guard let declared = hostedViewParents(), !declared.contains(.navigation) else {
            return base
        }

        return base + "\n\nThe view under test declares no navigation parent " +
            "(registerTestView(_:designedFor:) omitted .navigation). A control declared in " +
            ".toolbar, or a navigationTitle, is absent from the accessibility tree without " +
            "one — present nowhere, rather than off screen."
    }

    // swiftformat:disable docComments
    // An empty navigation bar under a raised keyboard, which is a signature rather than a
    // guess: the bar is asked whether it still holds anything, and only an entirely empty one
    // answers. Offered conditionally, because the missing target need not be a toolbar item -
    // nothing here can tell what the identifier was meant to name. Measured on iPhone Duo / iOS 27.1, 2026-09-22 — a raised keyboard compresses
    // the window, toolbar items move to a vertical bar along the trailing edge, and an item
    // whose label is text with no icon does not make the move; it leaves the tree, and the
    // navigationTitle leaves with it. The same tree on an iPhone 17 Pro keeps every item and
    // merely shortens the bar, which is why this reaches a reader as a device-shaped surprise
    // with no visible cause.
    // swiftformat:enable docComments
    private func shedToolbarHypothesis(_ identifier: String) -> String? {
        #if os(iOS)
        guard app.keyboards.firstMatch.exists else { return nil }

        let bar = app.navigationBars.firstMatch
        guard bar.exists, bar.buttons.count == 0, bar.staticTexts.count == 0 else { return nil }

        return """
        If "\(identifier)" is a toolbar item, its absence has a measured cause: a software \
        keyboard is up and the navigation bar is in the tree holding nothing at all — no \
        items, no title. On iOS 27.1 a raised keyboard compresses the window, the toolbar's \
        items move to a vertical bar along the trailing edge, and an item whose label is text \
        with no icon is dropped rather than moved. Give the item an icon — \
        Label(_:systemImage:) or Image(systemName:) — and it survives the move; \
        axisBehavior(.horizontalOnly) does not. toolbarVerticalBehavior(.disabled) keeps the \
        bar horizontal instead, at the cost of items collapsing into the overflow menu, where \
        a test has to tap "More" to reach them. Nothing identifying follows an item into that \
        menu — the system rebuilds it as a row carrying its label alone, so neither the tag \
        nor an accessibilityIdentifier applied straight to the control survives (both \
        measured). Match an overflowed item by its label.
        """
        #else
        return nil
        #endif
    }

    // swiftformat:disable docComments
    // The parents testHost() resolved for the view under test, or nil when nothing is under
    // test — a probe driving the application's own tree plants no facts. Absent means "not
    // hosted", never "declared nothing", so the hypothesis above stays silent rather than
    // guessing at a screen the harness never presented.
    // swiftformat:enable docComments
    private func hostedViewParents() -> ProductionParents? {
        let facts = app.descendants(matching: .any)
            .matching(identifier: TestHostFacts.accessibilityIdentifier)
            .firstMatch
        guard facts.exists, let value = facts.value as? String else { return nil }

        return TestHostFacts.parents(from: value)
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
            XCTFail(notFound(identifier), file: file, line: line)
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
    /// > A keyboard reports its own frame but not the input-assistant bar above it, so a
    /// > field can sit clear of the reported keyboard and still be untappable along its
    /// > lower edge. Such a field is aimed at higher up rather than scrolled after, and a
    /// > field with no reachable edge left is reported as a test-log warning naming its
    /// > resting frame.
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
            XCTFail(notFound(identifier), file: file, line: line)
            return
        }

        let expected = expectedValue ?? text

        _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
        guard let control = taggedControl(seeking: .textEntry),
              Self.textEntryTypes.contains(control.elementType) else {
            XCTFail(
                """
                No text control resolved for "\(identifier)". Tag a text field or text view — \
                or a composite containing one — and if the control is buried under sibling \
                views when presented bare, register its view as designed for a scrolling \
                parent: registerTestView(_:designedFor:).
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
                guard let focusTarget = taggedControl(seeking: .textEntry) else { continue }

                appCoordinate(at: CGPoint(
                    x: focusTarget.frame.midX,
                    y: focusTarget.frame.midY
                )).tap()
            } else {
                tap(file: file, line: line)
            }

            guard waitForFocus() else { continue }

            // Aim only AFTER focus is established: the keyboard's arrival reflows the
            // layout (measured: a vertically centered scene shifts up 147pt), so any frame
            // read before it is stale and every gesture from it lands rows away. The settle
            // waits out that reflow — the same in-flight-frame contract as tap()'s.
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            guard var target = taggedControl(seeking: .textEntry) else { continue }

            // A settled frame can still be an occluded one: a scroll parent that does not
            // auto-avoid the keyboard leaves the focused field under it — frame honest and
            // stable (measured: field at y=761 beneath a keyboard topping at 590), every
            // aim from it landing on keys. Two remedies, and the ORDER between them is
            // load-bearing: the band scroll first, the native tap only if it did not land
            // the target.
            //
            // The native tap rides XCUITest's scroll-to-visible with the keyboard staying
            // up, which is why it is here at all — but a native tap on an ALREADY-FOCUSED
            // field disarms every stroke that follows it. Measured on a 466x678 window,
            // identical strokes from an identical resting frame: without the tap a 41pt
            // stroke moved the content 31pt; with it, 41pt and 120pt strokes both moved
            // nothing, six times running. Tapping first spends the scroll budget on a
            // scroll view that can no longer pan.
            //
            // The tag's hittability, not the resolved snapshot's — a snapshot has none, and
            // the tag is the right proxy anyway: a `.searchable` field genuinely lives in the
            // navigation bar and must not be scrolled at, while a field buried under one must.
            if aimY(within: target.frame) == nil {
                scrollIntoBand {
                    if let fresh = taggedControl(seeking: .textEntry) {
                        target = fresh
                    }
                    return (target.frame, xcuiElement.isHittable)
                }

                if aimY(within: target.frame) == nil {
                    xcuiElement.tap()
                    _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
                    if let fresh = taggedControl(seeking: .textEntry) {
                        target = fresh
                    }
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
                    var barred = 0

                    // Clamped into the band, never the raw midpoint: the midpoint of a
                    // field straddling the keyboard's accessory margin is the one point on
                    // it that cannot be tapped.
                    let aimedY = aimY(within: target.frame) ?? target.frame.midY

                    for x in [target.frame.minX + inset, target.frame.midX, target.frame.maxX - inset] {
                        let aim = CGPoint(x: x, y: aimedY)
                        // An aim inside a system bar is not a miss, it is a hazard: the bar
                        // takes the touch, and a navigation bar taking a double-tap resigns
                        // the field's first responder — the keyboard drops, the next probe
                        // finds no focused field, and the run spends its remaining budget
                        // aiming at a scene that no longer exists. Measured as the cascade
                        // behind a "the edit menu never rose" failure whose real cause was
                        // three taps into the navigation bar.
                        guard !barsCover(aim) else {
                            barred += 1
                            continue
                        }

                        appCoordinate(at: aim).doubleTap()

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

                    if barred > 0 {
                        warn(
                            """
                            \(barred) of 3 selection aims at "\(identifier)" fell inside a \
                            system bar and were withheld; the field rests at \(target.frame).
                            """
                        )
                    }

                    if retry == 0 {
                        dragWithinBand(raisingTarget: true)
                        if let fresh = taggedControl(seeking: .textEntry) {
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

// swiftlint:enable type_body_length

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
        var top = app.frame.minY
        var bottom = app.frame.maxY

        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            bottom = min(bottom, keyboard.frame.minY - Self.keyboardClearance)
        }
        // No clearance term for either bar: a keyboard understates its extent by an
        // accessory bar it does not report, while a bar's reported frame IS what it covers.
        if let navBottom = barEdge(app.navigationBars, \.maxY) {
            top = max(top, navBottom)
        }
        if let tabTop = barEdge(app.tabBars, \.minY) {
            bottom = min(bottom, tabTop)
        }

        var band = app.frame
        band.origin.y = top
        band.size.height = max(0, bottom - top)

        return band
    }

    // swiftformat:disable docComments
    // One edge of a system bar, or nil when there is none. An empty frame counts as none:
    // a bar that exists with no extent occludes nothing, and clipping the band to it would
    // collapse the band and strand every target. Reads stay behind `exists` for the reason
    // the keyboard read does — resolving .frame on a non-existent firstMatch fails the test
    // hard rather than returning a degenerate rect.
    // swiftformat:enable docComments
    private func barEdge(_ query: XCUIElementQuery, _ edge: KeyPath<CGRect, CGFloat>) -> CGFloat? {
        let bar = query.firstMatch
        guard bar.exists else { return nil }
        let frame = bar.frame
        guard !frame.isEmpty else { return nil }

        return frame[keyPath: edge]
    }

    // swiftformat:disable docComments
    // Does a system bar cover this point? Asked of the TARGET, never of the screen. Bars are
    // permanent where a keyboard is transient, so "a bar exists" is not occlusion evidence
    // the way "a keyboard is up" is — it is true for every target in every app that has one,
    // including the ones nothing is covering.
    // swiftformat:enable docComments
    private func barsCover(_ point: CGPoint) -> Bool {
        for query in [app.navigationBars, app.tabBars] {
            let bar = query.firstMatch
            if bar.exists, bar.frame.contains(point) {
                return true
            }
        }

        return false
    }

    // swiftformat:disable docComments
    // A non-failing signal. XCTest has no warning primitive, and an activity is the
    // closest thing that reaches both audiences at once: it prints into the xcodebuild
    // console log AND lands in the xcresult activity tree, which is where a post-mortem
    // actually looks.
    // swiftformat:enable docComments
    private func warn(_ message: String) {
        XCTContext.runActivity(named: "WARNING - FOSTestingUI: \(message)") { _ in }
    }

    // swiftformat:disable docComments
    // WHERE to aim at a target, which is not the same question as whether the target can
    // be reached. A target does not have to sit wholly inside the band to be tappable: a
    // field whose bottom edge falls in the keyboard's accessory margin is still perfectly
    // tappable a few points higher, and the aim only has to find text, not the midpoint.
    // Measured on the failure that prompted this: a field at y 374.7-396.7 against a band
    // bottom of 389 overlapped the band by 14.3pt and was reachable the whole time, while
    // whole-frame containment called it occluded and sent six scroll strokes after a
    // target already under the finger.
    //
    // nil means no part of the target is in the band — the case a scroll is actually for.
    // swiftformat:enable docComments
    private func aimY(within frame: CGRect) -> CGFloat? {
        guard app.keyboards.firstMatch.exists else { return frame.midY }

        let usable = frame.intersection(aimableBand())
        guard !usable.isNull, usable.height > 0 else { return nil }

        return usable.midY
    }

    private func isAimable(_ frame: CGRect, hittable: Bool) -> Bool {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        // Two kinds of occlusion evidence, and they are NOT symmetric.
        //
        // A raised keyboard is transient, so its mere presence is evidence and narrows the
        // band for every target. Without one, every pre-existing aim path must stay
        // untouched — the guard firing keyboardless was measured scrolling an open menu and
        // failing rows that had left the tree.
        //
        // A navigation or tab bar is permanent, so its presence proves nothing: it is there
        // for every target in an app that has one, including the ones it does not cover.
        // Only a bar actually covering THIS target is evidence, which is why the question is
        // asked of the midpoint rather than of the app. That keeps the keyboardless
        // regression fixed: a menu row clear of the bars still reports aimable and no
        // scroll is attempted.
        //
        // BOTH bars, not just the bottom one. Clipping only the tab bar was measured
        // scrolling a covered target straight up into the navigation bar, where it was
        // equally unreachable and the band called it aimable.
        // A control that LIVES in a bar is not occluded by it — a toolbar item's midpoint is
        // inside the navigation bar by construction, and no amount of scrolling will move it.
        // Hittability separates the two, and only here: a bar-covered target reports false
        // (measured), while a keyboard-covered one reports true (0.12.7's finding), so this
        // signal is trustworthy for bars and useless for keyboards. Without the distinction a
        // toolbar tap spends the full scroll budget dragging the content it sits above —
        // measured at six futile strokes and 27s for one tap.
        let barOcclusion = !hittable && barsCover(midpoint)
        guard app.keyboards.firstMatch.exists || barOcclusion else { return true }

        let band = aimableBand()

        return band.contains(midpoint) && frame.maxY <= band.maxY
    }

    // swiftformat:disable docComments
    // One scroll stroke whose endpoints derive from the band, not the screen: fixed
    // offsets undershoot on short screens (measured: three fixed strokes left a target
    // 190pt outside the band), and a normalized start point drifts onto the keyboard as
    // device height shrinks. Dragging raises the target when the stroke runs bottom→top.
    //
    // The stroke is deliberately NOT sized to the distance the target must travel. What a
    // stroke moves is set by its release velocity, not its length — measured on a 466x678
    // window at 500px/s: 41pt, 80pt, 120pt and 187pt strokes moved the content 300, 293,
    // 302 and 345pt. Slowing the release to 100px/s does make movement proportional (41pt
    // moved 31), but only for the first stroke: a slow drag over a focused field is taken
    // by text interaction rather than the scroll view, and every stroke after it moves
    // nothing. So the stroke stays a fling, and a target the fling cannot land is reported
    // by scrollIntoBand rather than chased.
    // swiftformat:enable docComments
    private func dragWithinBand(raisingTarget: Bool) {
        let band = aimableBand()
        let topY = band.minY + Self.bandTopInset
        let bottomY = max(topY + 40, band.maxY - Self.bandBottomInset)
        let fromY = raisingTarget ? bottomY : topY
        let toY = raisingTarget ? topY : bottomY

        appCoordinate(at: CGPoint(x: band.midX, y: fromY))
            .press(
                forDuration: 0.05,
                thenDragTo: appCoordinate(at: CGPoint(x: band.midX, y: toY))
            )
        _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
    }

    // swiftformat:disable docComments
    // Scrolls the target into the aimable band, band membership as the arbiter, bounded.
    // frame() re-reads the target each attempt — the scroll is what moves it.
    //
    // The probe after the loop is not bookkeeping: the caller aims at the frame the probe
    // writes, so a budget that drains without one leaves every subsequent aim a stroke
    // behind. Measured consequence — three double-taps into the navigation bar, which
    // dismissed the keyboard and turned one miss into a cascade whose failure message
    // named the wrong mechanism.
    // swiftformat:enable docComments
    private func scrollIntoBand(of probe: () -> (frame: CGRect, hittable: Bool)) {
        var attempts = 0
        var beforeLastStroke: CGRect?

        while attempts < Self.bandScrollAttempts {
            let current = probe()
            guard !isAimable(current.frame, hittable: current.hittable) else { return }

            // A stroke that moved the target nowhere will not move it next time either, so
            // the attempts that remain are spent for nothing. A control that LIVES in a
            // system bar is the standing example — a toolbar item cannot be scrolled out of
            // the bar it is part of — and it was measured burning all six strokes and ~27s
            // per tap whenever a keyboard happened to be raised.
            //
            // Asked of MOVEMENT rather than of what the target IS: telling a bar-resident
            // control apart from one merely hidden behind a bar means trusting hittability
            // in a direction the measurement above establishes for one case only, and a
            // control wrongly judged bar-resident would have its scroll skipped and its tap
            // dispatched into the bar. Nothing moved is a fact; what the target is, is an
            // inference.
            guard current.frame != beforeLastStroke else { return }
            beforeLastStroke = current.frame

            dragWithinBand(raisingTarget: current.frame.midY > aimableBand().midY)
            attempts += 1
        }

        // Warned on the unambiguous case only — no part of the target inside the band.
        // A target that ends up partially inside is one setText can still aim at, and a
        // warning there would cry wolf on the common outcome.
        let settled = probe()
        guard aimY(within: settled.frame) == nil else { return }

        let band = aimableBand()
        warn(
            """
            "\(identifier)" did not reach the aimable band in \(Self.bandScrollAttempts) \
            scroll strokes; it rests at \(settled.frame) against a band of \(band). Aims \
            from here may land outside the target — a control the band cannot reach is \
            usually one the scroll parent cannot move.
            """
        )
    }

    // swiftformat:disable docComments
    // Brings a target beyond the window into the aimable band, the band as arbiter so the
    // target lands clear of the bars, bounded like scrollIntoBand and stopped the same way
    // when a stroke moves nothing. The stroke is the app-level fling, not the band's
    // press-and-drag: a target beyond the window can be a clipped row of an open menu, and
    // the fling scrolls the menu without dismissing it (measured on the overflow fixture)
    // where the press-and-drag from the band's origin dismissed it. Keyboardless by
    // construction — the target's midpoint lies outside the window, which no on-screen menu
    // row's does — so the regression that keeps isAimable keyboard-gated is not in reach.
    // swiftformat:enable docComments
    private func scrollIntoWindow() -> Bool {
        let element = xcuiElement
        var attempts = 0
        var beforeLastStroke: CGRect?

        func inBand() -> Bool? {
            guard element.exists else { return nil }
            let frame = element.frame
            return aimableBand().contains(CGPoint(x: frame.midX, y: frame.midY))
        }

        while attempts < Self.bandScrollAttempts {
            guard element.exists else { return false }
            let frame = element.frame
            if inBand() == true {
                return true
            }
            guard frame != beforeLastStroke else { return false }
            beforeLastStroke = frame

            if frame.midY > aimableBand().midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
            _ = waitForStableFrame(timeout: Self.coordinateSettleBudget)
            attempts += 1
        }

        return inBand() == true
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
            XCTFail(notFound(identifier), file: file, line: line)
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
