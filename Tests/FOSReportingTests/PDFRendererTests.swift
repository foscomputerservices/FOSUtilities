// PDFRendererTests.swift
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
import FOSReporting
import PDFKit
import SwiftUI
import Testing

@MainActor
struct PDFRendererTests {
    @Test func multiPageContent() throws {
        let pageCount = 3
        let pdfData = try PDFRenderer.render(
            pageSize: .usLetter(),
            pageCount: pageCount
        ) { pageIndex in
            Text("Page \(pageIndex + 1)")
        }

        let document = try #require(
            PDFDocument(data: pdfData),
            "Rendered data is not a readable PDF document"
        )
        #expect(document.pageCount == pageCount)

        for pageIndex in 0..<pageCount {
            let page = try #require(document.page(at: pageIndex))
            let pageText = try #require(page.string)
            #expect(pageText.contains("Page \(pageIndex + 1)"))
        }
    }

    @Test(arguments: [
        (PDFRenderer.PageSize.usLetter(), CGSize(width: 612, height: 792)),
        (PDFRenderer.PageSize.usLetter(orientation: .landscape), CGSize(width: 792, height: 612)),
        (PDFRenderer.PageSize.a4(), CGSize(width: 595.2, height: 841.8)),
        (PDFRenderer.PageSize.a4(orientation: .landscape), CGSize(width: 841.8, height: 595.2)),
        (PDFRenderer.PageSize(width: 500, height: 250), CGSize(width: 500, height: 250))
    ])
    func pageDimensions(pageSize: PDFRenderer.PageSize, expectedSize: CGSize) throws {
        let pdfData = try PDFRenderer.render(
            pageSize: pageSize,
            pageCount: 1
        ) { _ in
            Text("Sized page")
        }

        let document = try #require(PDFDocument(data: pdfData))
        let page = try #require(document.page(at: 0))
        // The media box round-trips through PDF serialization, so allow
        // for floating-point drift
        let mediaBox = page.bounds(for: .mediaBox)
        #expect(abs(mediaBox.width - expectedSize.width) < 0.01)
        #expect(abs(mediaBox.height - expectedSize.height) < 0.01)
    }

    @Test func contentErrorsPropagate() {
        struct ContentError: Error {}

        #expect(throws: ContentError.self) {
            _ = try PDFRenderer.render(
                pageSize: .usLetter(),
                pageCount: 2
            ) { pageIndex in
                if pageIndex > 0 {
                    throw ContentError()
                }
                return Text("Page \(pageIndex + 1)")
            }
        }
    }
}
