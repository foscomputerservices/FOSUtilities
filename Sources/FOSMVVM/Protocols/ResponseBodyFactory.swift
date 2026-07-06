// ResponseBodyFactory.swift
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

/// Constructs a request's response value on the server from the records loaded for it.
///
/// Conform the **response body** — the type a request returns — and build it in
/// `body(context:)`:
///
/// ```swift
/// extension BerthListVM: ResponseBodyFactory {
///     static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
///         where R.ResponseBody == Self {
///         BerthListVM(berths: try context.records(Self.berths).map(BerthCell.init))
///     }
/// }
/// ```
///
/// Author it **once** on the body; every request whose `ResponseBody` is this type —
/// the read *and* every write that returns it — builds through the same factory. The
/// records are loaded before `body` runs (declare them with ``ComposableFactory``);
/// `body` is synchronous — construction, never I/O.
///
/// > A server built on Vapor conforms ``VaporResponseBodyFactory`` instead (it also
/// > serves and localizes the result); adopt this base directly only outside Vapor.
public protocol ResponseBodyFactory: ServerRequestBody {
    /// The app-declared per-request value the projection may read (`Void` by default).
    associatedtype AppState: Sendable = Void

    /// Builds the body from the projection context of *any* request that returns it —
    /// synchronous by design.
    static func body<R: ServerRequest>(context: ProjectionContext<R, AppState>) throws -> Self
        where R.ResponseBody == Self
}
