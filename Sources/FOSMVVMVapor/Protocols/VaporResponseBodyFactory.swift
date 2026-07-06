// VaporResponseBodyFactory.swift
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

import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

/// Produces a request's `ResponseBody` on the server — the one factory for every
/// server-produced body, ViewModel or not. Author it once on the body; every request
/// whose `ResponseBody` is this type (a read and the writes that return it) reuses it.
///
/// ```swift
/// extension DockPageViewModel: VaporResponseBodyFactory {
///     static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self
///         where R.ResponseBody == Self {
///         .init(berthCells: try context.records(Self.berths)
///             .map { BerthCellViewModel(berth: $0) })
///     }
/// }
/// ```
///
/// The projection is handed a ``ProjectionContext`` — never a `Vapor.Request`,
/// never a `Database`. Records were loaded BEFORE projection began (auth-scoped,
/// cached, per the factory's declared requirements); a data need the factory forgot
/// to declare fails fast instead of loading silently.
///
/// `body` is synchronous — `throws`, never `async`. Loading belongs to the load
/// phase (declare it, or use ``SupplementalRecordLoading``); an awaitable projection
/// is the hole this type exists to close.
///
/// A zero-data body conforms to the factory alone (no ``ComposableFactory`` trait):
/// no plan, no data, just `body(context:)` returning the constructed value.
public protocol VaporResponseBodyFactory: ResponseBodyFactory, Vapor.AsyncResponseEncodable {}

public extension VaporResponseBodyFactory {
    /// Serves the body *localized to the request's* [Accept-Language](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language).
    ///
    /// The server route registered by ``Vapor/Application/register(request:)`` returns the
    /// *unlocalized* body straight from its processor and hands it to the shared
    /// ``ServerRequestBody/buildResponse(_:)`` to build the HTTP `Response`. That is the single
    /// point where localization-on-serve happens — the request-binding
    /// `VaporServerRequestMiddleware` only parses the query into the `ServerRequest` and does
    /// no response post-processing.
    ///
    /// **SRP:** encoding-with-localization has exactly one home — the shared
    /// ``ServerRequestBody/buildResponse(_:)`` (which encodes through `req.localizingEncoder`
    /// and stamps the `SystemVersion` header). This default delegates there so no conformer
    /// re-implements it. **OCP:** a ``VaporResponseBodyFactory`` therefore supplies only
    /// `body(context:)`; adding per-type `encodeResponse` boilerplate would be a red flag that
    /// localization leaked out of its single owner.
    func encodeResponse(for request: Vapor.Request) async throws -> Vapor.Response {
        try buildResponse(request)
    }
}
