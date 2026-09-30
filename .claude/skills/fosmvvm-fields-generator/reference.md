# FOSMVVM Fields Generator - Reference Templates

Complete file templates for generating Form Specifications.

> **Conceptual context:** See [SKILL.md](SKILL.md) for when and why to use this skill.
> **Architecture context:** See [FOSMVVMArchitecture.md](../../docs/FOSMVVMArchitecture.md) for full FOSMVVM understanding.

## Placeholders

| Placeholder | Replace With | Example |
|-------------|--------------|---------|
| `{Name}` | Form specification name (PascalCase) | `CreateIdea`, `User`, `LoginCredentials` |
| `{name}` | Same, but camelCase | `createIdea`, `user`, `loginCredentials` |
| `{ViewModelsTarget}` | Your ViewModels SPM target | `ViewModels`, `SharedViewModels` |
| `{ResourcesPath}` | Your localization resources path | `Sources/Resources` |

---

## File 1: {Name}Fields.swift

**Location:** `Sources/{ViewModelsTarget}/FieldModels/{Name}Fields.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// Form Specification for {describe the form purpose}.
///
/// This protocol defines:
/// - The user-editable fields
/// - Form presentation metadata (FormField definitions)
/// - Validation rules and localized error messages
///
/// Adopted by: RequestBody types, ViewModels, and optionally DataModels.
public protocol {Name}Fields: ValidatableModel, Codable, Sendable {
    // MARK: - Field Declarations

    // var fieldName: FieldType { get set }
}

// MARK: - Enums (if needed for constrained fields)

// public enum {Name}Status: String, CaseIterable, Equatable, Codable, Sendable {
//     case draft = "draft"
//     case published = "published"
// }

// MARK: - Field Definitions & Validation

public extension {Name}Fields {
    // MARK: Field Constraints

    // static var fieldNameRange: ClosedRange<Int> { 1...1024 }

    // MARK: FormField Definitions

    // static var fieldNameField: FormField<String?> { .init(
    //     fieldId: #fieldId(\Self.fieldName),
    //     title: .localized(for: {Name}FieldsMessages.self, propertyName: "fieldName", messageKey: "title"),
    //     placeholder: .localized(for: {Name}FieldsMessages.self, propertyName: "fieldName", messageKey: "placeholder"),
    //     type: .text(inputType: .text),
    //     options: [
    //         .required(value: true),
    //         .autocomplete(value: .off),
    //         .autocapitalize(value: .never)
    //     ] + FormInputOption.rangeLength(fieldNameRange)
    // ) }

    // MARK: Validation Message Mints
    //
    // Minted the way a FormField's title is: a @LocalizedString property binds its key only
    // while its own model is being encoded, so a message read off a {Name}FieldsMessages
    // instance and carried in a ValidationResult would encode empty.

    // static var fieldNameRequiredMessage: LocalizableString {
    //     .localized(for: {Name}FieldsMessages.self, propertyName: "fieldName", messageGroup: "validationMessages", messageKey: "required")
    // }

    // static var fieldNameOutOfRangeMessage: LocalizableString {
    //     .localized(for: {Name}FieldsMessages.self, propertyName: "fieldName", messageGroup: "validationMessages", messageKey: "outOfRange")
    // }

    // MARK: Field Validation Methods

    // internal func validateFieldName(_ fields: [FormFieldBase]?) -> [ValidationResult]? {
    //     guard fields?.contains(Self.fieldNameField) ?? true else {
    //         return nil
    //     }
    //
    //     var result = [ValidationResult]()
    //
    //     if fieldName.isEmpty {
    //         result.append(.init(
    //             status: .error,
    //             field: Self.fieldNameField,
    //             message: Self.fieldNameRequiredMessage
    //         ))
    //     } else if !Self.fieldNameRange.contains(NSString(string: fieldName).length) {
    //         result.append(.init(
    //             status: .error,
    //             field: Self.fieldNameField,
    //             message: Self.fieldNameOutOfRangeMessage
    //         ))
    //     }
    //
    //     return result.isEmpty ? nil : result
    // }

    // MARK: ValidatableModel Implementation

    func {name}FieldsValidateModel(
        validations: Validations,
        fields: [FormFieldBase]?
    ) -> [ValidationResult]? {
        var result = [ValidationResult]()

        // Aggregate all field validations:
        // result += validateFieldName(fields)

        return result.isEmpty ? nil : result
    }

    func validate(fields: [FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
        let result = {name}FieldsValidateModel(validations: validations, fields: fields) ?? []

        validations.replace(with: result)

        return validations.status
    }
}
```

