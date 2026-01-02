# Bugfix: More Embedded ViewModel Support

**Branch:** `bugfix/more-embedded-viewmodel-support`
**Test Command:** `swift test --filter EmbeddedViewModelTests`
**Full Test Suite:** `swift test`

---

## Architecture Context

FOSMVVM is a Model-View-ViewModel framework with a deferred localization system:

1. **`@ViewModel` macro** generates `propertyNames()` mapping `localizationId` → property names for `@LocalizedString` etc.
2. **`LocalizingEncoder`** (subclass of `JSONEncoder`) resolves localization during encoding via `.toJSON(encoder:).fromJSON()` round-trip
3. **`@LocalizedSubs`** property wrapper uses `encoder.currentModel(for:)` to access substitution values via KeyPath at encode time
4. **`allPropertyNames()`** traverses object graph using Mirror to collect all embedded ViewModels' property names

**Key protocols:**
- `RetrievablePropertyNames` - has `propertyNames() -> [LocalizableId: String]`
- `ViewModel` - conforms to `RetrievablePropertyNames`, has `vmId`
- `Localizable` - base for `LocalizableString`, `LocalizableInt`, etc.

---

## Problem Summary

The FOSMVVM localization system has two issues with embedded ViewModels:

### Issue 1: Optional ViewModels Not Collected in `allPropertyNames()`

**Location:** `Sources/FOSMVVM/Extensions/JSONEncoder.swift:172-197`

**Problem:** The `allPropertyNames()` extension uses `as? RetrievablePropertyNames` to find embedded ViewModels, but this cast fails for `Optional<ViewModel>` because `Optional` doesn't conform to `RetrievablePropertyNames`.

**Affected patterns:**
- `let child: ChildViewModel?` - Optional ViewModel
- `let children: [ChildViewModel]?` - Optional array of ViewModels
- `let children: [ChildViewModel?]` - Array of optional ViewModels
- `let childMap: [String: ChildViewModel]` - Dictionary with ViewModel values

### Issue 2: Multiple Instances of Same ViewModel Type Cannot Be Distinguished

**Location:** `Sources/FOSMVVM/Extensions/JSONEncoder.swift` (currentModel tracking)

**Problem:** The `currentModel` is stored by type in `userInfo`. When encoding multiple instances of the same ViewModel type (e.g., `innerViewModel1: InnerViewModel` and `innerViewModel2: InnerViewModel`), both get the same model reference when `@LocalizedSubs` or `@LocalizedCompoundString` access their substitutions via KeyPath.

**Root cause:** `setCurrentModel()` overwrites the single `userInfo[.currentModelKey]` value, and during nested encoding, the internal `Encoder` instances may not see real-time updates to the JSONEncoder's `userInfo`.

**Documented in:** `Tests/FOSMVVMTests/Localization/EmbeddedViewModelTests.swift:100-121` (`BrokenViewModel`)

---

## Solution Design

### Issue 1 Fix: Handle Optionals in `allPropertyNames()`

**Approach:** Add optional unwrapping logic before type checking.

```swift
// Helper to unwrap Optional values using Mirror
private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }
    return mirror.children.first?.value
}
```

**Modified `allPropertyNames()` logic:**

```swift
func allPropertyNames() -> [LocalizableId: String] {
    var result = (self as? RetrievablePropertyNames)?.propertyNames() ?? [:]
    let mirror = Mirror(reflecting: self)

    for child in mirror.children {
        // Unwrap optional if needed
        let unwrappedValue = unwrapOptional(child.value) ?? child.value

        if let model = unwrappedValue as? RetrievablePropertyNames {
            // Direct ViewModel (or unwrapped optional ViewModel)
            result.merge(model.allPropertyNames()) { _, new in new }
        } else if let collection = unwrappedValue as? (any Collection) {
            for element in collection {
                let unwrappedElement = unwrapOptional(element) ?? element
                if let model = unwrappedElement as? RetrievablePropertyNames {
                    result.merge(model.allPropertyNames()) { _, new in new }
                }
            }
        }
        // TODO: Handle Dictionary values
    }
    return result
}
```

