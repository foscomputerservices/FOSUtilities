// Macros.swift
//
// Copyright 2024 FOS Computer Services, LLC
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

public enum ViewModelOptions {
    /// Generate ``ClientHostedViewModelFactory`` support
    case clientHostedFactory
}

@attached(extension, conformances: RetrievablePropertyNames, FieldValidationModel)
@attached(member, names: named(propertyNames))
public macro FieldValidationModel() = #externalMacro(
    module: "FOSMacros",
    type: "FieldValidationModelMacro"
)

@attached(extension, conformances: RetrievablePropertyNames, ViewModel, ClientHostedViewModelFactory, RequestableViewModel)
@attached(member, names: named(propertyNames), named(Request), named(AppState), named(model), named(modelSync), named(ClientHostedRequest))
public macro ViewModel(options: Set<ViewModelOptions> = []) = #externalMacro(
    module: "FOSMacros",
    type: "ViewModelMacro"
)

@attached(member, names: named(model))
public macro VersionedFactory() = #externalMacro(
    module: "FOSMacros",
    type: "ViewModelFactoryMacro"
)

@attached(peer, names: arbitrary)
public macro Version(_ version: SystemVersion) = #externalMacro(
    module: "FOSMacros",
    type: "ViewModelFactoryMethodMacro"
)
