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

struct ProbeView: View {
    @State private var taps = 0
    @State private var selection = 0
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

                Toggle("flag", isOn: $flag)
                    .uiTestingIdentifier("flagToggle")

                ColorPicker("color", selection: $color)
                    .uiTestingIdentifier("colorPicker")

                // Tagged container wrapping a sub-view that carries its own tags
                HStack { InnerPanel(selection: $selection) }
                    .uiTestingIdentifier("outerPanel")

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

@main
struct UITestingProbeApp: App {
    var body: some Scene {
        WindowGroup {
            // testHost() is what plants the keyboard-dismissal control the
            // KeyboardDismissalTests ride; the probe never sets the __FOS_ launch environment,
            // so the host presents this view tree unchanged. PROBE_SCENE is the probe's own
            // switch for scenarios that need a different geometry than the main tree.
            Group {
                if ProcessInfo.processInfo.environment["PROBE_SCENE"] == "keyboardShift" {
                    KeyboardShiftProbe()
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
