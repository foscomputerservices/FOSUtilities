// LocalizableRef.swift
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

import Foundation

/// A reference to a value in the ``LocalizationStore``
public indirect enum LocalizableRef: Hashable, Identifiable, CustomStringConvertible, Sendable {
    /// Points to an `Any` value in the unified LocalizationStore
    ///
    /// The *key* is a '.' separated string that points to a location in the LocalizationStore
    /// that is expected to contain a value.  The *key* **must omit** the locale specification.
    ///
    /// > While the example here shows a value of type String, the value can be any supported
    /// > YAML [node](https://yaml.org/spec/1.2.2/#3211-nodes ).
    ///
    /// ## Example
    ///
    /// Given the following YAML, the *key* to retrieve *value* would be as follows:
    ///
    /// ```swift
    /// let valueKey = LocalizableRef.value(key: "level1.level2.value")
    /// ```
    ///
    /// ```yaml
    /// en:
    ///  level1:
    ///    level2:
    ///      value: 'A Value'
    /// ```
    ///
    /// - Parameters:
    ///   - key: A location in the LocalizationStore that contains `Any`
    case value(key: String)

    /// Points to an `Array[Any]` in the LocalizationStore
    ///
    /// *ref* is expected to point to a YAML [Block Sequence](https://yaml.org/spec/1.2.2/#21-collections) collection.
    /// The *index* parameter then locates the value at that index.
    ///
    /// > While the example here shows a value of type String, the value can be any supported
    /// > YAML [node](https://yaml.org/spec/1.2.2/#3211-nodes ).
    ///
    /// ## Example
    ///
    /// Given the following YAML, the *key* to retrieve 'Value 2' would be as follows:
    ///
    /// ```swift
    /// let value2Key = LocalizableRef.arrayValue(key: "level1.level2", index: 1)
    /// ```
    ///
    /// ```yaml
    /// en:
    ///  level1:
    ///    level2:
    ///      - 'Value 1'
    ///      - 'Value 2'
    ///      - 'Value 3'
    /// ```
    ///
    /// - Parameters:
    ///   - ref: A location in the LocalizationStore that contains a `Array[Any]`
    ///   - index: An index to lookup a value in the arrayValue
    case arrayValue(key: String, index: Int)

    /// Creates a multi-level reference
    ///
    /// ## Example
    ///
    /// ```swift
    /// let keyRef = LocalizableRef.value("level1", "level2", "level3")
    /// ```
    ///
    /// > This override should be used instead of concatenating strings
    ///
    /// - Parameter keys: The multiple level keys
    public static func value(keys: String...) -> Self {
        .value(key: multiLevelKey(keys: keys))
    }

    // MARK: Initialization Methods

    /// Initializes `LocalizableRef` for binding between a View-Model's property and its YAML value
    ///
    /// - Parameters:
    ///   - type: The Swift type of the View-Model
    ///   - parentType: For nested types, the name of the parent type
    ///   - parentKeys: An optional set of paths that that are prepended to *propertyName*
    ///   - propertyName: The base YAML key name that corresponds to the swift property
    ///   - index: An optional index into an arrayValue that is appended to *propertyName*  (0...n-1)
    public init(for type: (some Any).Type, parentType: Any.Type? = nil, parentKeys: String..., propertyName: String, index: Int? = nil) {
        self.init(
            for: type,
            parentType: parentType,
            parentKeys: Array(parentKeys),
            propertyName: propertyName,
            index: index
        )
    }

    /// Initializes `LocalizableRef` for binding between a View-Model's property and its YAML value
    ///
    /// - Parameters:
    ///   - type: The Swift type of the View-Model
    ///   - parentType: For nested types, the name of the parent type
    ///   - parentKeys: An optional set of paths that that are prepended to *propertyName*
    ///   - propertyName: The base YAML key name that corresponds to the swift property
    ///   - index: An optional index into an arrayValue that is appended to *propertyName*  (0...n-1)
    public init(for type: (some Any).Type, parentType: Any.Type? = nil, parentKeys: [String], propertyName: String, index: Int? = nil) {
        let key = Self.key(
            typeName: Self.typeName(for: type),
            parentType: parentType == nil ? nil : Self.typeName(for: parentType!),
            parentKeys: parentKeys,
            propertyName: propertyName
        )

        if let index {
            self = .arrayValue(key: key, index: index)
        } else {
            self = .value(key: key)
        }
    }
}

