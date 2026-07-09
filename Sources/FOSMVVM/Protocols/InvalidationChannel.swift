// InvalidationChannel.swift
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

/// One event from the server's live-invalidation stream
///
/// You only meet this type when supplying a custom ``InvalidationChannel``;
/// the default channel produces it for you. Yield `.connected` whenever your
/// transport (re)establishes its connection — FOSMVVM responds by refreshing
/// every live screen — and `.invalidated` with each identity set the server
/// pushes.
public enum InvalidationEvent: Sendable {
    case connected
    case invalidated(Set<ModelIdentity>)
}

/// The transport that delivers server invalidation nudges to this client
///
/// Most apps never touch this: leave ``MVVMEnvironment/invalidationChannel``
/// `nil` and FOSMVVM synthesizes the standard channel over your deployment
/// URLs. Conform your own type only to replace the transport wholesale:
///
/// ```swift
/// struct MyChannel: InvalidationChannel {
///     func events() -> AsyncStream<InvalidationEvent> { ... }
/// }
///
/// let environment = MVVMEnvironment(
///     appBundle: Bundle.main,
///     invalidationChannel: MyChannel(),
///     deploymentURLs: ...
/// )
/// ```
public protocol InvalidationChannel: Sendable {
    func events() -> AsyncStream<InvalidationEvent>
}
