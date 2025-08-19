// FieldModelTests.swift
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

// @ViewModel struct TestUserModel {
//    @LocalizedString var usernameTitle
//    @LocalizedString var usernamePlaceholder
//    @FormFieldModel(Self.userNameField) var username: String
//
//    var vmId: FOSMVVM.ViewModelId = .init()
// }
//
// extension TestUserModel {
//    static func stub() -> Self {
//        .init()
//    }
// }
//
// private extension TestUserModel {
//    static var userNameField: FormField<String> {
//        .init(
//            fieldId: .init(id: "username"),
//            title: .localized(for: Self.self, parentKeys: "username", propertyName: "title"),
//            placeholder: .localized(for: Self.self, parentKeys: "username", propertyName: "placeholder"),
//            type: .text(inputType: .text),
//            options: [
//                .required(value: true),
//                .maxLength(value: 255)
//            ]
//        )
//    }
// }
