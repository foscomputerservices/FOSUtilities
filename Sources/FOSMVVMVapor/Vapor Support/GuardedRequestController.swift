// GuardedRequestController.swift
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

import FOSMVVM
import Vapor

/// The pre-specialized controller register(request:app:) instantiates: the general
/// dispatch mechanism carrying the framework's guarded pipelines as its processors.
/// Guards live in the processors (and the register-door boot checks) — never in
/// which door was walked through.
/// The generic parameter is deliberately NOT named TRequest: naming it after the
/// associatedtype it witnesses makes the protocol's ActionProcessor typealias
/// unresolvable (a type-resolution cycle); the explicit typealias breaks it.
final class GuardedRequestController<Request: ServerRequest>: ServerRequestController {
    typealias TRequest = Request

    let actions: [ServerRequestAction: ActionProcessor]

    init(actions: [ServerRequestAction: ActionProcessor]) {
        self.actions = actions
    }
}
