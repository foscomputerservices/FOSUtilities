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

import FOSFoundation
import Foundation

public enum ViewModelFactoryError: Error, CustomDebugStringConvertible {
    /// The client requested a version of the ``ViewModel`` that is not supported
    case versionNotSupported(_ version: String)

    public var debugDescription: String {
        switch self {
        case .versionNotSupported(let version):
            "ViewModelFactoryError: Unsupported version: \(version)"
        }
    }

    public var localizedDescription: String {
        debugDescription
    }
}

public protocol ViewModelFactoryContext {
    var systemVersion: SystemVersion { get throws }
}

public protocol ViewModelFactory {
    associatedtype Context: ViewModelFactoryContext

    static func model(context: Context) async throws -> Self
}

public struct ClientHostedModelFactoryContext<Request: ViewModelRequest>: ViewModelFactoryContext {
    public let locale: Locale
    public let localizationStore: LocalizationStore
    public let vmRequest: Request

    public var systemVersion: SystemVersion {
        get throws {
            SystemVersion.current
        }
    }

    public init(locale: Locale, localizationStore: LocalizationStore, vmRequest: Request) {
        self.locale = locale
        self.localizationStore = localizationStore
        self.vmRequest = vmRequest
    }
}

public protocol ClientHostedViewModelFactory: ViewModelFactory where Context == ClientHostedModelFactoryContext<Request> {
    associatedtype Request: ViewModelRequest
}

public extension ClientHostedViewModelFactory where Self == Request.ResponseBody {
    static func model(context: ClientHostedModelFactoryContext<Request>, vmRequest: Request) async throws -> Self {
        let model = try await Self.model(context: context)

        // Now localize the model
        let encoder = JSONEncoder.localizingEncoder(
            locale: context.locale,
            localizationStore: context.localizationStore
        )

        return try model
            .toJSON(encoder: encoder)
            .fromJSON()
    }
}
