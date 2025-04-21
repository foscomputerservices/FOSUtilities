//
//  EmbeddedViewModelTests.swift
//  FOSUtilities
//
//  Created by David Hunt on 4/21/25.
//

import FOSFoundation
@testable import FOSMVVM
import FOSTesting
import Foundation
import Testing

@Suite("Embedded View Model Tests")
struct EmbeddedViewModelTests: LocalizableTestCase {
    @Test func testEmbeddedLocalization() throws {
        let vmEncoder = JSONEncoder.localizingEncoder(locale: en, localizationStore: locStore)
        let vm: MainViewModel = try .stub().toJSON(encoder: vmEncoder).fromJSON()

        #expect(try vm.innerViewModel.innerString.localizedString == "Inner String")
    }

    let locStore: LocalizationStore
    init() async throws {
        self.locStore = try await Self.loadLocalizationStore(
            bundle: Bundle.module,
            resourceDirectoryName: "TestYAML"
        )
    }
}

private struct MainViewModel: ViewModel {
    @LocalizedString var mainString
    let innerViewModel: InnerViewModel

    var vmId: FOSMVVM.ViewModelId
    
    static func stub() -> MainViewModel {
        .init(innerViewModel: .stub(), vmId: .init())
    }
}

private struct InnerViewModel: ViewModel {
    @LocalizedString var innerString

    var vmId: FOSMVVM.ViewModelId
    
    static func stub() -> InnerViewModel {
        .init(vmId: .init())
    }
}
