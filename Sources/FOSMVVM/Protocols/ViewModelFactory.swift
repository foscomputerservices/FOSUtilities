// ViewModelFactory.swift
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
import Foundation

public enum ViewModelFactoryError: Error, Codable, CustomDebugStringConvertible {
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

public protocol ViewModelFactoryContext: Sendable {
    /// Returns the *SystemVersion* that the (client) application requested
    var appVersion: SystemVersion { get throws }
}

/// A factory for creating instances of *ViewModel*
public protocol ViewModelFactory where Self: ViewModel {
    associatedtype Context: ViewModelFactoryContext

    /// Creates an instance of *ViewModel*
    static func model(context: Context) async throws -> Self
}

public struct ClientHostedModelFactoryContext<Request: ViewModelRequest, AppState>: ViewModelFactoryContext where AppState: Sendable {
    public let locale: Locale
    public let localizationStore: LocalizationStore
    public let vmRequest: Request
    public let appState: AppState

    public var appVersion: SystemVersion {
        SystemVersion.current
    }

    public init(
        locale: Locale,
        localizationStore: LocalizationStore,
        vmRequest: Request,
        appState: AppState
    ) {
        self.locale = locale
        self.localizationStore = localizationStore
        self.vmRequest = vmRequest
        self.appState = appState
    }
}

public extension ClientHostedModelFactoryContext where AppState == Void {
    init(
        locale: Locale,
        localizationStore: LocalizationStore,
        vmRequest: Request
    ) {
        self.init(
            locale: locale,
            localizationStore: localizationStore,
            vmRequest: vmRequest,
            appState: ()
        )
    }
}

public protocol ClientHostedViewModelFactory: ViewModelFactory where Context == ClientHostedModelFactoryContext<Request, AppState> {
    associatedtype Request: ViewModelRequest
    associatedtype AppState
}

public extension ClientHostedViewModelFactory where Self == Request.ResponseBody, Self.AppState == Void {
    static func model(context: ClientHostedModelFactoryContext<Request, Void>, vmRequest: Request) async throws -> Self {
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

public extension ClientHostedViewModelFactory where Self == Request.ResponseBody {
    static func model(context: ClientHostedModelFactoryContext<Request, AppState>, vmRequest: Request) async throws -> Self where AppState: Sendable {
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
