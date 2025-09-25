// PDFRenderer.swift
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

#if canImport(AppKit)
import AppKit
#endif
import PDFKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Original Idea Credit: https://youtu.be/FVssSeric50?si=E8wHEOfXKxBwn9kt

/// A utility for rendering SwiftUI views as PDF documents.
///
/// `PDFRenderer` provides a cross-platform solution for generating PDF documents
/// from SwiftUI views on both iOS/iPadOS and macOS platforms.
///
/// ## Overview
///
/// The renderer supports:
/// - Multiple page sizes (A4, US Letter, custom)
/// - Portrait and landscape orientations
/// - Multi-page documents
/// - Platform-specific rendering optimizations
///
/// ## Example Usage
///
/// ```swift
/// // Create a single-page PDF
/// let pdfData = try await PDFRenderer.render(
///     pageSize: .a4(),
///     pageCount: 1
/// ) { _ in
///     Text("Hello, PDF!")
///         .font(.title)
/// }
///
/// // Create a multi-page document
/// let multiPagePDF = try await PDFRenderer.render(
///     pageSize: .usLetter(orientation: .landscape),
///     pageCount: 10
/// ) { pageIndex in
///     VStack {
///         Text("Page \(pageIndex + 1)")
///         Divider()
///         Text("Content goes here")
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Page Configuration
/// - ``PageSize``
/// - ``PageSize/PageOrientation``
///
/// ### Rendering
/// - ``render(pageSize:pageCount:format:content:)``
public enum PDFRenderer {
    /// Defines the size and orientation of PDF pages.
    ///
    /// Use the provided factory methods for standard page sizes or create
    /// custom sizes using the initializer.
    ///
    /// ## Common Page Sizes
    ///
    /// ```swift
    /// // Standard A4 page in portrait
    /// let a4Portrait = PageSize.a4()
    ///
    /// // US Letter in landscape
    /// let letterLandscape = PageSize.usLetter(orientation: .landscape)
    ///
    /// // Custom size
    /// let custom = PageSize(width: 800, height: 600)
    /// ```
    public struct PageSize {
        /// The orientation of a page.
        ///
        /// Page orientation affects how standard page sizes are interpreted.
        public enum PageOrientation {
            /// Landscape orientation (wider than tall).
            case landscape
            /// Portrait orientation (taller than wide).
            case portrait
        }

        /// The actual size of the page in points.
        ///
        /// This size is used directly when creating the PDF context.
        public let size: CGSize

        /// Creates an A4 page size.
        ///
        /// The A4 format is 210 × 297 millimeters or 8.27 × 11.7 inches,
        /// which translates to 595.2 × 841.8 points in PDF coordinates.
        ///
        /// - Parameter orientation: The orientation of the page. Defaults to `.portrait`.
        /// - Returns: A `PageSize` configured for A4 dimensions.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let portraitA4 = PageSize.a4()
        /// let landscapeA4 = PageSize.a4(orientation: .landscape)
        /// ```
        public static func a4(orientation: PageOrientation = .portrait) -> Self {
            switch orientation {
            case .landscape: .init(.a4Portrait.inverted)
            case .portrait: .init(.a4Portrait)
            }
        }

        /// Creates a US Letter page size.
        ///
        /// The US Letter format is 8.5 × 11 inches,
        /// which translates to 612 × 792 points in PDF coordinates.
        ///
        /// - Parameter orientation: The orientation of the page. Defaults to `.portrait`.
        /// - Returns: A `PageSize` configured for US Letter dimensions.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let portraitLetter = PageSize.usLetter()
        /// let landscapeLetter = PageSize.usLetter(orientation: .landscape)
        /// ```
        public static func usLetter(orientation: PageOrientation = .portrait) -> Self {
            switch orientation {
            case .landscape: .init(.usLetterPortrait.inverted)
            case .portrait: .init(.usLetterPortrait)
            }
        }

        /// Creates a custom page size.
        ///
        /// - Parameters:
        ///   - width: The width of the page in points.
        ///   - height: The height of the page in points.
        ///
        /// ## Example
        ///
        /// ```swift
        /// // Create a square page
        /// let square = PageSize(width: 500, height: 500)
        ///
        /// // Create a wide banner format
        /// let banner = PageSize(width: 1000, height: 200)
        /// ```
        ///
        /// - Note: PDF coordinates use points as the unit of measurement,
        ///   where 1 point = 1/72 inch.
        public init(width: Double, height: Double) {
            self.size = .init(width: CGFloat(width), height: CGFloat(height))
        }
    }

