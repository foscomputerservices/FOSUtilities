// VersionedViewModel.swift
//
// Created by David Hunt on 12/11/24
// Copyright 2024 FOS Services, LLC
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
import Vapor

extension SystemVersion {
    static var v1_0_0: Self { .vInitial }
    static var v2_0_0: Self { .init(major: 2) }
    static var v2_1_0: Self { .init(major: 2, minor: 1) }
    static var v3_0_0: Self { .init(major: 3) }
}

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

struct P1: ViewModel, ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(_ req: Vapor.Request, vmRequest: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

struct P2: ViewModel, ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(_ req: Vapor.Request, vmRequest: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

struct P3: ViewModel, ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(_ req: Vapor.Request, vmRequest: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

struct P4: ViewModel, ViewModelFactory {
    var vmId: ViewModelId = .init()

    static func model(_ req: Vapor.Request, vmRequest: TestVersionedViewModelRequest) async throws -> Self {
        .stub()
    }

    static func stub() -> Self {
        .init()
    }
}

final class TestVersionedViewModelRequest: ViewModelRequest {
    typealias Query = EmptyQuery
    let responseBody: TestVersionedViewModel?

    init(query: EmptyQuery? = nil, fragment: EmptyFragment? = nil, requestBody: EmptyBody? = nil, responseBody: TestVersionedViewModel? = nil) {
        self.responseBody = responseBody
    }
}

@VersionedFactory
extension TestVersionedViewModel: ViewModelFactory {
    // @VersionedFactory generates conformance to ViewModelFactory
//    public static func model(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
//        let version = try req.systemVersion
//
//        if version >= SystemVersion(major: 3, minor: 0, patch: 0) {
//        return try await model_v3_0_0(req, vmRequest: vmRequest)
//        }
//        if version >= SystemVersion(major: 2, minor: 1, patch: 0) {
//            return try await model_v2_1_0(req, vmRequest: vmRequest)
//        }
//        if version >= SystemVersion(major: 2, minor: 0, patch: 0) {
//            return try await model_v2_0_0(req, vmRequest: vmRequest)
//        }
//        if version >= SystemVersion(major: 1, minor: 0, patch: 0) {
//            return try await model_v1_0_0(req, vmRequest: vmRequest)
//        }
//
//        throw ViewModelFactoryError.versionNotSupported(version.versionString)
//    }

    @Version(.v1_0_0)
    static func model_v1_0_0(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
        try await .init(p1: P1.model(req, vmRequest: vmRequest))
    }

    @Version(.v2_0_0)
    static func model_v2_0_0(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
        try await .init(p2: P2.model(req, vmRequest: vmRequest))
    }

    @Version(.v2_1_0)
    static func model_v2_1_0(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
        try await .init(
            p2: P2.model(req, vmRequest: vmRequest),
            p3: P3.model(req, vmRequest: vmRequest)
        )
    }

    @Version(.v3_0_0)
    static func model_v3_0_0(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
        try await .init(p4: P4.model(req, vmRequest: vmRequest))
    }
}