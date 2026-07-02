# Getting Started With View Model Testing

Quickly test your *ViewModel*s and SwiftUI Views

## Configuration

The *LocalizableTestCase* provides a convenient way to test your *ViewModel*s, which
is based on the [swift-testing](https://github.com/swiftlang/swift-testing.git) framework.

Initialization of *LocalizableTestCase* is required for each conformance of the protocol.
This can be accomplished by adding an extension that should work for all of your tests:

```swift
@Suite("My Test Suite", .serialized)
struct MyViewModelTests: LocalizableTestCase {

    let locStore: LocalizationStore
    var locales: Set<Locale> {[Self.en, Self.es]}
    init() throws {
        self.locStore = try Self.loadLocalizationStore(bundle: .module)
    }
}
```

## *ViewModel* Testing

Because *ViewModel*s have no behavior, calling ``expectFullViewModelTests`` is all
that is needed to test each *ViewModel*.  This method will test the following:

- Round-trip encoding and decoding of the *ViewModel*
- That all supported back-versions are decodable by the latest code
- That all @LocalizedString properties have translations

> Important: The version baseline JSON (`<Name>ViewModel_<version>.json`, written under
> `Tests/.../.VersionedTestJSON/` beside your test) is a **committed artifact** for any
> app that ships a versioned wire contract — commit it so it can catch an accidental
> wire-shape change across builds. `expectFullViewModelTests` forwards `#filePath`/`#line`
> so the baseline lands next to the calling test. (FOSUtilities' *own* baselines are
> regenerable fixtures with no shipped contract and are deliberately git-ignored — the
> opposite policy from a downstream app.)

### Example

```swift
@Suite("My Test Suite", .serialized)
struct MyViewModelTests: LocalizableTestCase {

    @Test func viewModel() async throws {
        try await expectFullViewModelTests(MyViewModel.self)
    }

    let locStore: LocalizationStore
    var locales: Set<Locale> {[Self.en, Self.es]}
    init() throws {
        self.locStore = try Self.loadLocalizationStore(bundle: .module)
    }
}
```

## Supporting Bundle Loading Using Package Manager and Xcode projects

Bundle loading is different depending on whether the resources are managed by an Xcode
project or by a Swift Package.  An Xcode project loads the bundle via Bundle.main whereas
Swift Package manger uses Bundle.module.

To unify this support one suggestion is to create an extension on Bundle as follows:

```swift
import Foundation

#if XCODEPROJ
extension Bundle {
    // This mimicks the automatically generated module property generated for libraries
    // and allows tests to run when hosted in the app like done with xcodeprojects.
    // The XCODEPROJ flag is set in the xcodeproj for the ActiveViewModelsTests target,
    // Build Settings->Swift Compiler - Custom Flags -> Other Swift Flags
    // The value is: -D XCODEPROJ
    static var module: Bundle { main }
}
#endif
```

Then, in the Xcode project's Build Settings for the UnitTests target do the following:

1. Search for 'other swift flags'
1. Add: -D XCODEPROJ

This will enable the project to use Bundle.module in all cases.

![Xcode Example](XcodeSettings)
