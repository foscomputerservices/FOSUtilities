// PushEnvironment.swift
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

import Foundation

/// The APNs environment a device token was issued in
///
/// A token only works in the environment that issued it. Apps signed for development
/// (run from Xcode) receive ``sandbox`` tokens; TestFlight and App Store builds
/// receive ``production`` tokens. Your app states which one it is when it creates its
/// `PushRegistration`, and your register request carries it to your server:
///
/// ```swift
/// #if DEBUG
/// let environment = PushEnvironment.sandbox
/// #else
/// let environment = PushEnvironment.production
/// #endif
/// ```
public enum PushEnvironment: Codable, Hashable, CaseIterable, Sendable {
    /// Apple's development push service, for apps signed for development
    case sandbox

    /// Apple's production push service, for TestFlight and App Store apps
    case production
}
