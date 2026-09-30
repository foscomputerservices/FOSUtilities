// SystemContainerFixtures.swift
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

import FluentKit
import FOSFoundation
import FOSMVVM
@testable import FOSMVVMVapor
import Foundation
import Vapor

// The containers with no rows: Suite owns every Workspace and every Mooring; Fleet owns every Quay.

enum Suite: SystemContainer {
    static var containment: [ContainmentRelation] {
        [.all(Workspace.self), .all(Mooring.self)]
    }
}

enum Fleet: SystemContainer {
    static var containment: [ContainmentRelation] {
        [.all(Quay.self)]
    }
}

// MARK: - Deliberately misconfigured (boot fail-fast fixtures)

/// A system container declaring a row relation — it has no rows to join from.
enum RowRelationSuite: SystemContainer {
    static var containment: [ContainmentRelation] {
        [.children(\Workspace.$boards)]
    }
}

/// A container with rows declaring `.all(_:)` — only a system container may.
final class AllDeclaringBoard: ContainerDataModel, @unchecked Sendable {
    static let schema = "all_declaring_boards"
    static var containedRecordTypes: [any FOSMVVM.Model.Type] {
        [Card.self]
    }

    static var containment: [ContainmentRelation] {
        [.all(Card.self)]
    }

    @ID(key: .id) var id: UUID?
    init() {}
    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

// MARK: - Reads and a create at the top

/// The Workspaces within the application scope — with a lone system container registered and
/// no `useApplicationScope`, that scope IS the system container.
struct WorkspaceListVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = WorkspaceListRequest

    static let workspaces = Workspace.loadingPlan(.read, within: .application)
    static var loadingPlans: LoadingPlans {
        workspaces
    }

    var vmId = ViewModelId()
    var names: [String] = []

    init() {}
    init(names: [String]) {
        self.names = names
    }

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        try .init(names: context.records(Self.workspaces).map(\.name).sorted())
    }
}

extension WorkspaceListVM: CreateResponseBody {}

final class WorkspaceListRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: WorkspaceListVM?

    init(query _: EmptyQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: WorkspaceListVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}

struct CreateWorkspaceBody: ServerRequestBody, ValidatableModel {
    var name: String

    func validate(fields _: [any FormFieldBase]?, validations _: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

extension CreateWorkspaceBody: DataModelWriter {
    static let candidates = Workspace.creationPlan(within: .application)

    func apply(to workspace: Workspace) throws {
        workspace.name = name
    }
}

/// Creates a Workspace at the top: no container row exists to create into, so the system
/// container is the destination.
final class CreateWorkspaceRequest: CreateRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias RequestBody = CreateWorkspaceBody
    typealias Fragment = EmptyFragment
    typealias ResponseError = ValidationError
    typealias ResponseBody = WorkspaceListVM

    let id: String
    let requestBody: CreateWorkspaceBody?
    var responseBody: WorkspaceListVM?

    init(query _: EmptyQuery?, sort _: EmptySort?, fragment _: EmptyFragment?, requestBody: CreateWorkspaceBody?, responseBody: WorkspaceListVM?) {
        self.id = .random(length: 10)
        self.requestBody = requestBody
        self.responseBody = responseBody
    }

    static func stub() -> Self {
        .init(query: nil, sort: nil, fragment: nil, requestBody: nil, responseBody: nil)
    }
}

/// The Workspaces the subject's grants reach — through a grant on the system container, its
/// `.all(Workspace.self)` members are the extended set.
struct SubjectWorkspacesVM: RequestableViewModel, ComposableFactory, VaporResponseBodyFactory {
    typealias Request = SubjectWorkspacesRequest

    static let workspaces = Workspace.loadingPlan(.read, within: .subject)
    static var loadingPlans: LoadingPlans {
        workspaces
    }

    var vmId = ViewModelId()
    init() {}

    func propertyNames() -> [LocalizableId: String] {
        [:]
    }

    static func stub() -> Self {
        .init()
    }

    static func body<R: ServerRequest>(context _: ProjectionContext<R, Void>) throws -> Self where R.ResponseBody == Self {
        .init()
    }
}

final class SubjectWorkspacesRequest: ViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias ResponseError = EmptyError

    let id: String
    var responseBody: SubjectWorkspacesVM?

    init(query _: EmptyQuery? = nil, sort _: EmptySort? = nil, fragment _: EmptyFragment? = nil, requestBody _: EmptyBody? = nil, responseBody: SubjectWorkspacesVM? = nil) {
        self.id = .random(length: 10)
        self.responseBody = responseBody
    }
}
