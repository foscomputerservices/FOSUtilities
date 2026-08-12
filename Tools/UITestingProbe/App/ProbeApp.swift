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

struct ProbeView: View {
    @State private var taps = 0
    @State private var selection = 0
    @State private var name = ""
    @State private var flag = false
    @State private var date = Date(timeIntervalSince1970: 0)
    @State private var color = Color.red
    @State private var showsBanner = false

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

@main
struct UITestingProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}
