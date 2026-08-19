// ProbeApp.swift
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

import FOSFoundation
import FOSMVVM
import SwiftUI

struct InnerPanel: View {
    @Binding var selection: Int

    var body: some View {
        HStack {
            // A Picker's options carry tags into the menu it presents. The two are tagged
            // on either side of .tag() to cover both orderings.
            Picker("program", selection: $selection) {
                Text(verbatim: "optA").tag(0).uiTestingIdentifier("optionA")
                Text(verbatim: "optB").uiTestingIdentifier("optionB").tag(1)
            }
            .uiTestingIdentifier("innerPicker")
            .pickerStyle(.menu)
        }
        .uiTestingIdentifier("innerPanel")
    }
}

/// A `.numberPad` field on iOS — no Return key, so once a test types here the keyboard stays
/// up until dismissKeyboard() puts it away. Plain text on the other platforms.
struct NumberPadField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        #if os(iOS)
        TextField(title, text: $text)
            .keyboardType(.numberPad)
        #else
        TextField(title, text: $text)
        #endif
    }
}

/// Reproduces keyboard-avoidance displacement: no scroll container, tall filler above a
/// `.numberPad` field near the bottom, so raising the keyboard would cover the focused field
/// and SwiftUI shifts the whole content upward. The dismissal control must stay on screen
/// through that shift — the geometry 0.12.2 got wrong.
struct KeyboardShiftProbe: View {
    @State private var taps = 0
    @State private var amount = ""

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "shift-taps-\(taps)")
                .uiTestingIdentifier("shiftTapCounter")

            Spacer(minLength: 420)

            NumberPadField(title: "amount", text: $amount)
                .textFieldStyle(.roundedBorder)
                .uiTestingIdentifier("shiftAmountField")

            Button(action: { taps += 1 }) { Text(verbatim: "tap me") }
                .uiTestingIdentifier("shiftTapButton")
        }
        .padding()
    }
}

/// Tags spanning caption + field composites, in their own scene so the rows' geometry is
/// deterministic and the main tree's is undisturbed. In gapRow the tag's midpoint falls in
/// the caption/field gap (no leaf contains it); in captionRow it falls inside the caption.
/// First-stage resolution answers with a container, or the caption; the second stage must
/// find the field either way. gapRow's field is deliberately untagged — the row tag is its
/// only route.
struct RowResolutionProbe: View {
    @State private var gapAmount = "45"
    @State private var captionAmount = ""
    @State private var price = 0.0
    @State private var trailing = ""
    @State private var padAmount = "45"
    @State private var secret = ""

    /// Renders at commit time: "45" typed reads back "45.00" once the entry commits —
    /// the normalization setText's expecting: exists for.
    private static let twoDecimals: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                Text(verbatim: "Gap")
                    .frame(width: 80, alignment: .leading)
                Spacer().frame(width: 60)
                TextField("gap amount", text: $gapAmount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            .uiTestingIdentifier("gapRow")

            HStack(spacing: 0) {
                Text(verbatim: "A much longer caption")
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                TextField("caption amount", text: $captionAmount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .uiTestingIdentifier("captionField")
            }
            .uiTestingIdentifier("captionRow")

            // setText's fixture matrix: formatter-backed, trailing-aligned, number pad
            // (prefilled, so replace must select-all on a keyboard with no text menu
            // shortcuts), and a SecureField for the teaching rejection.
            TextField("price", value: $price, formatter: Self.twoDecimals)
                .textFieldStyle(.roundedBorder)
                .uiTestingIdentifier("priceField")

            TextField("trailing", text: $trailing)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .uiTestingIdentifier("trailingField")

            NumberPadField(title: "pad", text: $padAmount)
                .textFieldStyle(.roundedBorder)
                .uiTestingIdentifier("padField")

            SecureField("secret", text: $secret)
                .textFieldStyle(.roundedBorder)
                .uiTestingIdentifier("secretField")
        }
        .padding()
    }
}

/// Two FormFieldViews sharing the owner's `@FocusState`, so a tap in the second blurs the
/// first and drives FormFieldView's focus plumbing (validation-on-blur) — the path under
/// suspicion for SwiftUI's "Accessing FocusState's value outside of the body of a View"
/// runtime warning. The probe asserts nothing about the warning itself; the harness reads
/// the simulator's runtime-issue log around this scene.
struct FormFocusProbe: View {
    @FocusState private var focusedField: FormFieldIdentifier?
    @State private var firstModel = FormFieldModel<String>(
        FormField(
            fieldId: .init(id: "focusProbeFirst"),
            title: .constant("First"),
            type: .text(inputType: .text)
        ),
        default: ""
    )
    @State private var secondModel = FormFieldModel<String>(
        FormField(
            fieldId: .init(id: "focusProbeSecond"),
            title: .constant("Second"),
            type: .text(inputType: .text)
        ),
        default: ""
    )

