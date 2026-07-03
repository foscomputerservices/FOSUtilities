# FOSReporting API Catalog

Curated map of FOSReporting's public API, organized by task — PDF generation
from SwiftUI views. Apple platforms only (iOS, macOS, visionOS, watchOS): on
Linux this module produces no symbol graph, so the audit skips this file's
stale check there — it runs fully on macOS. Before hand-rolling a
Core Graphics PDF context or a UIGraphicsPDFRenderer — check here first.

## PDF Rendering

One entry point: render any SwiftUI view hierarchy into a multi-page PDF,
with page geometry described by a small size/orientation vocabulary.

### Render SwiftUI views as a PDF document — `PDFRenderer` / `render()`
Reach for this when: generating a PDF (reports, receipts, printable documents)
whose pages are ordinary SwiftUI views. The page-content closure receives the
0-based page index and is called once per page; the result is the finished
document as `Data`. Synchronous and `@MainActor` — call it from the main actor
and get the data back without awaiting. On iOS/iPadOS an optional `format:`
parameter carries `UIGraphicsPDFRendererFormat` document metadata (title,
author); the macOS overload has no format parameter. Content is sized to the
page — anything that overflows the page bounds is clipped, and pagination is
yours: one closure call renders exactly one page.
Don't hand-roll `CGContext`/`UIGraphicsPDFRenderer` plumbing — this handles the
per-platform context setup and coordinate flipping for you.

```swift
let pdfData = try PDFRenderer.render(
    pageSize: .usLetter(),
    pageCount: 3
) { pageIndex in
    VStack {
        Text("Page \(pageIndex + 1) of 3").font(.title)
        Divider()
        Text("Content for page \(pageIndex + 1)")
    }
    .padding()
}
try pdfData.write(to: outputUrl)
```

### Choose page size and orientation — `PageSize` / `PageOrientation`
Reach for this when: describing the page geometry for `render()`. Factory
methods cover the standard formats — `.a4()` and `.usLetter()`, each defaulting
to `.portrait` — and the initializer takes custom dimensions in points
(1 point = 1/72 inch).

```swift
let letter = PDFRenderer.PageSize.usLetter() // portrait by default
let a4Wide = PDFRenderer.PageSize.a4(orientation: .landscape)
let square = PDFRenderer.PageSize(width: 500, height: 500)
```