### Issue 2 Fix: Path-Based Model Registry

**Problem insight:** The `LocalizingEncoder.encode(_:)` override only triggers at the top level. When nested ViewModels are encoded via Codable synthesis, their `encode(to:)` methods run but we have no hook to update `currentModel`. A simple stack won't work because we can't push/pop at the right times.

**Approach:** Pre-register all ViewModel instances at their coding paths before encoding starts. During encoding, use `encoder.codingPath` to look up the correct model instance.

**New class:**

```swift
private final class ModelRegistry: @unchecked Sendable {
    private var models: [String: Any] = [:]

    func register(_ model: Any, at path: String) {
        models[path] = model
    }

    func model<T>(for type: T.Type, at codingPath: [CodingKey]) -> T? {
        // Walk up the coding path to find the nearest ancestor of requested type
        var pathParts = codingPath.map { $0.stringValue }
        while !pathParts.isEmpty {
            pathParts.removeLast() // Remove current property, look at its container
            let pathKey = pathParts.joined(separator: ".")
            if let model = models[pathKey] as? T {
                return model
            }
        }
        // Check root model
        return models[""] as? T
    }
}
```

**Pre-registration function:**

```swift
private func registerModels(from value: Any, path: String, into registry: ModelRegistry) {
    // Register this value if it's a RetrievablePropertyNames
    if value is (any RetrievablePropertyNames) {
        registry.register(value, at: path)
    }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        guard let label = child.label else { continue }
        // Strip "_" prefix from property wrapper storage names
        let cleanLabel = String(label.trimmingPrefix("_"))
        let childPath = path.isEmpty ? cleanLabel : "\(path).\(cleanLabel)"

        // Handle optionals
        let unwrappedValue = unwrapOptional(child.value)

        if let unwrapped = unwrappedValue {
            // Recurse for nested models
            registerModels(from: unwrapped, path: childPath, into: registry)
        }

        // Handle arrays
        if let array = (unwrappedValue ?? child.value) as? [Any] {
            for (index, element) in array.enumerated() {
                let elementPath = "\(childPath).\(index)"
                if let unwrappedElement = unwrapOptional(element) ?? element as Any? {
                    registerModels(from: unwrappedElement, path: elementPath, into: registry)
                }
            }
        }
    }
}
```

**Modified `LocalizingEncoder.encode(_:)`:**

```swift
override func encode(_ value: some Encodable) throws -> Data {
    // Build model registry before encoding
    let registry = ModelRegistry()
    registerModels(from: value, path: "", into: registry)
    userInfo[.modelRegistryKey] = registry

    // Continue with existing property name merging...
    let newPropertyNames: [LocalizableId: String]
    if let model = value as? (any RetrievablePropertyNames) {
        newPropertyNames = model.allPropertyNames()
    } else {
        newPropertyNames = value.allPropertyNames()
    }
    propertyNameBindings = newPropertyNames

    // Encode
    if let viewModel = value as? any ViewModel {
        return try encodeViewModel(viewModel)
    } else {
        return try super.encode(value)
    }
}
```

**Modified `currentModel(for:)`:**

```swift
extension Encoder {
    func currentModel<T>(for type: T.Type) -> T? {
        guard let registry = userInfo[.modelRegistryKey] as? ModelRegistry else {
            return nil
        }
        return registry.model(for: type, at: codingPath)
    }
}
```

**How this solves BrokenViewModel:**

When encoding `BrokenViewModel`:
1. Pre-registration builds: `{"": brokenVM, "innerViewModel1": innerVM1, "innerViewModel2": innerVM2}`
2. When encoding `innerViewModel1.innerSubs`:
   - `codingPath` = `["innerViewModel1", "innerSubs"]`
   - Walk up: check `"innerViewModel1"` → finds `innerVM1` of type `InnerViewModel` ✓
