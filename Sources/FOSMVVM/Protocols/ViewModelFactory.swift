// ViewModelFactory.swift
//
// Created by David Hunt on 9/4/24
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
import Foundation

public enum ViewModelFactoryError: Error {
    /// The client requested a version of the ``ViewModel`` that is not supported
    case versionNotSupported(_ version: String)

    public var localizedDescription: String {
        switch self {
        case .versionNotSupported(let version):
            "Unsupported version: \(version)"
        }
    }
}

public protocol ViewModelFactoryContext {
    var systemVersion: SystemVersion { get throws }
}

public protocol ViewModelFactory {
    associatedtype Context: ViewModelFactoryContext

    static func model(context: Context) async throws -> Self
}

#if canImport(Vapor)
import Vapor

public struct VaporModelFactoryContext<VMRequest: ViewModelRequest>: ViewModelFactoryContext {
    public let req: Vapor.Request
    public let vmRequest: VMRequest

    public var systemVersion: SystemVersion {
        get throws {
            try req.systemVersion
        }
    }

    public init(req: Vapor.Request, vmRequest: VMRequest) {
        self.req = req
        self.vmRequest = vmRequest
    }
}

public protocol VaporViewModelFactory: ViewModelFactory where Context == VaporModelFactoryContext<VMRequest> {
    associatedtype VMRequest: ViewModelRequest
}

public extension VaporViewModelFactory {
    static func model(_ req: Vapor.Request, vmRequest: VMRequest) async throws -> Self {
        try await Self.model(context: .init(req: req, vmRequest: vmRequest))
    }
}
#endif