**A Fields validate replaces its own fields; nothing assigns the array.** `Validations.validations` is `private(set)`; `append(_:)`, `append(contentsOf:)`, `replace(with:)` and `removeAll(fieldIds:)` are the whole of the API, and an assignment does not compile. One `Validations` is the single accumulator every level adds to — the Fields rules, then the `DataModel`'s own `validateModel(in:)` rules, then the server's answer on the way back. A Fields rule set owns exactly the fields it names, so it hands its answer to `replace(with:)`, which swaps those fields' results and leaves every other level's alone; re-validating a form as the user types then re-answers for those fields instead of stacking a second copy of the same message. **OCP:** each level extends the judgement without modifying what the level before it found; assign the array instead and a `DataModel` adding a rule after the Fields rules erases them, so the user is told about the second problem with their form only after fixing the first.

**A rule about the model as a whole names no field.** `ValidationResult(status:message:)` — the initializer without a field — makes a model-level result, and `ValidationResult.Message.addressesModel` is how such a message says it names none. Field views ignore it; the form shows it by applying `.withFormValidations()`. When a conflict is genuinely *between* two fields, name both with `.init(status:fieldIds:message:)` instead.

---

## File 2: {Name}FieldsMessages.swift

**Location:** `Sources/{ViewModelsTarget}/FieldModels/{Name}FieldsMessages.swift`

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// Localized validation messages for {Name}Fields.
///
/// Each property maps to a key path in {Name}FieldsMessages.yml.
/// The @FieldValidationModel macro generates propertyNames() for localization binding.
@FieldValidationModel public struct {Name}FieldsMessages {
    // MARK: - Field Titles & Placeholders (used by FormField definitions)

    // Note: Titles and placeholders are referenced directly in FormField definitions
    // via .localized(for:propertyName:messageKey:) - no properties needed here.

    // MARK: - Validation Messages

    // @LocalizedString("fieldName", messageGroup: "validationMessages", messageKey: "required")
    // public var fieldNameRequiredMessage

    // @LocalizedString("fieldName", messageGroup: "validationMessages", messageKey: "outOfRange")
    // public var fieldNameOutOfRangeMessage

    public init() {}
}
```

---

## File 3: {Name}FieldsMessages.yml

**Location:** `{ResourcesPath}/FieldModels/{Name}FieldsMessages.yml`

```yaml
en:
  {Name}FieldsMessages:
    fieldName:
      title: "Field Display Name"
      placeholder: "Enter value..."
      validationMessages:
        required: "Field name is required"
        outOfRange: "Field name must be between X and Y characters"
```

---

## Complete Example: IdeaFields

A full implementation showing multiple fields, enums, and validation.

### IdeaFields.swift

```swift
import FOSFoundation
import FOSMVVM
import Foundation

/// Form Specification for Idea entities.
///
/// Defines the editable fields, validation rules, and localized messages
/// for creating and editing Ideas.
public protocol IdeaFields: ValidatableModel, Codable, Sendable {
    var id: ModelIdType? { get set }
    var content: String { get set }
    var department: Department { get set }
    var status: IdeaStatus { get set }
    var metadata: [String: String]? { get set }
}

public enum Department: CaseIterable, Equatable, Codable, Sendable {
    case strategic
    case product
    case content
    case consulting
    case operations
}

public enum IdeaStatus: CaseIterable, Equatable, Codable, Sendable {
    case queued
    case exploring
    case parking
    case implementing
    case complete
    case discarded
}

public extension IdeaFields {
    // MARK: Field Constraints

    static var contentRange: ClosedRange<Int> { 1...10000 }

    // MARK: FormField Definitions