    /// Text(LocalizableString) requires an installed MVVMEnvironment (its @Environment
    /// subscript traps without one); the titles here are constants, so empty stores serve.
    @State private var mvvmEnv = MVVMEnvironment(
        currentVersion: SystemVersion(major: 1, minor: 0, patch: 0),
        appBundle: Bundle.main,
        deploymentURLs: [.debug: .init(serverBaseURL: URL(string: "http://localhost:8080")!)]
    )

    /// FieldValidationsView (applied by FormFieldView unconditionally) requires an installed
    /// Validations the same way — both are trap-on-missing environment objects.
    @State private var validations = Validations()

    var body: some View {
        Form {
            FormFieldView(fieldModel: firstModel, focusField: $focusedField)
                .uiTestingIdentifier("focusFirstField")
            FormFieldView(fieldModel: secondModel, focusField: $focusedField)
                .uiTestingIdentifier("focusSecondField")
        }
        .environment(mvvmEnv)
        .environment(validations)
    }
}

struct ProbeView: View {
    @State private var taps = 0
    @State private var selection = 0
    @State private var settleSelection = 0
    @State private var overflowSelection = 0
    @State private var name = ""
    @State private var flag = false
    @State private var date = Date(timeIntervalSince1970: 0)
    @State private var color = Color.red
    @State private var showsBanner = false
    @State private var amount = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(verbatim: "taps-\(taps)")
                    .uiTestingIdentifier("tapCounter")

                Button(action: { taps += 1 }) { Text(verbatim: "tap me") }
                    .uiTestingIdentifier("tapButton")

                TextField("name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .uiTestingIdentifier("nameField")

                NumberPadField(title: "amount", text: $amount)
                    .textFieldStyle(.roundedBorder)
                    .uiTestingIdentifier("amountField")

                DatePicker("date", selection: $date, displayedComponents: .date)
                    .uiTestingIdentifier("datePicker")

                // A leading-label Toggle exposes one accessibility element spanning
                // label + switch, so a midpoint tap lands on the label side and flips
                // nothing. The derived label is the postcondition read.
                Text(verbatim: "flag-\(flag ? "on" : "off")")
                    .uiTestingIdentifier("flagStateLabel")
                Toggle("flag", isOn: $flag)
                    .uiTestingIdentifier("flagToggle")

                ColorPicker("color", selection: $color)
                    .uiTestingIdentifier("colorPicker")

                // Tagged container wrapping a sub-view that carries its own tags
                HStack { InnerPanel(selection: $selection) }
                    .uiTestingIdentifier("outerPanel")

                // Frame settling: a menu with enough rows to animate a real presentation.
                // FrameSettlingTests loops open/select against it and allows zero misses.
                Text(verbatim: "settle-sel-\(settleSelection)")
                    .uiTestingIdentifier("settleSelectionLabel")
                Picker("settle", selection: $settleSelection) {
                    ForEach(0..<8, id: \.self) { option in
                        Text(verbatim: "settle-\(option)")
                            .tag(option)
                            .uiTestingIdentifier("settleOption-\(option)")
                    }
                }
                .uiTestingIdentifier("settlePicker")
                .pickerStyle(.menu)

                // In-menu scrolling: more rows than the presented menu's card can show, so
                // part of the list is clipped behind the menu's internal scroll — while the
                // accessibility tree reports clipped rows with on-screen frames at the
                // positions they would occupy, so a midpoint tap lands on the scrim. The
                // menu anchors its scroll at the checked item, so cycling selections moves
                // the clipped region to either side of the anchor.
                Text(verbatim: "overflow-sel-\(overflowSelection)")
                    .uiTestingIdentifier("overflowSelectionLabel")
                Picker("overflow", selection: $overflowSelection) {
                    ForEach(0..<24, id: \.self) { option in
                        Text(verbatim: "overflow-\(option)")
                            .tag(option)
                            .uiTestingIdentifier("overflowOption-\(option)")
                    }
                }
                .uiTestingIdentifier("overflowPicker")
                .pickerStyle(.menu)

                // The tag is applied after other modifiers, which must not matter
                Button(action: {}) { Text(verbatim: "styled") }
                    .padding(2)
                    .frame(width: 140)
                    .uiTestingIdentifier("lateTaggedButton")

                // isEnabled: false leaves the view untagged
                Button(action: {}) { Text(verbatim: "untagged") }
                    .uiTestingIdentifier("disabledTag", isEnabled: false)

                // Existence across a conditional branch
                Button(action: { showsBanner.toggle() }) { Text(verbatim: "toggle") }
                    .uiTestingIdentifier("bannerToggle")
                if showsBanner {
                    Text(verbatim: "saved").uiTestingIdentifier("savedBanner")
                }

                // Disabled control: does the tag reflect enablement?
                Button(action: { taps += 1 }) { Text(verbatim: "disabled") }
                    .disabled(true)
                    .uiTestingIdentifier("disabledButton")

                Button(action: { taps += 1 }) { Text(verbatim: "enabled") }
                    .disabled(false)
                    .uiTestingIdentifier("enabledButton")

                // Tagged with a raw accessibility identifier rather than uiTestingIdentifier:
                // the identifier is on the control itself, so its state must be read from it.
                Button(action: {}) { Text(verbatim: "raw") }
                    .disabled(true)
                    .accessibilityIdentifier("rawTaggedButton")

                // Present in the hierarchy, but off screen
                Spacer().frame(height: 1400)
                Text(verbatim: "far below").uiTestingIdentifier("offscreenLabel")
            }
            .padding()
        }
    }
}

