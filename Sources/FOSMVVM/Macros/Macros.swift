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

    /// Refresh bound views automatically when server data changes — see ``LiveViewModel``
    case live
}

@attached(extension, conformances: RetrievablePropertyNames, FieldValidationModel)
@attached(member, names: named(propertyNames))
public macro FieldValidationModel() = #externalMacro(
    module: "FOSMacros",
    type: "FieldValidationModelMacro"
)

/// The identifier of a form field, from the property it validates
///
/// ```swift
/// public extension CardFields {
///     static var titleField: FormField<String> { .init(
///         fieldId: #fieldId(\Self.title),
///         …
///     )}
/// }
///
/// return [.init(status: .error, fieldId: #fieldId(\CardFields.title), message: validationMessages.titleTaken)]
/// ```
///
/// Name the key path's root (`\CardFields.title`, or `\Self.title` inside the type). The compiler
/// checks the key path, so renaming the property breaks every site that names it. The identity is
/// scoped to the type the key path names, so `\CardFields.title` and `\BoardFields.title` are
/// different fields; inside a `Fields` protocol's extension `\Self` names the protocol, so every
/// adopter shares the one identity. Mint a field a form shows on the `Fields` protocol that
/// declares it, so the form, the request body and the `DataModel` all name the one field; mint a
/// property no form shows on the model itself. A capitalized component names the type and a
/// lowercase one names the property, so a nested property like `\Card.author.name` is one field
/// of `Card`.
///
/// For a field repeated over a collection, pass the element's index: ``fieldId(_:index:)``.
@freestanding(expression)
public macro fieldId<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> FormFieldIdentifier = #externalMacro(
    module: "FOSMacros",
    type: "FieldIdMacro"
)

/// The identifier of one element of a form field repeated over a collection
///
/// Pass the element's position, the way a localized string for one element does:
///
/// ```swift
/// for index in tags.indices {
///     fields.append(FormField(fieldId: #fieldId(\CardFields.tags, index: index), title: …))
/// }
/// ```
///
/// Two mints with the same key path and index are equal, so a message about an element finds
/// its field.
///
/// > Note: The key path names the field the same way it does in ``fieldId(_:)``.
@freestanding(expression)
public macro fieldId<Root, Value>(_ keyPath: KeyPath<Root, Value>, index: Int) -> FormFieldIdentifier = #externalMacro(
    module: "FOSMacros",
    type: "FieldIdMacro"
)

public enum LocalizableErrorOptions {
    /// The error is created — and therefore localized — on the client; see
    /// ``ClientHostedLocalizableError``
    case clientHosted
}

@attached(extension, conformances: RetrievablePropertyNames, LocalizableError, ClientHostedLocalizableError)
@attached(member, names: named(propertyNames))
public macro LocalizableError(options: Set<LocalizableErrorOptions> = []) = #externalMacro(
    module: "FOSMacros",
    type: "LocalizableErrorMacro"
)

@attached(extension, conformances: RetrievablePropertyNames, ViewModel, ClientHostedViewModelFactory, RequestableViewModel, LiveViewModel)
@attached(member, names: named(propertyNames), named(Request), named(AppState), named(model), named(modelSync), named(ClientHostedRequest), named(stub))
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
