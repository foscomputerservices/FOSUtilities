// FOSUtilitiesSource.swift
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

/// Where a generated project resolves FOSUtilities from.
///
/// The default, `.release`, pins the release this scaffolder ships with
/// (``Release/version``) and fetches it from GitHub — what every customer
/// project gets. Pass `.localCheckout(url)` to `Emitter.emit(config:into:fosUtilities:)`
/// (or `--fos-utilities-path` to `fosmvvm-bootstrap new`) to resolve
/// FOSUtilities from a checkout on this machine instead:
///
/// ```swift
/// try Emitter.emit(
///     config: config,
///     into: outputDir,
///     fosUtilities: .localCheckout(URL(fileURLWithPath: "/path/to/FOSUtilities"))
/// )
/// ```
///
/// Use `.localCheckout` when developing FOSUtilities itself: the generated
/// project then builds against the framework in that checkout, unreleased
/// changes included. CI verifies every scaffold this way, so a template may
/// use an API the same branch introduces.
///
/// > The checkout must contain FOSUtilities' `Package.swift`; emitting throws
/// > ``EmitterError/fosUtilitiesCheckoutNotFound(_:)`` otherwise.
public enum FOSUtilitiesSource: Equatable, Sendable {
    /// The release-stamped pin, fetched from GitHub. The default.
    case release

    /// The FOSUtilities package rooted at this directory.
    case localCheckout(URL)
}
