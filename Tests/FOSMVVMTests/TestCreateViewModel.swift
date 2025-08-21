// TestCreateViewModel.swift
//
// Copyright 2025 FOS Computer Services, LLC
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

struct TestCreateModel: ServerRequestBody, ValidatableModel, Codable {
    let field: String

    func validate(fields: [any FOSMVVM.FormFieldBase]?, validations: FOSMVVM.Validations) -> FOSMVVM.ValidationResult.Status? {
        nil
    }
}

final class TestCreateViewModelRequest: ValidatableViewModelRequest, @unchecked Sendable {
    typealias Query = EmptyQuery
    typealias Fragment = EmptyFragment
    let requestBody: TestCreateModel?
    var responseBody: ResponseBody?

    @ViewModel struct ResponseBody: RequestableViewModel {
        typealias Request = TestCreateViewModelRequest

        let finalField: String

        var vmId: ViewModelId = .init()
    }

    struct ResponseError: ValidatableViewModelRequestError {
        let validations: [ValidationResult]

        init(validations: [ValidationResult]) {
            self.validations = validations
        }
    }

    init(query: Query? = nil, fragment: Fragment? = nil, requestBody: TestCreateModel?, responseBody: ResponseBody?) {
        self.requestBody = requestBody
        self.responseBody = responseBody
    }
}

extension TestCreateViewModelRequest.ResponseBody {
    static func stub() -> Self {
        .init(
            finalField: "<stub final>"
        )
    }
}