    static var contentField: FormField<String?> { .init(
        fieldId: #fieldId(\Self.content),
        title: .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageKey: "title"),
        placeholder: .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageKey: "placeholder"),
        type: .textArea(inputType: .text),
        options: [
            .required(value: true)
        ] + FormInputOption.rangeLength(contentRange)
    ) }

    static var departmentField: FormField<String?> { .init(
        fieldId: #fieldId(\Self.department),
        title: .localized(for: IdeaFieldsMessages.self, propertyName: "department", messageKey: "title"),
        type: .select,
        options: [.required(value: true)]
    ) }

    static var statusField: FormField<String?> { .init(
        fieldId: #fieldId(\Self.status),
        title: .localized(for: IdeaFieldsMessages.self, propertyName: "status", messageKey: "title"),
        type: .select,
        options: [.required(value: true)]
    ) }

    // MARK: Validation Message Mints

    static var contentRequiredMessage: LocalizableString {
        .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageGroup: "validationMessages", messageKey: "required")
    }

    static var contentOutOfRangeMessage: LocalizableString {
        .localized(for: IdeaFieldsMessages.self, propertyName: "content", messageGroup: "validationMessages", messageKey: "outOfRange")
    }

    // MARK: Validation Methods

    internal func validateContent(_ fields: [FormFieldBase]?) -> [ValidationResult]? {
        guard fields?.contains(Self.contentField) ?? true else {
            return nil
        }

        var result = [ValidationResult]()

        if content.isEmpty {
            result.append(.init(
                status: .error,
                field: Self.contentField,
                message: Self.contentRequiredMessage
            ))
        } else if !Self.contentRange.contains(NSString(string: content).length) {
            result.append(.init(
                status: .error,
                field: Self.contentField,
                message: Self.contentOutOfRangeMessage
            ))
        }

        return result.isEmpty ? nil : result
    }

    // MARK: ValidatableModel

    func ideaFieldsValidateModel(
        validations: Validations,
        fields: [FormFieldBase]?
    ) -> [ValidationResult]? {
        var result = [ValidationResult]()
        result += validateContent(fields)
        return result.isEmpty ? nil : result
    }

    func validate(fields: [FormFieldBase]?, validations: Validations) -> ValidationResult.Status? {
        let result = ideaFieldsValidateModel(validations: validations, fields: fields) ?? []
        validations.replace(with: result)
        return validations.status
    }
}
```

### IdeaFieldsMessages.swift

```swift
import FOSFoundation
import FOSMVVM
import Foundation

@FieldValidationModel public struct IdeaFieldsMessages {
    @LocalizedString("content", messageGroup: "validationMessages", messageKey: "required")
    public var contentRequiredMessage

    @LocalizedString("content", messageGroup: "validationMessages", messageKey: "outOfRange")
    public var contentOutOfRangeMessage

    public init() {}
}
```

### IdeaFieldsMessages.yml

```yaml
en:
  IdeaFieldsMessages:
    content:
      title: "Idea Content"
      placeholder: "Describe your idea..."
      validationMessages:
        required: "Content is required"
        outOfRange: "Content must be between 1 and 10,000 characters"
    department:
      title: "Department"
    status:
      title: "Status"
```

---

## Adopting the Form Specification

### In a DataModel (Fluent)

```swift
final class Idea: DataModel, IdeaFields, Hashable, @unchecked Sendable {
    @ID(key: .id) var id: ModelIdType?
    @Field(key: "content") var content: String
    @Field(key: "department") var department: Department
    @Field(key: "status") var status: IdeaStatus
    @OptionalField(key: "metadata") var metadata: [String: String]?

    init() {}
}
```

An adopter declares the fields and nothing else: the `FormField` definitions, the message mints and the validation rules all live on the protocol's extension, so every adopter runs the same checks and reports them with the same words.

### In a RequestBody

```swift
public final class CreateIdeaRequest: CreateRequest, @unchecked Sendable {
    public struct RequestBody: IdeaFields, ServerRequestBody, Stubbable {
        public var id: ModelIdType? = nil
        public var content: String
        public var department: Department
        public var status: IdeaStatus = .queued
        public var metadata: [String: String]?

        public init(content: String, department: Department) {
            self.content = content
            self.department = department
        }

        public static func stub() -> Self {
            .init(content: "Stub idea", department: .product)
        }
    }
}
```

### In Tests

```swift
private struct TestIdea: IdeaFields {
    var id: ModelIdType?
    var content: String
    var department: Department
    var status: IdeaStatus
    var metadata: [String: String]?

    init(
        id: ModelIdType? = .init(),
        content: String = "Test content",
        department: Department = .product,
        status: IdeaStatus = .queued,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.content = content
        self.department = department
        self.status = status
        self.metadata = metadata
    }
}
```

---

## Quick Reference: Naming Conventions

| Concept | Pattern | Example |
|---------|---------|---------|
| Protocol | `{Name}Fields` | `IdeaFields` |
| Messages struct | `{Name}FieldsMessages` | `IdeaFieldsMessages` |
| FormField definition | `{fieldName}Field` | `contentField` |
| Range constant | `{fieldName}Range` | `contentRange` |
| Validate method | `validate{FieldName}` | `validateContent` |
| Required message (static mint) | `{fieldName}RequiredMessage` | `contentRequiredMessage` |
| OutOfRange message (static mint) | `{fieldName}OutOfRangeMessage` | `contentOutOfRangeMessage` |
