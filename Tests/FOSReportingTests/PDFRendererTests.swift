// PDFRendererTests.swift
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

import FOSFoundation
import FOSReporting
import SwiftUI
import Testing

@MainActor
@Suite("PDF Renderer Tests")
struct PDFRendererTests {
    @Test func simpleTest() throws {
        let pdfData = try PDFRenderer.render(
            pageSize: .usLetter(),
            pageCount: 3
        ) { pageIndex in
            Text("Page \(pageIndex + 1)")
        }

        #if os(macOS)
        let tmpUrl = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pdf")
        try pdfData.write(to: tmpUrl)
        NSWorkspace.shared.open(tmpUrl)
        #endif

        #expect(pdfData.isEmpty == false)
    }
}
