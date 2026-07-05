// ContainmentError.swift
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

/// Containment misconfiguration, by trigger timing. BOOT-TIME (thrown from configure(_:)):
/// `.duplicateNamespace`, `.containerTypeMismatch`, `.containmentDrift`,
/// `.duplicateAuthorizationProvider`, `.duplicateApexContainerResolver`, `.invalidLoadPlan`
/// (RecordLoadPlan boot validation at route registration), `.missingAppStateBuilder` /
/// `.duplicateAppStateBuilder` (useAppState registry validation at route registration),
/// `.unstableRequirementTokens` (`dataRequirements`/`candidates` mints requirements inline
/// instead of returning stored handles), `.writeRequestAtReadDoor` / `.unsupportedWriteProtocol` (a
/// write-protocol conformer reaching the read door / a not-yet-supported write protocol).
/// REQUEST-TIME:
/// `.unregisteredNamespace` (registry lookup for a stored identity found no registered type),
/// `.noAuthorizationProvider` (first authorized load with no provider registered),
/// `.unsortableContainedType` (sort terms against a non-sortable or wrong-vocabulary contained type),
/// `.unplannedRequirement` / `.ambiguousRequirement` (a projection read a requirement handle that
/// reached the plan zero / more-than-once), `.appStateInconsistency` (the boot check guarantees a
/// correctly-typed AppState builder, so any request-time failure to resolve one is a framework
/// invariant breakage), `.invalidCreateScope` (a create was directed at a relation that is not a
/// create scope), plus the members() cast backstop.
/// Internal, not public: apps never catch it — its value is the diagnostic message in Vapor's
/// failed configure(_:) or a thrown request-time error; coverage tests assert the typed cases
/// via @testable.
enum ContainmentError: Error, CustomDebugStringConvertible {
    case duplicateNamespace(modelType: String)
    case containerTypeMismatch(expected: String, actual: String)
    case containmentDrift(modelType: String, containmentTypes: [String], containedRecordTypes: [String])
    case unsortableContainedType(modelType: String, keyType: String)
    case unregisteredNamespace(identity: String)
    case duplicateAuthorizationProvider(registered: String, duplicate: String)
    case noAuthorizationProvider
    case invalidLoadPlan(request: String, reason: String)
    case duplicateApexContainerResolver
    case unplannedRequirement(recordType: String, request: String)
    case ambiguousRequirement(recordType: String, request: String, matchCount: Int)
    case missingAppStateBuilder(request: String, appStateType: String)
    case duplicateAppStateBuilder(appStateType: String)
    case appStateInconsistency(request: String, appStateType: String, reason: String)
    case unstableRequirementTokens(request: String, handle: String)
    case writeRequestAtReadDoor(request: String)
    case unsupportedWriteProtocol(request: String)
    case invalidCreateScope(container: String, recordType: String)

