// Stubbable.swift
//
// Created by David Hunt on 4/5/23
// Copyright 2023 FOS Services, LLC
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

/// Returns a fully initialized instance that can be used for testing purposes
///
/// ## Example
///
/// ```swift
/// struct MyStubbable: Stubbable {
///   let myProperty: String
///
///   static func stub() -> Self {
///     .init(myProperty: "My Property Value")
///   }
/// }
///
/// let stubInstance = MyStubbable.stub()
/// ```
public protocol Stubbable {
    static func stub() -> Self
}