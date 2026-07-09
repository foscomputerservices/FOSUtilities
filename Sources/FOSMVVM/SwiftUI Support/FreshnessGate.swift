// FreshnessGate.swift
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

/// The monotonic gate that guards a same-request refresh swap (spec §3.3): a newer response
/// replaces the current one, an older one racing in is dropped. Keyed on ``ViewModelId/freshness``
/// (L0's version clock), it applies only where the two ViewModels answer the *same* request —
/// a `query`/`fragment` change is navigation to different data, incomparable, and bypasses it.
enum FreshnessGate {
    /// Whether `incoming` should replace `current`. `nil` current is always accepted (first arrival);
    /// otherwise only a strictly-fresher `incoming` wins — an equal-or-older one (the redundant
    /// self-nudge a client's own write races back to it) is dropped.
    static func shouldReplace<V: ViewModel>(current: V?, with incoming: V) -> Bool {
        guard let current else { return true }
        return incoming.vmId.freshness > current.vmId.freshness
    }
}
