// ModelIdentifiedViewModelTests.swift
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
import Testing

@ViewModel
private struct WidgetViewModel: RequestableViewModel, ModelIdentifiedViewModel, Hashable {
    typealias Request = WidgetViewModelRequest
    @LocalizedString var title
    let vmId: ViewModelId
    let modelIdentity: ModelIdentity

    init(widget: TestWidget) throws {
        let identity = try widget.modelIdentity
        self.modelIdentity = identity
        self.vmId = identity.viewModelId
    }

    static func stub() -> Self {
        try! .init(widget: TestWidget())
    }
}

private final class WidgetViewModelRequest: ViewModelRequest, @unchecked Sendable {
    typealias Fragment = EmptyFragment
    typealias RequestBody = EmptyBody
    typealias ResponseError = EmptyError
    let query: EmptyQuery?
    var responseBody: WidgetViewModel?

    init(
        query: EmptyQuery? = nil,
        sort: EmptySort? = nil,
        fragment: EmptyFragment? = nil,
        requestBody: EmptyBody? = nil,
        responseBody: WidgetViewModel? = nil
    ) {
        self.query = query
        self.responseBody = responseBody
    }
}

struct ModelIdentifiedViewModelTests {
    @Test func exposesModelIdentityRootedInTheModel() throws {
        let widget = TestWidget()
        let vm = try WidgetViewModel(widget: widget)
        #expect(vm.modelIdentity == widget)
        #expect(try vm.vmId == widget.modelIdentity.viewModelId)
    }
}