extension LocalizableRef {
    /// The reference ``LocalizableCase`` resolves *enumCase* through
    ///
    /// A top-level enum's case is keyed `Enum.case`; a nested enum's is keyed by every type that
    /// encloses it, outermost first: `Outer.Inner.Enum.case`.
    init(caseOf enumCase: some Any) {
        let enumType = type(of: enumCase)
        let enclosing = Self.enclosingTypeNames(of: enumType)
        self = .value(key: Self.key(
            typeName: Self.typeName(for: enumType),
            parentType: enclosing.isEmpty ? nil : enclosing.joined(separator: Self.separator),
            propertyName: String(describing: enumCase)
        ))
    }
}

public extension LocalizableRef {
    // MARK: Identifiable Protocol

    var id: String {
        description
    }

    // MARK: CustomStringConvertible Protocol

    var description: String {
        switch self {
        case .value(let key): key
        case .arrayValue(let ref, let index): "\(ref.description)[\(index)]"
        }
    }
}

private extension LocalizableRef {
    static let separator = "."

    private static func multiLevelKey(keys: [String]) -> String {
        keys.filter { !$0.isEmpty }.joined(separator: separator)
    }

    static func key(typeName: String, parentType: String? = nil, parentKeys: [String] = [], propertyName: String) -> String {
        var typePath = typeName

        if let parentType {
            typePath = "\(parentType)\(separator)\(typePath)"
        }

        let parentKeys = parentKeys.filter { !$0.isEmpty }
        if !parentKeys.isEmpty {
            typePath += "\(separator)\(Self.multiLevelKey(keys: parentKeys))"
        }

        return String(
            "\(typePath)\(separator)\(propertyName)"
        )
    }

    static func typeName(for type: Any.Type) -> String {
        let result = String(describing: type)

        // If type isn't generic, then we're done!
        guard let genericIndex = result.firstIndex(of: "<") else {
            return result
        }

        return String(result.prefix(upTo: genericIndex))
    }

    /// The names ``typeName(for:)`` gives the types that enclose *type*, outermost first; empty
    /// for a type declared at module or function scope
    static func enclosingTypeNames(of type: Any.Type) -> [String] {
        // String(reflecting:) yields e.g. "Module.Outer.Parent<Swift.Int>.Kind",
        // "(extension in Module):Module.Parent<Swift.Int>.Kind", or, for private and local
        // types, "Module.(unknown context at $1f2e3d).Parent.Kind"; the dots inside generic
        // arguments and parenthesized contexts are not path separators.
        let reflected = String(reflecting: type)
        var components = [Substring]()
        var depth = 0
        var start = reflected.startIndex
        var previous: Character?
        for index in reflected.indices {
            switch reflected[index] {
            case "<", "(":
                depth += 1
            case ">" where previous != "-", ")":
                depth -= 1
            case "." where depth == 0:
                components.append(reflected[start..<index])
                start = reflected.index(after: index)
            default:
                break
            }
            previous = reflected[index]
        }
        components.append(reflected[start...])

        // The first component is the module, the last is the type itself; a parenthesized
        // context (a private or local scope) roots the path after it
        guard components.count > 2 else {
            return []
        }
        let enclosing = components[1..<(components.count - 1)]
        let path = enclosing.lastIndex { $0.hasPrefix("(") }
            .map { enclosing[enclosing.index(after: $0)...] } ?? enclosing

        return path.map { String($0.prefix { $0 != "<" }) }
    }
}