3. When encoding `innerViewModel2.innerSubs`:
   - `codingPath` = `["innerViewModel2", "innerSubs"]`
   - Walk up: check `"innerViewModel2"` → finds `innerVM2` of type `InnerViewModel` ✓

Each gets the correct model instance based on its position in the encoding hierarchy!

---

## Files to Modify

### Primary Changes

1. **`Sources/FOSMVVM/Extensions/JSONEncoder.swift`**
   - Add `unwrapOptional(_:)` helper function
   - Modify `allPropertyNames()` to handle arrays (throw error for unsupported types like optionals/dictionaries)
   - Add `ModelRegistry` class for path-based model lookup
   - Add `registerModels(from:path:into:)` function for pre-registration
   - Add `.modelRegistryKey` to `CodingUserInfoKey` extension
   - Modify `LocalizingEncoder.encode(_:)` to build registry before encoding
   - Update `currentModel(for:)` to use registry with `codingPath` lookup
   - Can remove old `setCurrentModel` / single-model tracking

### Test Changes

2. **`Tests/FOSMVVMTests/Localization/EmbeddedViewModelTests.swift`**
   - Rename `BrokenViewModel` → `MultipleInnerViewModel` (enable as working test)
   - Add test `multipleEmbeddedViewModelsOfSameType()` verifying correct substitution values
   - Verify `innerViewModel1` gets `SubInt: 42` and `innerViewModel2` gets `SubInt: 43`

---

## Test Cases to Add

```swift
// Test multiple same-type ViewModels (currently BrokenViewModel)
@Test func multipleEmbeddedViewModelsOfSameType() throws {
    let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
    let vm: MultipleInnerViewModel = try .stub().toJSON(encoder: vmEncoder).fromJSON()

    // innerViewModel1 should have subInt: 42
    #expect(try vm.innerViewModel1.innerSubs.localizedString == "SubInt: 42")
    // innerViewModel2 should have subInt: 43 (NOT 42!)
    #expect(try vm.innerViewModel2.innerSubs.localizedString == "SubInt: 43")
}
```

---

## Implementation Order

1. **Phase 1: Add ModelRegistry infrastructure**
   - Add `unwrapOptional()` helper function
   - Add `ModelRegistry` class
   - Add `registerModels(from:path:into:)` function
   - Add `.modelRegistryKey` to `CodingUserInfoKey`

2. **Phase 2: Update encoding flow**
   - Modify `LocalizingEncoder.encode(_:)` to build registry before encoding
   - Update `currentModel(for:)` to use registry with `codingPath` lookup
   - Update `allPropertyNames()` to use same traversal logic (handle arrays, throw for unsupported types)

3. **Phase 3: Tests**
   - Enable `BrokenViewModel` test (rename to `MultipleInnerViewModel`)
   - Verify existing tests still pass
   - Verify new test passes with correct substitution values

4. **Phase 4: Cleanup**
   - Remove old `setCurrentModel` / single-model tracking
   - Run full test suite

---

## Current Code to Modify

### File: `Sources/FOSMVVM/Extensions/JSONEncoder.swift`

**Current `LocalizingEncoder` class (lines 127-170):**
```swift
private final class LocalizingEncoder: JSONEncoder {
    override func encode(_ value: some Encodable) throws -> Data {
        let parentModel = userInfo[.currentModelKey]
        let parentPropertyNames = propertyNameBindings

        let newPropertyNames: [LocalizableId: String]
        if let model = value as? (any RetrievablePropertyNames) {
            newPropertyNames = model.allPropertyNames()
            setCurrentModel(model)
        } else {
            newPropertyNames = value.allPropertyNames()
        }
        var propertyNames = propertyNameBindings ?? [:]
        for (key, value) in newPropertyNames {
            propertyNames[key] = value
        }
        propertyNameBindings = propertyNames

        let result: Data
        if let viewModel = value as? any ViewModel {
            result = try encodeViewModel(viewModel)
        } else {
            result = try super.encode(value)
        }
        setCurrentModel(parentModel)
        propertyNameBindings = parentPropertyNames

        return result
    }
    // ...
}
```

