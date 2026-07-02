// SynthesizedStubWitnessTests.swift
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
import Foundation
import Testing

/// A child ViewModel that provides ONLY a fully-defaulted parameterized `stub(...)`
/// and NO zero-arg `stub()`. It compiles as a `ViewModel` (which requires
/// `Stubbable`) only because the `@ViewModel` macro synthesizes the witness.
@ViewModel
struct StubWitnessViewModel {
    let count: Int
    let label: String

    var vmId = ViewModelId()

    static func stub(count: Int = 8, label: String = "berth") -> Self {
        .init(count: count, label: label)
    }
}

@Suite("Synthesized Stub Witness")
struct SynthesizedStubWitnessTests {
    /// Generic dispatch through `Stubbable` — this only type-checks if the macro
    /// produced a genuine `static func stub() -> Self` witness, and only returns
    /// (rather than infinitely recursing) because the witness forwards to the
    /// parameterized overload with explicit arguments.
    private func makeStub<T: Stubbable>(_: T.Type) -> T {
        T.stub()
    }

    @Test func synthesizedWitnessReturnsDefaultedInstance() {
        let vm = StubWitnessViewModel.stub()
        #expect(vm.count == 8)
        #expect(vm.label == "berth")
    }

    @Test func parameterizedStubStillOverridesDefaults() {
        let vm = StubWitnessViewModel.stub(count: 3)
        #expect(vm.count == 3)
        #expect(vm.label == "berth")
    }

    @Test func witnessSatisfiesStubbableProtocol() {
        let vm = makeStub(StubWitnessViewModel.self)
        #expect(vm.count == 8)
        #expect(vm.label == "berth")
    }
}
