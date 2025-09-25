# ``FOSReporting``

A Swift framework for rendering SwiftUI views to PDF rendering.

## Overview

FOSReporting provides a SwiftUI-based approach to creating professional reports and documents across Apple platforms. The framework emphasizes type safety, declarative syntax, and seamless integration with SwiftUI views.

### Key Features

- **PDF Generation**: Convert SwiftUI views directly to PDF documents
- **Cross-Platform**: Support for iOS, iPadOS, and macOS
- **Flexible Page Layouts**: Built-in support for standard page sizes and orientations
- **Multi-Page Documents**: Easy creation of complex, multi-page reports
- **SwiftUI Integration**: Leverage your existing SwiftUI knowledge and components

## Getting Started

To begin using FOSReporting, import the framework and start with simple PDF generation:

```swift
import FOSReporting
import SwiftUI

// Generate a simple PDF
let pdfData = try await PDFRenderer.render(
    pageSize: .a4(),
    pageCount: 1
) { pageIndex in
    Text("Hello, FOSReporting! - Page # \(pageIndex)")
        .font(.largeTitle)
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``PDFRenderer``