**Current `allPropertyNames()` extension (lines 172-197):**
```swift
private extension Encodable {
    func allPropertyNames() -> [LocalizableId: String] {
        var result = (self as? RetrievablePropertyNames)?.propertyNames() ?? [:]

        let mirror = Mirror(reflecting: self)

        for child in mirror.children {
            if let model = child.value as? RetrievablePropertyNames {
                for (key, value) in model.allPropertyNames() {
                    result[key] = value
                }
            } else if let collection = child.value as? (any Collection) {
                for child in collection {
                    if let model = child as? RetrievablePropertyNames {
                        for (key, value) in model.allPropertyNames() {
                            result[key] = value
                        }
                    }
                }
            }
        }

        return result
    }
}
```

**Current `currentModel(for:)` (lines 225-227):**
```swift
extension Encoder {
    func currentModel<T>(for type: T.Type) -> T? {
        userInfo[.currentModelKey] as? T
    }
    // ...
}
```

**Current `CodingUserInfoKey` extension (lines 301-318):**
```swift
private extension CodingUserInfoKey {
    static var localeKey: CodingUserInfoKey { ... }
    static var localizationStoreKey: CodingUserInfoKey { ... }
    static var propertyNamesKey: CodingUserInfoKey { ... }
    static var currentModelKey: CodingUserInfoKey { ... }
}
```

### File: `Tests/FOSMVVMTests/Localization/EmbeddedViewModelTests.swift`

**Current `BrokenViewModel` (lines 100-121) - marked as TODO:**
```swift
// TODO: Future

private struct BrokenViewModel: ViewModel {
    @LocalizedString var mainString

    // This doesn't work because there's no way to encode
    // the inner property values and keep them separate.
    // Current lookup is only by type.
    let innerViewModel1: InnerViewModel
    let innerViewModel2: InnerViewModel

    var vmId: FOSMVVM.ViewModelId

    static func stub() -> Self {
        .init(
            innerViewModel1: .stub(subInt: 42),
            innerViewModel2: .stub(subInt: 43),
            vmId: .init()
        )
    }
}
```

**Test YAML already exists at:** `Tests/FOSMVVMTests/TestYAML/` with `InnerViewModel` localization including `innerSubs: "SubInt: %{subInt}"`

---

## Resolved Questions

1. **Dictionary support:** Skip for now - throw error for unsupported types (per user request)

2. **Thread safety:** Use `@unchecked Sendable` - encoding is single-threaded (per user confirmation)

3. **Optionals/other patterns:** Focus on arrays; throw descriptive errors for unsupported types to guide users

4. **Macro vs Mirror approach:** Use Mirror-based traversal in `JSONEncoder.swift`. The macro's job remains generating `propertyNames()` for direct properties; runtime handles object graph traversal.

5. **Custom CodingKeys:** Assume default CodingKeys (property names match coding keys). Custom CodingKeys with renamed properties are not supported for embedded ViewModels. This can be documented and enhanced later if needed.

---

## Step-by-Step Implementation

### Step 1: Add helper and ModelRegistry class
In `Sources/FOSMVVM/Extensions/JSONEncoder.swift`, add before `LocalizingEncoder`:

