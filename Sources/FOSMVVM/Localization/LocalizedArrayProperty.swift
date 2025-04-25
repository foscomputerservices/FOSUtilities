// LocalizedArrayProperty.swift
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

public enum LocalizedArrayPropertyError: Error, CustomDebugStringConvertible {
    case internalError(_ message: String)

    public var debugDescription: String {
        switch self {
        case .internalError(let message):
            "LocalizedArrayPropertyError: Internal Error: \(message)"
        }
    }
}

public extension ViewModel {
    // NOTE: If something new is added here, ViewModelMacro.knownLocalizedPropertyNames must be updated
    typealias LocalizedStrings = _LocalizedArrayProperty<Self, LocalizableString>
}

@propertyWrapper public struct _LocalizedArrayProperty<Model, Value>: Codable, Sendable, Stubbable where Model: ViewModel, Value: Localizable {
    public var wrappedValue: LocalizableArray<Value>
    public var projectedValue: LocalizableArray<Value> { wrappedValue }

    private typealias WrappedValueBinder = @Sendable (String) -> LocalizableArray<Value>

    public let localizationId: LocalizableId
    private let bindWrappedValue: WrappedValueBinder?

    /// Initializes the ``LocalizedStrings`` property wrapper
    ///
    /// - Parameters:
    ///   - parentKey: If provided, a key that is appended to *propertyName*
    ///   - propertyName: The name of the key to look up in the ``LocalizationStore``
    ///    under the ``ViewModel`` name.  If no value (default: nil) is provided, the name of the property
    ///    that the *PropertyWrapper* is attached to is used.
    ///
    /// - See also: ``LocalizableRef``*.init()*
    public init(parentKey: String? = nil, propertyName: String? = nil) where Value == LocalizableString {
        self.init(
            parentKeys: parentKey == nil ? [] : [parentKey!],
            propertyName: propertyName
        )
    }

    /// Initializes the ``LocalizedStrings`` property wrapper
    ///
    /// - Parameters:
    ///   - parentKeys: If provided, a set of keys that are appended to *propertyName*
    ///   - propertyName: The name of the key to look up in the ``LocalizationStore``
    ///      under the ``ViewModel`` name.  If no value (default: nil) is provided, the name of the property
    ///      that the *PropertyWrapper* is attached to is used.
    ///
    /// - See also: ``LocalizableRef``*.init()*
    public init(parentKeys: String..., propertyName: String? = nil) where Value == LocalizableString {
        self.init(parentKeys: Array(parentKeys), propertyName: propertyName)
    }

    /// Initializes the ``LocalizedStrings`` property wrapper
    ///
    /// - Parameters:
    ///   - parentKeys: If provided, a set of keys that are appended to *propertyName*
    ///   - propertyName: The name of the key to look up in the ``LocalizationStore``
    ///      under the ``ViewModel`` name.  If no value (default: nil) is provided, the name of the property
    ///      that the *PropertyWrapper* is attached to is used.
    ///
    /// - See also: ``LocalizableRef``*.init()*
    public init(parentKeys: [String], propertyName: String? = nil) where Value == LocalizableString {
        // Bound later when propertyName is set, but we need a unique id to look up when
        // binding the propertyName
        self.localizationId = .random(length: 10)
        self.wrappedValue = .empty
        self.bindWrappedValue = { autoPropName in
            let finalPropName: String = if let propertyName, !propertyName.isEmpty {
                propertyName
            } else {
                autoPropName
            }
            return LocalizableArray.localized(.init(
                for: Model.self,
                parentKeys: parentKeys,
                propertyName: finalPropName
            ))
        }
    }
}

public extension _LocalizedArrayProperty {
    // MARK: Codable

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        self.localizationId = .random(length: 10)
        self.wrappedValue = try container.decode(LocalizableArray<Value>.self)
        self.bindWrappedValue = nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bindWrappedValue {
            guard
                let propertyNames = encoder.propertyNameBindings(),
                let propertyName = propertyNames[localizationId]
            else {
                throw LocalizedArrayPropertyError.internalError("\(Self.self): Unable to resolve the property name")
            }

            let wrappedValue = bindWrappedValue(propertyName)
            try container.encode(wrappedValue)
        } else {
            try container.encode(wrappedValue)
        }
    }
}

public extension _LocalizedArrayProperty {
    // MARK: Stubbable Protocol

    static func stub() -> Self {
        fatalError()
    }
}
