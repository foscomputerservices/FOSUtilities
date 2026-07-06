// ContainerOperationTests.swift
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

@Suite("ContainerOperation")
struct ContainerOperationTests {
    @Test("Single op authorizes only its own intent (+ anyOperation, except destroy)")
    func singleOpIntent() {
        #expect(ContainerOperation.readRecords.authorizesReadRecords)
        #expect(!ContainerOperation.readRecords.authorizesWriteRecords)

        // anyOperation grants everything EXCEPT destroy
        #expect(ContainerOperation.anyOperation.authorizesReadRecords)
        #expect(ContainerOperation.anyOperation.authorizesWriteRecords)
        #expect(ContainerOperation.anyOperation.authorizesCreateRecords)
        #expect(ContainerOperation.anyOperation.authorizesDeleteRecords)
        #expect(!ContainerOperation.anyOperation.authorizesDestroyRecords)

        // destroy is explicit-only
        #expect(ContainerOperation.destroyRecords.authorizesDestroyRecords)
        #expect(!ContainerOperation.destroyRecords.authorizesReadRecords)
    }

    @Test("A set authorizes an intent iff any element does")
    func sequenceIntent() {
        let ops: [ContainerOperation] = [.readRecords, .createRecords]
        #expect(ops.authorizesReadRecords)
        #expect(ops.authorizesCreateRecords)
        #expect(!ops.authorizesWriteRecords)
        #expect(![ContainerOperation]().authorizesReadRecords) // empty grants nothing

        let anyOps: [ContainerOperation] = [.anyOperation]
        #expect(anyOps.authorizesDeleteRecords)
        #expect(!anyOps.authorizesDestroyRecords)
    }

    @Test("Usable as Set metadata (Hashable, no Codable needed)")
    func hashableSet() {
        let set: Set<ContainerOperation> = [.readRecords, .readRecords, .writeRecords]
        #expect(set.count == 2)
        #expect(set.contains(.readRecords))
    }

    @Test("authorizes(_:) answers by intent, including the wildcard-excludes-destroy rule")
    func operationSetAuthorizesByIntent() {
        let wildcard: [ContainerOperation] = [.anyOperation]
        #expect(wildcard.authorizes(.readRecords))
        #expect(wildcard.authorizes(.deleteRecords))
        #expect(!wildcard.authorizes(.destroyRecords)) // wildcard never grants destroy
        #expect([ContainerOperation]().authorizes(.readRecords) == false)
        #expect([.destroyRecords].authorizes(.destroyRecords))
        #expect([.writeRecords, .readRecords].authorizes(.readRecords))
        #expect(![.writeRecords].authorizes(.readRecords))
        #expect(wildcard.authorizes(.anyOperation))
        #expect(![ContainerOperation]().authorizes(.anyOperation))
    }
}
