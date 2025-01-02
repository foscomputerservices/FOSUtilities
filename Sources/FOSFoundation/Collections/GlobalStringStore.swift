// GlobalStringStore.swift
//
// Created by David Hunt on 9/11/24
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

/// A thread-safe store for storing global key/value pairs of Strings
public actor GlobalStringStore {
    private var data: [String: String] = [:]

    public static let `default`: GlobalStringStore = .init()

    /// Retrieves a value from the store
    ///
    /// - Parameter key: The key that identifies the value to retrieve
    /// - Returns: The corresponding value, or nil if no value exists in the store
    public func getValue(key: String) -> String? {
        data[key]
    }

    /// Stores a value in the store
    ///
    /// - Parameters:
    ///   - key: The key that identifies the value
    ///   - value: The corresponding value
    public func setValue(key: String, value: String) {
        data[key] = value
    }

    /// Removes a value from the store
    ///
    /// If there is no corresponding value, nothing changes
    ///
    /// - Parameter key: The key that identifies the value to retrieve
    public func removeValue(key: String) {
        data.removeValue(forKey: key)
    }
}
