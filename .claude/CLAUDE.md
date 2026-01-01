# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Run all tests
swift test

# Run a single test (Swift Testing)
swift test --filter TestClassName

# Format code (auto-adds Apache 2.0 license header)
swiftformat .

# Lint code
swiftlint
```

## Architecture Overview

FOSUtilities is a Swift Package providing MVVM infrastructure for binding SwiftUI apps to Vapor web services, plus foundation utilities and testing support.

### Library Hierarchy

```
FOSFoundation          - Base utilities (URL/JSON extensions, async helpers, string utils)
    ↓
FOSMVVM               - MVVM pattern implementation with localization support
    ↓                   (uses FOSMacros for @ViewModel, @LocalizedString, etc.)
    ├→ FOSMVVMVapor    - Vapor server integration (macOS/Linux only)
    ├→ FOSReporting    - PDF generation (Apple platforms only)
    └→ FOSTestingUI    - SwiftUI test utilities
         ↓
FOSTesting            - Test base classes and mocking
    ↓
FOSTestingVapor       - Vapor-specific test support (macOS/Linux only)
```

### Key Patterns

**ViewModel Declaration:**
```swift
@ViewModel
public struct MyViewModel: RequestableViewModel {
    public typealias Request = MyRequest
    @LocalizedString public var title
    public var vmId = ViewModelId()
    public init() {}
    public static func stub() -> Self { .init() }
}
```

**Localization:** YAML-based stores (see `Sources/FOSMVVM/Localization/`). Properties use `@LocalizedString`, `@LocalizedInt`, `@LocalizedDate` wrappers.

**Macros:** `FOSMacros` provides `@ViewModel`, `@FieldValidationModel`, `@ViewModelFactory` - only compile on macOS/Linux.

### Platform Constraints

- Swift 6.0+ required (`swiftLanguageModes: [.v6]`)
- `FOSMVVMVapor` / `FOSTestingVapor`: macOS/Linux only
- `FOSReporting`: Apple platforms only (iOS, macOS, visionOS, watchOS)
- `FOSMacros`: macOS/Linux/Windows only (macro compilation)

### Test Notes

- Uses Swift Testing framework (not XCTest), except macro tests which require XCTest
- Test YAML fixtures located in `Tests/FOSMVVMTests/TestYAML/` and `Tests/FOSMVVMVaporTests/TestYAML/`