/// A toolbar, which bridges to a native bar item the way a tab bar item does. Three ways of
/// writing a tagged toolbar control sit side by side: our tag on the control inside a
/// `ToolbarItem`, Apple's modifier raw in the same position, and a bare control in the builder
/// with no `ToolbarItem` around it.
struct ToolbarProbe: View {
    @State private var toolbarTaps = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(verbatim: "toolbar-taps-\(toolbarTaps)")
                    .uiTestingIdentifier("toolbarCounter")

                ProbeView()
            }
            .navigationTitle(Text(verbatim: "probe-title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { toolbarTaps += 1 }) { Text(verbatim: "save") }
                        .uiTestingIdentifier("saveToolbarButton")
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: {}) { Text(verbatim: "raw") }
                        .accessibilityIdentifier("rawToolbarButton")
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button(action: {}) { Text(verbatim: "plain") }
                        .uiTestingIdentifier("plainToolbarButton")
                }
            }
        }
    }
}

/// Three ways of writing a tagged tab, side by side: the closure-based initializer and the
/// convenience one, both tagged through TabContent, and a tab whose label carries the View tag
/// instead. A tab bar reaches the accessibility tree later than the views on screen, which is what
/// the tab tests are really about.
///
/// Floors match `TabContent.uiTestingIdentifier`: iOS 27, where Apple starts putting an
/// identifier on a tab bar item, and macOS and visionOS at their own floors.
@available(iOS 27.0, macOS 15.0, visionOS 2.0, *)
struct ProbeTabs: View {
    var body: some View {
        TabView {
            Tab {
                ToolbarProbe()
            } label: {
                Label("probe", systemImage: "1.square")
            }
            .uiTestingIdentifier("probeTab")

            Tab("second", systemImage: "2.square") {
                Text(verbatim: "second-content").uiTestingIdentifier("secondContent")
            }
            .uiTestingIdentifier("secondTab")

            Tab {
                Text(verbatim: "third-content").uiTestingIdentifier("thirdContent")
            } label: {
                Label("third", systemImage: "3.square").uiTestingIdentifier("thirdLabel")
            }
        }
    }
}

/// A card taller than any window: filler above a field and a button row at the bottom.
/// TallCardView registers it scrollable — the harness supplies the scrolling parent the
/// card is designed for; BareCardView registers the default and pins today's bare
/// presentation, where the bottom controls overflow past the window with nothing to scroll.
struct CardContent: View {
    let idPrefix: String
    @State private var amount = ""

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "card-top")
                .uiTestingIdentifier("\(idPrefix)Top")

            Spacer(minLength: 1100)

            TextField("amount", text: $amount)
                .textFieldStyle(.roundedBorder)
                .uiTestingIdentifier("\(idPrefix)Field")

            Button(action: {}) { Text(verbatim: "set") }
                .uiTestingIdentifier("\(idPrefix)Button")
        }
        .padding()
    }
}

