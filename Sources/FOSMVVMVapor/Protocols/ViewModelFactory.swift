// ViewModelFactory.swift
//
// Created by David Hunt on 9/4/24
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

#if canImport(Vapor)
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

public struct VaporModelFactoryContext<Request: ViewModelRequest>: ViewModelFactoryContext {
    public let req: Vapor.Request
    public let vmRequest: Request

    public var systemVersion: SystemVersion {
        get throws {
            try req.systemVersion
        }
    }

    public init(req: Vapor.Request, vmRequest: Request) {
        self.req = req
        self.vmRequest = vmRequest
    }
}

public protocol VaporViewModelFactory: ViewModelFactory & Vapor.AsyncResponseEncodable where Self: RequestableViewModel, Context == VaporModelFactoryContext<Request> {}

public extension VaporViewModelFactory {
    static func model(_ req: Vapor.Request, vmRequest: Request) async throws -> Self {
        try await model(context: .init(req: req, vmRequest: vmRequest))
    }
}
#endif
