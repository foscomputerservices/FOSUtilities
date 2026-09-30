// ModelOperationMappingTests.swift
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

@testable import FOSMVVM
import Foundation
import Testing

@Suite("ModelOperation ↔ ContainerOperation mapping")
struct ModelOperationMappingTests {
    @Test("Each model operation names the member operation a granted container must extend")
    func modelToContainer() {
        #expect(ModelOperation.read.containerOperation == .readRecords)
        #expect(ModelOperation.write.containerOperation == .writeRecords)
        #expect(ModelOperation.archive.containerOperation == .archiveRecords)
        #expect(ModelOperation.destroy.containerOperation == .destroyRecords)
        #expect(ModelOperation.anyOperation.containerOperation == .anyOperation)
    }

    @Test("Each member operation names the model operation a named model must hold; create has none")
    func containerToModel() {
        #expect(ContainerOperation.readRecords.modelOperation == .read)
        #expect(ContainerOperation.writeRecords.modelOperation == .write)
        #expect(ContainerOperation.createRecords.modelOperation == nil)
        #expect(ContainerOperation.archiveRecords.modelOperation == .archive)
        #expect(ContainerOperation.destroyRecords.modelOperation == .destroy)
        #expect(ContainerOperation.anyOperation.modelOperation == .anyOperation)
    }

    @Test("The mapping round-trips for every model operation")
    func roundTrip() {
        for operation in ModelOperation.allCases {
            #expect(operation.containerOperation.modelOperation == operation)
        }
    }
}