    var debugDescription: String {
        switch self {
        case .duplicateNamespace(let modelType):
            "Duplicate ModelTypeRegistry registration: \(modelType)'s namespace is already registered. Each container is registered exactly once (register(_:migration:))."
        case .containerTypeMismatch(let expected, let actual):
            "ContainmentRelation container-type mismatch: relation was built from \(expected)'s relationship, but was applied to \(actual). Build containment only from the declaring container's own KeyPaths; if this arose from a sort/refinement path it indicates framework-invariant breakage — file an issue."
        case .containmentDrift(let modelType, let containmentTypes, let containedRecordTypes):
            "\(modelType).containment (\(containmentTypes.sorted())) must declare the same record types as its containedRecordTypes (\(containedRecordTypes.sorted())). These two declarations must not drift."
        case .unsortableContainedType(let modelType, let keyType):
            "Sort terms of key type \(keyType) cannot be applied to \(modelType): the model must conform to SortableDataModel with \(keyType) as its RequestSortKey. Loads never silently drop a requested sort — fix the request's sort vocabulary or the model's conformance."
        case .unregisteredNamespace(let identity):
            "No container is registered for the requested identity (\(identity)). Register the container in configure(_:) via Application.register(_:migration:) — an unregistered namespace is a configuration bug, not an authorization result."
        case .duplicateAuthorizationProvider(let registered, let duplicate):
            "Duplicate ContainerAuthorizationProvider registration: \(registered) is already registered, so \(duplicate) was rejected. Exactly one provider per application (useContainerAuthorizationProvider(_:)); compose multiple sources inside that single conformance."
        case .noAuthorizationProvider:
            "No ContainerAuthorizationProvider is registered. Register one in configure(_:) via Application.useContainerAuthorizationProvider(_:) — a missing provider is a configuration bug, not an unauthorized/empty-grant result."
        case .invalidLoadPlan(let request, let reason):
            "Invalid RecordLoadPlan for \(request): \(reason). Plans are derived and validated at route registration, never at request time — fix the factory declarations or boot registrations named above."
        case .duplicateApexContainerResolver:
            "Duplicate apex container resolver registration: a resolver is already registered, so this one was rejected. Exactly one resolver per application (useApexContainerResolver(_:)); compose multi-tenant resolution inside that single closure."
        case .unplannedRequirement(let recordType, let request):
            "A projection of \(request) read records of \(recordType) through a requirement handle that never reached the request's load plan. A handle that is not declared never loads — declare it in the factory's dataRequirements (or, for a composed child's data, list the child in children). Mint each requirement in a stored static let handle and return those handles from dataRequirements; a handle minted inline in the getter carries a fresh declaration identity, so a handle read back never matches the one that was walked. Reading an undeclared handle is a misconfiguration, never a silently empty screen."
        case .ambiguousRequirement(let recordType, let request, let matchCount):
            "A projection of \(request) read \(recordType) through a requirement handle that matched \(matchCount) declared loads — the handle is ambiguous. The same declaration was composed onto multiple paths — give each composition its own declaration so the handle names exactly one load; the framework never guesses which set to return."
        case .missingAppStateBuilder(let request, let appStateType):
            "No AppState builder is registered for \(appStateType), which \(request)'s ResponseBody projects. Register one in configure(_:) via useAppState(\(appStateType).self) { req in ... } — call it BEFORE register(request:). A non-Void AppState with no builder is a boot-time configuration bug, never a first-request surprise."
        case .duplicateAppStateBuilder(let appStateType):
            "Duplicate AppState builder registration: a builder for \(appStateType) is already registered, so this one was rejected. Exactly one builder per AppState type (useAppState(_:builder:)); compose multiple sources inside that single closure."
        case .appStateInconsistency(let request, let appStateType, let reason):
            "Internal inconsistency resolving AppState \(appStateType) for \(request): \(reason). The boot check guarantees a correctly-typed builder for every non-Void AppState, so this is a framework-invariant breakage — file an issue."
        case .unstableRequirementTokens(let request, let handle):
            "\(request)'s \(handle) is not stable across evaluations: two reads minted different declaration identities. Mint each requirement in a stored static let handle and return those handles — a computed dataRequirements (or candidates) RETURNING stored handles is fine and canonical; minting inline in the getter allocates a fresh declaration identity on each access, which breaks the handle→load resolution."
        case .writeRequestAtReadDoor(let request):
            "\(request) is a write-protocol request (Create/Update/Delete) but reached the read door (register(request:) for a plain read). Its Query/RequestBody do not satisfy the write overload's constraints (Query: TargetedQuery, RequestBody: DataModelWriter/WriteTargetProviding), so overload resolution fell through to the read door. Registering it read-only would be a silent write-drop — fix the Query/RequestBody so the write overload binds."
        case .unsupportedWriteProtocol(let request):
            "\(request) speaks a write protocol that is not yet supported (ReplaceRequest/DestroyRequest). Only Create, Update, and Delete are wired. Registering it read-only would be a silent write-drop — this write protocol has no route yet."
        case .invalidCreateScope(let container, let recordType):
            "Cannot create a \(recordType) into \(container): the containment relation for \(recordType) is a to-one parent relation, which is not a create scope. Create is defined only into a container's .children or .siblings relations, where the container owns the new record."
        }
    }
}
