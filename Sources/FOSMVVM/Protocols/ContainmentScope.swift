// ContainmentScope.swift
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

/// The region of data a loading plan is confined to, named by the party that owns it.
///
/// Every clause of a factory's plan says where it starts with `within:`. The scope decides
/// which container the plan begins from; the subject's grants then decide what loads inside
/// it — a scope never widens authority. Choose by who owns the region:
///
/// ```swift
/// static let cards      = Card.loadingPlan(.read, within: .request)             // the container the client named
/// static let status     = SystemStatus.loadingPlan(.read, within: .application) // the container the app resolves
/// static let workspaces = Workspace.loadingPlan(.read, within: .subject)        // what the subject's grants reach
/// static var children: [ComposedChild] { [.child(CardCellViewModel.self, within: .parent)] }
/// ```
///
/// `via:` descends from any scope through declared containment:
/// `Board.loadingPlan(.read, within: .subject, via: Workspace.self)`.
public enum ContainmentScope: Hashable, Sendable {
    /// The scope the enclosing factory bound. A child composed inside a parent shares it.
    ///
    /// ```swift
    /// // BoardPageViewModel is within .request (one Board). Its child:
    /// @ViewModel struct CardCellViewModel: ComposableFactory {
    ///     static let cards = Card.loadingPlan(.read, within: .parent)   // the cards of THAT Board
    ///     static var loadingPlans: LoadingPlans { cards }
    /// }
    /// ```
    ///
    /// Use it for every child unless the child deliberately opens a region of its own. A
    /// top-level factory has no parent; its `.parent` resolves to the request's own scope.
    case parent

    /// The container the client named. The request's query conforms to ``ScopedQuery`` and
    /// vends its identity.
    ///
    /// ```swift
    /// struct BoardPageQuery: ScopedQuery {
    ///     let scopeIdentity: ModelIdentity            // the Board this page is about
    /// }
    /// static let cards = Card.loadingPlan(.read, within: .request)
    /// ```
    ///
    /// Use it for a page about one container the client chose. One request names one
    /// container. A container the subject holds no grant reaching loads empty — never an
    /// error, so a guessed identity learns nothing.
    case request

    /// The container the application resolves for this caller, through
    /// `useApplicationScope(_:)` — a constant for a single-tenant app, the caller's tenant
    /// for a multi-tenant one — or, with nothing registered, the one system container.
    ///
    /// ```swift
    /// // configure(_:)
    /// try app.useApplicationScope { req in try await req.auth.require(SessionUser.self).tenantIdentity }
    /// // or simply: try app.register(Suite.self) — a lone SystemContainer IS the application scope
    ///
    /// static let status       = SystemStatus.loadingPlan(.read, within: .application)
    /// static let newWorkspace = Workspace.creationPlan(within: .application)   // create at the top
    /// ```
    ///
    /// Use it for anything scoped to the whole application or the caller's tenant: overviews,
    /// system-wide models, and creating a top-level container. The client cannot pick another.
    case application

    /// What the subject's grants reach: every model of the plan's type a grant names with
    /// the plan's operation, plus every such model inside a granted container that directly
    /// contains the type. Bound from the grants alone — nothing to name, nothing to resolve.
    ///
    /// ```swift
    /// static let workspaces = Workspace.loadingPlan(.read, within: .subject)                       // the Workspaces this user may see
    /// static let boards     = Board.loadingPlan(.read, within: .subject, via: Workspace.self)     // and their Boards
    /// static let archivable = Board.loadingPlan(.archive, within: .subject)                       // an archive request's candidates
    /// ```
    ///
    /// Use it for a list with no parent that differs per subject, and for a write whose
    /// target may be reachable by either a grant on the model or a grant on its container.
    /// Never a create scope: `creationPlan(within: .subject)` fails at boot. Every bound
    /// model is registered for live refresh, and the subject too when the provider vends it.
    /// A create registers no identity here — a row that did not exist was never bound — so
    /// pair a subject-scoped list with the application scope or a system container when new
    /// rows must appear live.
    case subject
}
