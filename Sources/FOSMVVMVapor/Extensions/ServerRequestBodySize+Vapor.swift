// ServerRequestBodySize+Vapor.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

import FOSMVVM
import Vapor

public extension ServerRequestBodySize {
    /// Convert to Vapor's ByteCount
    var vaporByteCount: ByteCount {
        // ByteCount.value is Int, but our byteCount is UInt.
        // Clamp to Int.max to avoid overflow (astronomically unlikely in practice)
        let clamped = min(byteCount, UInt(Int.max))
        return ByteCount(value: Int(clamped))
    }
}

extension Optional where Wrapped == ServerRequestBodySize {
    /// Convert to Vapor's HTTPBodyStreamStrategy
    var bodyStreamStrategy: HTTPBodyStreamStrategy {
        switch self {
        case .some(let size):
            .collect(maxSize: size.vaporByteCount)
        case .none:
            .collect
        }
    }
}
