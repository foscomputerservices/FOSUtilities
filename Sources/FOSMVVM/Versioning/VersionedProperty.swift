// VersionedProperty.swift
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

public extension ViewModel {
    typealias Versioned<VM: ViewModel> = _VersionedProperty<Self, VM>
}

@propertyWrapper public struct _VersionedProperty<Model, Value>: Codable, Sendable, Stubbable, Versionable where Model: ViewModel, Value: Stubbable & Codable & Sendable {
    public var wrappedValue: Value
    public var projectedValue: Value { wrappedValue }

    // MARK: Versionable Protocol

    public var vFirst: SystemVersion
    public var vLast: SystemVersion?

    // MARK: Initialization Methods

    public init(_ wrappedValue: Value? = nil, vFirst: SystemVersion? = nil, vLast: SystemVersion? = nil) {
        self.wrappedValue = wrappedValue ?? .stub()
        self.vFirst = vFirst ?? .vInitial
        self.vLast = vLast
    }
}

public extension _VersionedProperty {
    // MARK: Stubbable Protocol

    static func stub() -> Self {
        fatalError()
    }
}
