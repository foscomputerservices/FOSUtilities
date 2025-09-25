# Getting Started with FOSReporting

Learn the basics of FOSReporting and create your first PDF document.

## Overview

FOSReporting makes it simple to convert your SwiftUI views into professional PDF documents. This guide will walk you through the fundamental concepts and help you create your first report.

## Basic Concepts

FOSReporting is built around three core concepts:

1. **PDFRenderer**: The main entry point for generating PDFs
2. **Page Size**: Defines the dimensions and orientation of your document
3. **Content Builder**: SwiftUI views that define your document's appearance

## Your First PDF

Let's create a simple single-page PDF document:

```swift
import FOSReporting
import SwiftUI

@MainActor
func createSimplePDF() async throws -> Data {
    try PDFRenderer.render(
        pageSize: .a4(),
        pageCount: 1
    ) { pageIndex in
        VStack(alignment: .leading, spacing: 20) {
            Text("My First Report")
                .font(.largeTitle)
                .bold()
            
            Text("Generated with FOSReporting")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("This is a simple PDF document created using FOSReporting. ")
            + Text("You can use any SwiftUI view to create your content.")
                .foregroundColor(.blue)
            
            Spacer()
            
            HStack {
                Text("Page \(pageIndex + 1)")
                Spacer()
                Text(Date(), style: .date)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(40)
    }
}
```