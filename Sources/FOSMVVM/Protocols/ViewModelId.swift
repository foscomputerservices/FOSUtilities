// ViewModelId.swift
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

public struct ViewModelId: Codable, Hashable, Comparable, Sendable {
    private let id: String
    private let isRandom: Bool
    private let timestamp: TimeInterval

    public func childId(name: String) -> ViewModelId {
        .init(parent: self, childId: name)
    }

    public init(id: String? = nil) {
        self.id = id ?? String.unique()
        self.isRandom = id == nil
        self.timestamp = Date().timeIntervalSince1970
    }

    public init(id: Int) {
        self.init(id: "\(id)")
    }

    // MARK: Codable Protocol

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decodeIfPresent(String.self, forKey: .id)
        self.isRandom = id == nil
        self.id = id ?? String.unique()
        self.timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if !isRandom {
            try container.encode(id, forKey: .id)
        }
        try container.encode(timestamp, forKey: .timestamp)
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
    }

    // MARK: Equatable

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.timestamp == rhs.timestamp
    }

    // MARK: Comparable

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}

private extension ViewModelId {
    init(parent: ViewModelId, childId: String) {
        self.id = "\(parent.id):\(childId))"
        self.isRandom = false
        self.timestamp = Date().timeIntervalSince1970
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp = "ts"
    }
}