```swift
/// Unwraps Optional values using Mirror reflection
private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }
    return mirror.children.first?.value
}

/// Registry of models keyed by their coding path for lookup during encoding
private final class ModelRegistry: @unchecked Sendable {
    private var models: [String: Any] = [:]

    func register(_ model: Any, at path: String) {
        models[path] = model
    }

    func model<T>(for type: T.Type, at codingPath: [CodingKey]) -> T? {
        var pathParts = codingPath.map { $0.stringValue }
        while !pathParts.isEmpty {
            pathParts.removeLast()
            let pathKey = pathParts.joined(separator: ".")
            if let model = models[pathKey] as? T {
                return model
            }
        }
        return models[""] as? T
    }
}

/// Pre-registers all RetrievablePropertyNames in the object graph
private func registerModels(from value: Any, path: String, into registry: ModelRegistry) {
    if value is (any RetrievablePropertyNames) {
        registry.register(value, at: path)
    }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        guard let label = child.label else { continue }
        let cleanLabel = String(label.trimmingPrefix("_"))
        let childPath = path.isEmpty ? cleanLabel : "\(path).\(cleanLabel)"

        let unwrappedValue = unwrapOptional(child.value)

        if let unwrapped = unwrappedValue {
            registerModels(from: unwrapped, path: childPath, into: registry)
        }

        if let array = (unwrappedValue ?? child.value) as? [Any] {
            for (index, element) in array.enumerated() {
                let elementPath = "\(childPath).\(index)"
                if let unwrappedElement = unwrapOptional(element) {
                    registerModels(from: unwrappedElement, path: elementPath, into: registry)
                } else {
                    registerModels(from: element, path: elementPath, into: registry)
                }
            }
        }
    }
}
```

### Step 2: Add CodingUserInfoKey
Add to the `CodingUserInfoKey` extension:
```swift
static var modelRegistryKey: CodingUserInfoKey {
    CodingUserInfoKey(rawValue: "_*MoDeL_ReGiStRy*_")!
}
```

### Step 3: Update LocalizingEncoder.encode(_:)
Replace the method to build registry before encoding:
```swift
override func encode(_ value: some Encodable) throws -> Data {
    // Build model registry before encoding
    let registry = ModelRegistry()
    registerModels(from: value, path: "", into: registry)
    userInfo[.modelRegistryKey] = registry

    // Merge property names
    propertyNameBindings = value.allPropertyNames()

    // Encode
    if let viewModel = value as? any ViewModel {
        return try encodeViewModel(viewModel)
    } else {
        return try super.encode(value)
    }
}
```

### Step 4: Update currentModel(for:)
Replace to use registry with codingPath:
```swift
func currentModel<T>(for type: T.Type) -> T? {
    guard let registry = userInfo[.modelRegistryKey] as? ModelRegistry else {
        return nil
    }
    return registry.model(for: type, at: codingPath)
}
```

### Step 5: Update allPropertyNames()
Update to use `unwrapOptional`:
```swift
private extension Encodable {
    func allPropertyNames() -> [LocalizableId: String] {
        var result = (self as? RetrievablePropertyNames)?.propertyNames() ?? [:]
        let mirror = Mirror(reflecting: self)

        for child in mirror.children {
            let unwrappedValue = unwrapOptional(child.value)

            if let model = (unwrappedValue ?? child.value) as? RetrievablePropertyNames {
                result.merge(model.allPropertyNames()) { _, new in new }
            } else if let collection = (unwrappedValue ?? child.value) as? (any Collection) {
                for element in collection {
                    let unwrappedElement = unwrapOptional(element)
                    if let model = (unwrappedElement ?? element) as? RetrievablePropertyNames {
                        result.merge(model.allPropertyNames()) { _, new in new }
                    }
                }
            }
        }
        return result
    }
}
```

### Step 6: Enable test
In `Tests/FOSMVVMTests/Localization/EmbeddedViewModelTests.swift`:
1. Remove `// TODO: Future` comment
2. Rename `BrokenViewModel` to `MultipleInnerViewModel`
3. Add test:
```swift
@Test func multipleEmbeddedViewModelsOfSameType() throws {
    let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
    let vm: MultipleInnerViewModel = try .stub().toJSON(encoder: vmEncoder).fromJSON()

    #expect(try vm.innerViewModel1.innerSubs.localizedString == "SubInt: 42")
    #expect(try vm.innerViewModel2.innerSubs.localizedString == "SubInt: 43")
}
```

### Step 7: Cleanup
Remove old `setCurrentModel` method and `currentModelKey` if no longer used.

### Step 8: Verify
```bash
swift test --filter EmbeddedViewModelTests
swift test
```
