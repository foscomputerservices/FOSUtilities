// DeleteTimestampCheck.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

import Fluent
import FluentKit
import FOSMVVM

// swiftformat:disable docComments
// FluentKit answers the same question with `Fields.deletedTimestamp`, but both it and the
// `AnyTimestamp` it returns are internal to FluentKit. `TimestampProperty` and its `trigger` are
// public, so the fact is reachable through a conformance of our own.
// swiftformat:enable docComments
protocol DeleteTimestampCheck {
    var isDeleteTriggered: Bool { get }
}

extension TimestampProperty: DeleteTimestampCheck {
    var isDeleteTriggered: Bool {
        trigger == .delete
    }
}

extension DataModel {
    /// Whether a fresh instance of this model carries a `@Timestamp(on: .delete)` — the column
    /// Fluent marks instead of removing the row, and the precondition an archive route registers
    /// against.
    static var declaresDeleteTimestamp: Bool {
        Self().properties.contains { ($0 as? any DeleteTimestampCheck)?.isDeleteTriggered ?? false }
    }
}