    #if canImport(UIKit)
    /// Renders SwiftUI views as a PDF document on iOS/iPadOS.
    ///
    /// This method creates a PDF document by rendering each page using the provided
    /// SwiftUI view builder. The rendering is performed on the main actor to ensure
    /// proper view updates.
    ///
    /// - Parameters:
    ///   - pageSize: The size configuration for each page in the document.
    ///   - pageCount: The total number of pages to render.
    ///   - format: The PDF renderer format configuration. Defaults to `.default()`.
    ///   - content: A view builder closure that creates the content for each page.
    ///     The closure receives the current page index (0-based) and should return
    ///     a SwiftUI view for that page.
    ///
    /// - Returns: The generated PDF document as `Data`.
    ///
    /// - Throws: Any error thrown by the content closure during rendering.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let pdfData = try await PDFRenderer.render(
    ///     pageSize: .a4(),
    ///     pageCount: 3,
    ///     format: {
    ///         let format = UIGraphicsPDFRendererFormat()
    ///         format.documentInfo = [
    ///             kCGPDFContextTitle as String: "My Document",
    ///             kCGPDFContextAuthor as String: "John Doe"
    ///         ]
    ///         return format
    ///     }()
    /// ) { pageIndex in
    ///     VStack {
    ///         Text("Page \(pageIndex + 1) of 3")
    ///             .font(.largeTitle)
    ///         Spacer()
    ///         Text("Document content here")
    ///         Spacer()
    ///     }
    ///     .padding()
    /// }
    /// ```
    ///
    /// - Important: This method must be called from the main actor context.
    ///
    /// - Note: The view content is automatically sized to fit the specified page size.
    ///   Content that exceeds the page bounds will be clipped.
    @MainActor public static func render(
        pageSize: PageSize,
        pageCount: Int,
        format: UIGraphicsPDFRendererFormat = .default(),
        @ViewBuilder content: @escaping (_ pageIndex: Int) throws -> some View
    ) throws -> Data {
        let size = pageSize.size
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: size),
            format: format
        )

        var renderingError: Error?
        let result = renderer.pdfData { context in
            do {
                for pageIndex in 0..<pageCount {
                    let pageContent = try content(pageIndex)
                    context.beginPage()
                    let swiftRenderer = ImageRenderer(
                        content: pageContent.frame(width: size.width, height: size.height)
                    )
                    swiftRenderer.proposedSize = .init(size)

                    // Flip for proper view orientation
                    context.cgContext.translateBy(x: 0, y: size.height)
                    context.cgContext.scaleBy(x: 1.0, y: -1.0)

                    swiftRenderer.render { _, swiftUIContext in
                        swiftUIContext(context.cgContext)
                    }
                }
            } catch {
                renderingError = error
            }
        }

        if let renderingError {
            throw renderingError
        }

        return result
    }
    #endif

    #if canImport(AppKit)
    /// Renders SwiftUI views as a PDF document on macOS.
    ///
    /// This method creates a PDF document by rendering each page using the provided
    /// SwiftUI view builder. The rendering is performed on the main actor to ensure
    /// proper view updates.
    ///
    /// - Parameters:
    ///   - pageSize: The size configuration for each page in the document.
    ///   - pageCount: The total number of pages to render.
    ///   - content: A view builder closure that creates the content for each page.
    ///     The closure receives the current page index (0-based) and should return
    ///     a SwiftUI view for that page.
    ///
    /// - Returns: The generated PDF document as `Data`.
    ///
    /// - Throws: An error if PDF creation fails or if the content closure throws.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let pdfData = try await PDFRenderer.render(
    ///     pageSize: .usLetter(orientation: .landscape),
    ///     pageCount: 5
    /// ) { pageIndex in
    ///     VStack(alignment: .leading) {
    ///         HStack {
    ///             Text("Report Title")
    ///                 .font(.title)
    ///             Spacer()
    ///             Text("Page \(pageIndex + 1)")
    ///         }
    ///         Divider()
    ///         Text("Content for page \(pageIndex + 1)")
    ///             .padding(.top)
    ///     }
    ///     .padding()
    /// }
    /// ```
    ///
    /// - Important: This method must be called from the main actor context.
    ///
    /// - Note: Unlike the iOS version, this method doesn't support a format parameter
    ///   as it uses Core Graphics directly for PDF creation.
    @MainActor public static func render(
        pageSize: PageSize,
        pageCount: Int,
        @ViewBuilder content: @escaping (_ pageIndex: Int) throws -> some View
    ) throws -> Data {
        let size = pageSize.size
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData) else {
            throw NSError(domain: "PDFRendererError", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF consumer"])
        }

        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "PDFRendererError", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        let previousContext = NSGraphicsContext.current

        var renderingError: Error?

        do {
            for pageIndex in 0..<pageCount {
                let pageContent = try content(pageIndex)

                context.beginPage(mediaBox: &mediaBox)
                NSGraphicsContext.current = graphicsContext

                let swiftRenderer = ImageRenderer(
                    content: pageContent.frame(width: size.width, height: size.height)
                )
                swiftRenderer.proposedSize = .init(size)

                swiftRenderer.render { _, swiftUIContext in
                    swiftUIContext(context)
                }

                context.endPage()
            }
        } catch {
            renderingError = error
        }

        context.closePDF()
        NSGraphicsContext.current = previousContext

        if let renderingError {
            throw renderingError
        }

        return pdfData as Data
    }
    #endif
}

private extension PDFRenderer.PageSize {
    init(_ size: CGSize) {
        self.size = size
    }
}

private extension CGSize {
    static var a4Portrait: CGSize {
        .init(width: 595.2, height: 841.8)
    }

    static var usLetterPortrait: CGSize {
        .init(width: 612, height: 792)
    }

    var inverted: CGSize {
        .init(width: height, height: width)
    }
}
