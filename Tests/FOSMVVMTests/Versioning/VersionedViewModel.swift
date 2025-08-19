// VersionedViewModel.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

extension SystemVersion {
    static var v1_0_0: Self { .vInitial }
    static var v2_0_0: Self { .init(major: 2) }
    static var v2_1_0: Self { .init(major: 2, minor: 1) }
    static var v3_0_0: Self { .init(major: 3) }
}

@ViewModel
struct TestVersionedViewModel: RequestableViewModel {
    typealias Request = TestVersionedViewModelRequest

    @LocalizedString(vFirst: .v1_0_0) var aLocalizedString
    @Versioned(vLast: .v1_0_0) var p1: P1
    @Versioned(vLast: .v2_0_0) var p2: P2
    @Versioned(vLast: .v2_1_0) var p3: P3
    @Versioned(vLast: .v3_0_0) var p4: P4

    let vmId: FOSMVVM.ViewModelId

    // Latest (v3.0.0) initializer
    init() {
        self.vmId = .init()
        self.p2 = p2
        self.p3 = p3
    }

    static func stub() -> TestVersionedViewModel {
        .init()
    }
}

extension TestVersionedViewModel {
    // v1.0.0 Initializer
    init(p1: P1) {
        self.vmId = .init()
        self.p1 = p1
    }

    // v2.0.0 Initializer
    init(p2: P2) {
        self.vmId = .init()
        self.p1 = p1
    }

    // v2.1.0 Initializer
    init(p2: P2, p3: P3) {
        self.vmId = .init()
        self.p1 = p1
    }

    // v3.0.0 Initializer
    init(p4: P4) {
        self.vmId = .init()
        self.p4 = p4
    }
}

@ViewModel
struct P1: ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(context: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

@ViewModel
struct P2: ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(context: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

@ViewModel
struct P3: ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(context: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

@ViewModel
struct P4: ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(context: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

final class TestVersionedViewModelRequest: ViewModelRequest, ViewModelFactoryContext, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    var responseBody: TestVersionedViewModel?

    var systemVersion: SystemVersion {
        get throws {
            .init(major: 3, minor: 0, patch: 0)
        }
    }

    init(query: EmptyQuery? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: TestVersionedViewModel? = nil) {
        self.responseBody = responseBody
    }
}

@VersionedFactory
extension TestVersionedViewModel: ViewModelFactory {
    typealias Context = Request

    // @VersionedFactory generates conformance to ViewModelFactory
//    static func model(context: Request) async throws -> Self {
//        let version = try context.systemVersion
//
//        if version >= SystemVersion(major: 3, minor: 0, patch: 0) {
//        return try await model_v3_0_0(context: context)
//        }
//        if version >= SystemVersion(major: 2, minor: 1, patch: 0) {
//            return try await model_v2_1_0(context: context)
//        }
//        if version >= SystemVersion(major: 2, minor: 0, patch: 0) {
//            return try await model_v2_0_0(context: context)
//        }
//        if version >= SystemVersion(major: 1, minor: 0, patch: 0) {
//            return try await model_v1_0_0(context: context)
//        }
//
//        throw ViewModelFactoryError.versionNotSupported(version.versionString)
//    }

    @Version(.v1_0_0)
    static func model_v1_0_0(context: Context) async throws -> Self {
        try await .init(p1: P1.model(context: context))
    }

    @Version(.v2_0_0)
    static func model_v2_0_0(context: Context) async throws -> Self {
        try await .init(p2: P2.model(context: context))
    }

    @Version(.v2_1_0)
    static func model_v2_1_0(context: Context) async throws -> Self {
        try await .init(
            p2: P2.model(context: context),
            p3: P3.model(context: context)
        )
    }

    @Version(.v3_0_0)
    static func model_v3_0_0(context: Context) async throws -> Self {
        try await .init(p4: P4.model(context: context))
    }
}