/// The composite the 0.12.5 field round proved the scrollable pin never saw, all in one
/// card: its OWN internal `ScrollView` around data sections, the sections rendered only
/// after a tapped async action populates them, an action row BELOW the fields, a
/// transporter behind the card's opaque background, and enough height that the raised
/// keyboard occludes the deeper targets — behind it, beyond the viewport bottom, and at
/// its accessory margin, depending on device height. Registered `scrollable: true`, so
/// the harness supplies the outer scrolling parent that makes all of it reachable.
struct OcclusionCardContent: View {
    @State private var ops = OcclusionCardOps()
    @State private var repaintToggle = false
    @State private var loaded = false
    @State private var alpha = "11"
    @State private var beta = "22"
    @State private var gamma = "33"

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: "occlusion-top")
                .uiTestingIdentifier("occlusionTop")
            Text(verbatim: "load-count-\(ops.loadCount)")
                .uiTestingIdentifier("occlusionLoadCount")

            Button {
                Task { @MainActor in
                    ops.loadCount += 1
                    loaded = true
                    repaintToggle.toggle()
                }
            } label: { Text(verbatim: "load") }
                .uiTestingIdentifier("occlusionLoadButton")

            // The field section sits LOW in the card (the measured client geometry:
            // field at y=761 under a keyboard topping 590): scroll-to-visible brings a
            // field just inside the bottom edge, focus raises the keyboard over it, and
            // every aim from its honest, stable frame lands on the keys.
            Spacer(minLength: 450)

            if loaded {
                ScrollView {
                    VStack(spacing: 40) {
                        TextField("alpha", text: $alpha)
                            .textFieldStyle(.roundedBorder)
                            .uiTestingIdentifier("occlusionAlphaField")

                        TextField("beta", text: $beta)
                            .textFieldStyle(.roundedBorder)
                            .uiTestingIdentifier("occlusionBetaField")

                        TextField("gamma", text: $gamma)
                            .textFieldStyle(.roundedBorder)
                            .uiTestingIdentifier("occlusionGammaField")
                    }
                    .padding(.vertical)
                }
                .frame(height: 420)
            }

            Spacer(minLength: 120)

            Text(verbatim: "set-count-\(ops.setCount)")
                .uiTestingIdentifier("occlusionSetCount")

            Button {
                Task { @MainActor in
                    ops.setCount += 1
                    ops.lastAmount = alpha
                    repaintToggle.toggle()
                }
            } label: { Text(verbatim: "set") }
                .uiTestingIdentifier("occlusionSetButton")
        }
        .padding()
        // Opaque background: the transporter-pruning trigger the field round measured —
        // behind opaque content inside a ScrollView, the transporter left the AX tree.
        .background(Color(white: 0.95))
        .testDataTransporter(viewModelOps: ops, repaintToggle: $repaintToggle)
    }
}

struct OcclusionCardView: ViewModelView {
    let viewModel: OcclusionCardViewModel

    var body: some View {
        OcclusionCardContent()
    }
}

struct TallCardView: ViewModelView {
    let viewModel: TallCardViewModel

    var body: some View {
        CardContent(idPrefix: "scrollCard")
    }
}

struct BareCardView: ViewModelView {
    let viewModel: BareCardViewModel

    var body: some View {
        CardContent(idPrefix: "bareCard")
    }
}

@main
struct UITestingProbeApp: App {
    init() {
        #if DEBUG
        MVVMEnvironment.registerTestView(TallCardView.self, scrollable: true)
        MVVMEnvironment.registerTestView(BareCardView.self)
        MVVMEnvironment.registerTestView(OcclusionCardView.self, scrollable: true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // testHost() is what plants the keyboard-dismissal control the
            // KeyboardDismissalTests ride; the probe never sets the __FOS_ launch environment,
            // so the host presents this view tree unchanged. PROBE_SCENE is the probe's own
            // switch for scenarios that need a different geometry than the main tree.
            Group {
                if ProcessInfo.processInfo.environment["PROBE_SCENE"] == "keyboardShift" {
                    KeyboardShiftProbe()
                } else if ProcessInfo.processInfo.environment["PROBE_SCENE"] == "rowResolution" {
                    RowResolutionProbe()
                } else if ProcessInfo.processInfo.environment["PROBE_SCENE"] == "formFocus" {
                    FormFocusProbe()
                } else if #available(iOS 27.0, macOS 15.0, visionOS 2.0, *) {
                    ProbeTabs()
                } else {
                    ToolbarProbe()
                }
            }
            .testHost()
        }
    }
}
