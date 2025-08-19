// ViewModelMacroTests.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

#if os(macOS) || os(Linux) || os(Windows)
import FOSFoundation
import FOSMacros
import Foundation
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class ViewModelMacroTests: XCTestCase {
    private let testMacros: [String: any Macro.Type] = [
        "ViewModel": ViewModelMacro.self
    ]

    func testBlankExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
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

    func testSimpleLocalizedStringExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel {
                @LocalizedString public var name
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                @LocalizedString public var name
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_name.localizationId: "name"]
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

    func testSkipViewModelExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel struct TestViewModel: ViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel: ViewModel {
                var name: String { "TestViewModel" }
                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [:]
                }
            }

            extension TestViewModel: RetrievablePropertyNames {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testComplexLocalizableStringExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel
            struct TestViewModel: RequestableViewModel {
                typealias Request = TestViewModelRequest

                @LocalizedString var aLocalizedString
                @LocalizedString(parentKeys: "aField") var title
                @LocalizedString(parentKeys: "aField", propertyName: "title") var aFieldTitle
                @LocalizedString(parentKeys: "aField", "validationMessages") var error1
                @LocalizedString(parentKeys: "aField", "validationMessages") var error2
                @LocalizedString(propertyName: "pieces", index: 0) var firstPiece
                @LocalizedInt(value: 42) var aLocalizedInt
                @LocalizedStrings var pieces
                @LocalizedString var separator
                @LocalizedCompoundString(pieces: \._pieces) var aLocalizedCompoundNoSep
                @LocalizedCompoundString(pieces: \._pieces, separator: \Self._separator) var aLocalizedCompoundSep

                @LocalizedSubs(substitutions: \.substitutions) var aLocalizedSubstitution
                private let substitutions: [String: LocalizableInt]

                var vmId = ViewModelId()

                public var displayName: LocalizableString { .constant("TestVM") }

                init() {
                    self.substitutions = [
                        "aSub": .init(value: 42)
                    ]
                }

                public static func stub() -> Self {
                    fatalError()
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel: RequestableViewModel {
                typealias Request = TestViewModelRequest

                @LocalizedString var aLocalizedString
                @LocalizedString(parentKeys: "aField") var title
                @LocalizedString(parentKeys: "aField", propertyName: "title") var aFieldTitle
                @LocalizedString(parentKeys: "aField", "validationMessages") var error1
                @LocalizedString(parentKeys: "aField", "validationMessages") var error2
                @LocalizedString(propertyName: "pieces", index: 0) var firstPiece
                @LocalizedInt(value: 42) var aLocalizedInt
                @LocalizedStrings var pieces
                @LocalizedString var separator
                @LocalizedCompoundString(pieces: \._pieces) var aLocalizedCompoundNoSep
                @LocalizedCompoundString(pieces: \._pieces, separator: \Self._separator) var aLocalizedCompoundSep

                @LocalizedSubs(substitutions: \.substitutions) var aLocalizedSubstitution
                private let substitutions: [String: LocalizableInt]

                var vmId = ViewModelId()

                public var displayName: LocalizableString { .constant("TestVM") }

                init() {
                    self.substitutions = [
                        "aSub": .init(value: 42)
                    ]
                }

                public static func stub() -> Self {
                    fatalError()
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_aLocalizedString.localizationId: "aLocalizedString", _title.localizationId: "title", _aFieldTitle.localizationId: "aFieldTitle", _error1.localizationId: "error1", _error2.localizationId: "error2", _firstPiece.localizationId: "firstPiece", _aLocalizedInt.localizationId: "aLocalizedInt", _pieces.localizationId: "pieces", _separator.localizationId: "separator", _aLocalizedCompoundNoSep.localizationId: "aLocalizedCompoundNoSep", _aLocalizedCompoundSep.localizationId: "aLocalizedCompoundSep", _aLocalizedSubstitution.localizationId: "aLocalizedSubstitution"]
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

    func testComplexExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel
            public struct InfoViewModel: RequestableViewModel {
                // MARK: ViewModel Properties

                @LocalizedSubs(substitutions: \.substitutions) public var Title
                private var substitutions: [String: LocalizableString] { [
                    "fred": .constant(fred.string(includeCompanyCode: true))
                ] }

                @LocalizedString public var connectionTitle
                @LocalizedString public var onTitle
                @LocalizedString public var offTitle
                @LocalizedString public var batteryTitle
                @LocalizedString public var connectTitle
                @LocalizedString public var disconnectTitle
                @LocalizedString public var deleteTitle
                @LocalizedString public var errorTitle
                @LocalizedString public var errorMessage
                @LocalizedString public var errorDismissButtonTitle

                public let fred: Fred

                // MARK: RequestableViewModel Protocol

                public typealias Request = InfoViewModelRequest
                public let vmId: ViewModelId

                // MARK: Operations Access

                private let isStub: Bool

                #if canImport(SwiftUI)
                public var operations: any InfoViewModelOperations {
                    isStub ? InfoStubOps() : InfoOps()
                }
                #endif

                // MARK: Initialization

                public init(fred: Fred) {
                    self.init(isStub: false, fred: fred)
                }
            }
            """#,
            expandedSource: #"""
            public struct InfoViewModel: RequestableViewModel {
                // MARK: ViewModel Properties

                @LocalizedSubs(substitutions: \.substitutions) public var Title
                private var substitutions: [String: LocalizableString] { [
                    "fred": .constant(fred.string(includeCompanyCode: true))
                ] }

                @LocalizedString public var connectionTitle
                @LocalizedString public var onTitle
                @LocalizedString public var offTitle
                @LocalizedString public var batteryTitle
                @LocalizedString public var connectTitle
                @LocalizedString public var disconnectTitle
                @LocalizedString public var deleteTitle
                @LocalizedString public var errorTitle
                @LocalizedString public var errorMessage
                @LocalizedString public var errorDismissButtonTitle

                public let fred: Fred

                // MARK: RequestableViewModel Protocol

                public typealias Request = InfoViewModelRequest
                public let vmId: ViewModelId

                // MARK: Operations Access

                private let isStub: Bool

                #if canImport(SwiftUI)
                public var operations: any InfoViewModelOperations {
                    isStub ? InfoStubOps() : InfoOps()
                }
                #endif

                // MARK: Initialization

                public init(fred: Fred) {
                    self.init(isStub: false, fred: fred)
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_Title.localizationId: "Title", _connectionTitle.localizationId: "connectionTitle", _onTitle.localizationId: "onTitle", _offTitle.localizationId: "offTitle", _batteryTitle.localizationId: "batteryTitle", _connectTitle.localizationId: "connectTitle", _disconnectTitle.localizationId: "disconnectTitle", _deleteTitle.localizationId: "deleteTitle", _errorTitle.localizationId: "errorTitle", _errorMessage.localizationId: "errorMessage", _errorDismissButtonTitle.localizationId: "errorDismissButtonTitle"]
                }
            }

            extension InfoViewModel: ViewModel {
            }

            extension InfoViewModel: RetrievablePropertyNames {
            }

            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testSimpleClientFactoryConformanceExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel(options: [.clientHostedFactory]) struct TestViewModel {
                @LocalizedString public var name
                let foo: Int
                let bar: String

                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                init(foo: Int, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel {
                @LocalizedString public var name
                let foo: Int
                let bar: String

                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                init(foo: Int, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }

                public typealias Request = ClientHostedRequest

                public struct AppState: Hashable, Sendable {
                    public let foo: Int
                    public let bar: String

                    public init(foo: Int, bar: String) {
                        self.foo = foo
                        self.bar = bar
                    }
                }

                public final class ClientHostedRequest: ViewModelRequest, @unchecked Sendable {
                    public var responseBody: TestViewModel?
                    public init(
                        query: EmptyQuery?,
                        fragment: EmptyFragment? = nil,
                        requestBody: EmptyBody? = nil,
                        responseBody: TestViewModel?
                    ) {
                        self.responseBody = responseBody
                    }
                }

                public static func model(
                    context: ClientHostedModelFactoryContext<Request, AppState>
                ) async throws -> Self {
                    .init(foo: context.appState.foo, bar: context.appState.bar)
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_name.localizationId: "name"]
                }
            }

            extension TestViewModel: ViewModel {
            }

            extension TestViewModel: RetrievablePropertyNames {
            }

            extension TestViewModel: ClientHostedViewModelFactory, RequestableViewModel {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testVMSpecifiedSpecifiedClientFactoryConformanceExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel(options: [.clientHostedFactory]) struct TestViewModel: ViewModel {
                @LocalizedString public var name
                let foo: Int
                let bar: String

                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                init(foo: Int, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel: ViewModel {
                @LocalizedString public var name
                let foo: Int
                let bar: String

                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                init(foo: Int, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }

                public typealias Request = ClientHostedRequest

                public struct AppState: Hashable, Sendable {
                    public let foo: Int
                    public let bar: String

                    public init(foo: Int, bar: String) {
                        self.foo = foo
                        self.bar = bar
                    }
                }

                public final class ClientHostedRequest: ViewModelRequest, @unchecked Sendable {
                    public var responseBody: TestViewModel?
                    public init(
                        query: EmptyQuery?,
                        fragment: EmptyFragment? = nil,
                        requestBody: EmptyBody? = nil,
                        responseBody: TestViewModel?
                    ) {
                        self.responseBody = responseBody
                    }
                }

                public static func model(
                    context: ClientHostedModelFactoryContext<Request, AppState>
                ) async throws -> Self {
                    .init(foo: context.appState.foo, bar: context.appState.bar)
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_name.localizationId: "name"]
                }
            }

            extension TestViewModel: RetrievablePropertyNames {
            }

            extension TestViewModel: ClientHostedViewModelFactory, RequestableViewModel {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testRequestableSpecifiedClientFactoryConformanceExpansion() throws {
        assertMacroExpansion(
            #"""
            @ViewModel(options: [.clientHostedFactory]) struct TestViewModel: RequestableViewModel {
                @LocalizedString public var name
                let foo: Int
                let bar: String

                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                init(foo: Int, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }
            }
            """#,
            expandedSource: #"""
            struct TestViewModel: RequestableViewModel {
                @LocalizedString public var name
                let foo: Int
                let bar: String

                var vmId: FOSMVVM.ViewModelId = .init()
                static func stub() -> TestViewModel {
                    .init()
                }

                init(foo: Int, bar: String) {
                    self.foo = foo
                    self.bar = bar
                }

                public typealias Request = ClientHostedRequest

                public struct AppState: Hashable, Sendable {
                    public let foo: Int
                    public let bar: String

                    public init(foo: Int, bar: String) {
                        self.foo = foo
                        self.bar = bar
                    }
                }

                public final class ClientHostedRequest: ViewModelRequest, @unchecked Sendable {
                    public var responseBody: TestViewModel?
                    public init(
                        query: EmptyQuery?,
                        fragment: EmptyFragment? = nil,
                        requestBody: EmptyBody? = nil,
                        responseBody: TestViewModel?
                    ) {
                        self.responseBody = responseBody
                    }
                }

                public static func model(
                    context: ClientHostedModelFactoryContext<Request, AppState>
                ) async throws -> Self {
                    .init(foo: context.appState.foo, bar: context.appState.bar)
                }

                public func propertyNames() -> [LocalizableId: String] {
                    [_name.localizationId: "name"]
                }
            }

            extension TestViewModel: ViewModel {
            }

            extension TestViewModel: RetrievablePropertyNames {
            }

            extension TestViewModel: ClientHostedViewModelFactory {
            }
            """#,
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
}
#endif
