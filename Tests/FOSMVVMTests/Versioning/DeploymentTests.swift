// DeploymentTests.swift
//
// Created by David Hunt on 9/11/24
// Copyright 2024 FOS Services, LLC
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
@testable import FOSMVVM
import Foundation
import Testing

@Suite("Deployment Tests")
struct DeploymentTests {
    @Test func overriddenCurrent() async {
        await Deployment.overrideDeployment(to: .production)
        #expect(await Deployment.current == .production)
    }

    @Test func defaultCurrent() async {
        #expect(await Deployment.current == .debug)
    }

    @Test(arguments: [
        (deployment: Deployment.production, id: "production"),
        (deployment: Deployment.staging, id: "staging"),
        (deployment: Deployment.debug, id: "debug"),
        (deployment: Deployment.custom(name: "_custom"), id: "_custom")
    ]) func testID(tuple: (deployment: Deployment, id: String)) async {
        await Deployment.overrideDeployment(to: tuple.deployment)
        #expect(await Deployment.current.id == tuple.id)
    }

    @Test(arguments: [
        (deployment: Deployment.production, env: "production"),
        // Checks that an empty string doesn't use .custom(name: "")
        (deployment: Deployment.debug, env: ""),
        (deployment: Deployment.staging, env: "staging"),
        (deployment: Deployment.debug, env: "debug"),
        (deployment: Deployment.custom(name: "_custom"), env: "_custom")
    ]) func testEnvUpdate(tuple: (deployment: Deployment, env: String)) async {
        setenv(Deployment.envKey, tuple.env, 1)
        #expect(await Deployment.current.id == tuple.deployment.id)
    }

    @Test(arguments: [
        Deployment.production,
        .staging,
        .debug,
        .custom(name: "_custom")
    ]) func testEquatable(deployment: Deployment) {
        #expect(deployment == deployment)
        #expect(deployment != .custom(name: "????"))
    }

    init() async {
        setenv(Deployment.envKey, "", 1)
        await Deployment.testingReset()
    }
}
