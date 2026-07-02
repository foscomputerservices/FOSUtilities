// ViewModelStubMacroTests.swift
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

#if os(macOS)
import FOSFoundation
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class ViewModelStubMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "ViewModel": ViewModelMacro.self
    ]

    /// When a VM provides a fully-defaulted parameterized `stub(...)` but no
    /// zero-arg `stub()`, the macro synthesizes the `Stubbable` witness, forwarding
    /// each parameter with its default made explicit (so the call binds to the
    /// parameterized overload and never recurses into the witness).
    func testSynthesizesWitnessFromParameterizedStub() {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel {
                let count: Int
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub(count: Int = 8) -> TestViewModel {
                    .init(count: count)
                }
                init(count: Int) {
                    self.count = count
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                let count: Int
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub(count: Int = 8) -> TestViewModel {
                    .init(count: count)
                }
                init(count: Int) {
                    self.count = count
                }

                public static func stub() -> Self {
                    Self.stub(count: 8)
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestViewModel: ViewModel {
            }

            extension TestViewModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    /// A hand-written zero-arg `stub()` already witnesses `Stubbable`; the macro
    /// must NOT emit a second `stub()` (which would be a redeclaration), even when
    /// a parameterized `stub(...)` is also present.
    func testDoesNotClobberExistingZeroArgStub() {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel {
                let count: Int
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .stub(count: 8)
                }
                static func stub(count: Int = 8) -> TestViewModel {
                    .init(count: count)
                }
                init(count: Int) {
                    self.count = count
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                let count: Int
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .stub(count: 8)
                }
                static func stub(count: Int = 8) -> TestViewModel {
                    .init(count: count)
                }
                init(count: Int) {
                    self.count = count
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestViewModel: ViewModel {
            }

            extension TestViewModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    /// When a parameterized `stub(...)` has any non-defaulted parameter, the macro
    /// cannot invent a value, so it synthesizes nothing and lets the normal
    /// `Stubbable` conformance error surface.
    func testDoesNotSynthesizeWhenNotAllParametersDefaulted() {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel {
                let count: Int
                let name: String
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub(count: Int = 8, name: String) -> TestViewModel {
                    .init(count: count, name: name)
                }
                init(count: Int, name: String) {
                    self.count = count
                    self.name = name
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                let count: Int
                let name: String
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub(count: Int = 8, name: String) -> TestViewModel {
                    .init(count: count, name: name)
                }
                init(count: Int, name: String) {
                    self.count = count
                    self.name = name
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestViewModel: ViewModel {
            }

            extension TestViewModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    /// Forwarding transcribes each default expression verbatim and respects labels:
    /// a `_` external label is forwarded positionally, an external label is kept,
    /// and non-literal defaults (an array literal) round-trip unchanged.
    func testForwardsPositionalAndLabeledDefaults() {
        assertMacroExpansion(
            #"""
            @ViewModel struct RowViewModel {
                let berths: [Int]
                let label: String
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub(_ berths: [Int] = [1, 2], named label: String = "row") -> RowViewModel {
                    .init(berths: berths, label: label)
                }
                init(berths: [Int], label: String) {
                    self.berths = berths
                    self.label = label
                }
            }
            """#,
            expandedSource: #"""
            struct RowViewModel {
                let berths: [Int]
                let label: String
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub(_ berths: [Int] = [1, 2], named label: String = "row") -> RowViewModel {
                    .init(berths: berths, label: label)
                }
                init(berths: [Int], label: String) {
                    self.berths = berths
                    self.label = label
                }

                public static func stub() -> Self {
                    Self.stub([1, 2], named: "row")
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension RowViewModel: ViewModel {
            }

            extension RowViewModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
