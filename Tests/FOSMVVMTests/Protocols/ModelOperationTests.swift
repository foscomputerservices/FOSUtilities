// ModelOperationTests.swift
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
import Foundation
import Testing

@Suite("ModelOperation")
struct ModelOperationTests {
    @Test("A single operation authorizes only its own intent; the wildcard everything but destroy")
    func singleOperationIntent() {
        #expect(ModelOperation.read.authorizesRead)
        #expect(!ModelOperation.read.authorizesWrite)
        #expect(!ModelOperation.read.authorizesArchive)
        #expect(!ModelOperation.read.authorizesDestroy)

        #expect(ModelOperation.anyOperation.authorizesRead)
        #expect(ModelOperation.anyOperation.authorizesWrite)
        #expect(ModelOperation.anyOperation.authorizesArchive)
        #expect(!ModelOperation.anyOperation.authorizesDestroy)

        #expect(ModelOperation.destroy.authorizesDestroy)
        #expect(!ModelOperation.destroy.authorizesRead)
    }

    @Test("A granted set authorizes an intent iff any element does")
    func sequenceIntent() {
        let granted: [ModelOperation] = [.read, .archive]
        #expect(granted.authorizesRead)
        #expect(granted.authorizesArchive)
        #expect(!granted.authorizesWrite)
        #expect(!granted.authorizesDestroy)
        #expect(![ModelOperation]().authorizesRead)

        let wildcard: [ModelOperation] = [.anyOperation]
        #expect(wildcard.authorizesWrite)
        #expect(!wildcard.authorizesDestroy)
    }

    @Test("authorizes(_:) answers by intent, honoring the wildcard and its destroy exclusion")
    func authorizesByIntent() {
        let wildcard: [ModelOperation] = [.anyOperation]
        #expect(wildcard.authorizes(.read))
        #expect(wildcard.authorizes(.write))
        #expect(wildcard.authorizes(.archive))
        #expect(!wildcard.authorizes(.destroy))
        #expect(wildcard.authorizes(.anyOperation))

        #expect([ModelOperation.destroy].authorizes(.destroy))
        #expect(![ModelOperation.write].authorizes(.read))
        #expect(![ModelOperation]().authorizes(.read))
        #expect(![ModelOperation]().authorizes(.anyOperation))
    }

    @Test("There is no create: the five cases are read, write, archive, destroy, and the wildcard")
    func noCreate() {
        #expect(ModelOperation.allCases.count == 5)
        #expect(Set(ModelOperation.allCases) == [.read, .write, .archive, .destroy, .anyOperation])
    }

    @Test("Usable as Set metadata")
    func hashableSet() {
        let set: Set<ModelOperation> = [.read, .read, .write]
        #expect(set.count == 2)
        #expect(set.contains(.read))
    }
}
