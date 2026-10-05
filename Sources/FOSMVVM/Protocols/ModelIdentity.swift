// ModelIdentity.swift
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
import Foundation

/// Answers "which entity is this?" for a ``Model`` — an opaque, value-comparable identity that stays
/// stable across the wire, persistence, and authorization.
///
/// Get one from a model, then compare, route on, or store it — without ever touching the underlying
/// id or type:
///
/// ```swift
/// let identity = try user.modelIdentity
///
/// if identity == changedModel { refresh() }     // compare to a live model of any type, safely
/// grantedContainers.contains(identity)          // Hashable — use it as a Set member or dictionary key
/// ```
///
/// You can't build one from raw values, and you can't read its contents back out. An identity comes
/// only from ``Model/modelIdentity``, from decoding, or, in tests and previews, from ``stub()``.
///
/// A ViewModel carries an identity for two reasons: to pass it along, through its View and
/// Operations, to the ServerRequest that acts on the entity, and to root its ``ViewModel/vmId``. It
/// never builds one or looks inside it. Its init takes the identity, and its factory passes in
/// ``Model/modelIdentity``.
///
/// - Important: Treat it as opaque. Encode/decode it *as a whole* to persist or transmit it; never
///   parse or hand-build its encoded form. The encoding is stable — it changes only on a library major
///   version — so a stored identity always round-trips.
public struct ModelIdentity: Hashable, Codable, Sendable {
    // `package`, NOT public — server-side targets read these to drive the ModelTypeRegistry lookup +
    // Fluent find; clients still cannot read identity contents (opacity is a public-surface guarantee, L0).
    package let namespace: ModelNamespace
    package let id: ModelIdType

    /// The one identity of a system container — a container with no rows, so not a `Model`, which
    /// is why it cannot mint through ``Model/modelIdentity``. `package`, not public: the server's
    /// `SystemContainer.identity` is its only caller, and it mints exactly one shape — the type's
    /// namespace with the framework's constant id part — never an arbitrary namespace and id.
    package static func systemContainer(for type: Any.Type) -> ModelIdentity {
        .init(namespace: ModelNamespace(for: type), id: systemContainerId)
    }

    // Frozen: L1 persists these in DB columns — never rename/reorder/remove a key (breaks stored
    // data; a change here is a library major-version bump).
    private enum CodingKeys: String, CodingKey {
        case namespace
        case id
    }
}

/// The constant id part every system container's identity carries: the namespace (the type) is
/// what tells two apart. Pinned by SystemContainerTests — changing it orphans every stored grant on
/// a system container.
let systemContainerId = UUID(uuid: (0x5F, 0x05, 0xC0, 0xDE, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))

public extension ModelIdentity {
    /// The HTTP response header FOSMVVM uses to keep ``LiveViewModel`` screens current
    ///
    /// The framework attaches it to served responses and the live bind resolver consumes
    /// it — application code never reads, parses, or constructs its value. The constant
    /// exists so infrastructure (proxies, logging filters, tests) can reference the header
    /// **by name**; its value is an opaque framework contract that may evolve.
    static let registrationsHeader = "X-FOS-Registrations"
}

public extension ModelIdentity {
    /// Whether this identity is the one rooted in `model` — sugar for `models.filter { changed == $0 }`.
    ///
    /// An unpersisted `model` (`id == nil`) compares `false`; it never throws.
    static func == (lhs: ModelIdentity, rhs: some Model) -> Bool {
        (try? lhs == rhs.modelIdentity) ?? false
    }
}

extension ModelIdentity: Stubbable {
    /// A new stand-in identity for tests and previews.
    ///
    /// A ViewModel that carries an identity takes it as a defaulted stub parameter, so every preview
    /// and test gets a valid one without a model:
    ///
    /// ```swift
    /// @ViewModel
    /// struct CardViewModel: ModelIdentifiedViewModel {
    ///     let modelIdentity: ModelIdentity
    ///     let vmId: ViewModelId
    ///
    ///     init(modelIdentity: ModelIdentity) {
    ///         self.modelIdentity = modelIdentity
    ///         self.vmId = modelIdentity.viewModelId
    ///     }
    ///
    ///     static func stub(modelIdentity: ModelIdentity = .stub()) -> Self {
    ///         .init(modelIdentity: modelIdentity)
    ///     }
    /// }
    /// ```
    ///
    /// To prove a View wires the identity through to its Operation, hold one, pass it in, and check
    /// that the same identity comes out the other end of the action:
    ///
    /// ```swift
    /// let cardId = ModelIdentity.stub()
    /// let app = try presentView(viewModel: .stub(modelIdentity: cardId))
    ///
    /// app.uiTestingElement("deleteButton").tap()
    ///
    /// let stubOps = try viewModelOperations()
    /// XCTAssertEqual(stubOps.deleteCalledWith, cardId)
    /// ```
    ///
    /// > Each call returns a different identity, so the rows of a stubbed list stay distinct. A stub
    /// > identity names no entity: it equals itself across an encode and decode, never equals another
    /// > stub, and never equals an identity that came from a real model.
    public static func stub() -> Self {
        .init(namespace: ModelNamespace(for: StubIdentity.self), id: .init())
    }
}

/// Anchors every stub identity's namespace. Private, so no `Model` and no `ModelNamespace(for:)`
/// outside FOSMVVM can name it: a stub can never collide with a real model's identity.
private enum StubIdentity {}

public extension ModelIdentity {
    /// A stable ``ViewModelId`` derived from this identity. Bind your ViewModel's `vmId` to it so
    /// SwiftUI keeps the view stable as the model's data changes:
    ///
    /// ```swift
    /// self.vmId = try user.modelIdentity.viewModelId
    /// ```
    var viewModelId: ViewModelId {
        namespace.viewModelId(rooting: id)
    }
}
