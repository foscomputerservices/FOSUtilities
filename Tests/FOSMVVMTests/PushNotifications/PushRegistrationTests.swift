// PushRegistrationTests.swift
//
// Copyright 2026 FOS Computer Services, LLC
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

#if canImport(UserNotifications)
@testable import FOSMVVM
import Foundation
import Testing

@MainActor
@Suite("PushRegistration — handing the device token to the app")
struct PushRegistrationTests {
    @Test func handsTheTokenToTheHookAsHexText() async throws {
        let received = Received()
        let pushRegistration = try PushRegistration(environment: .sandbox, bundle: .boards()) { registration in
            received.registrations.append(registration)
        }

        await pushRegistration.handOver(Data([0x00, 0x0F, 0xA5, 0xFF]))

        let first = try #require(received.registrations.first)
        #expect(received.registrations.count == 1)
        #expect(first.deviceToken == "000fa5ff")
    }

    @Test func handsOverEveryTokenItReceives() async throws {
        let received = Received()
        let pushRegistration = try PushRegistration(environment: .sandbox, bundle: .boards()) { registration in
            received.registrations.append(registration)
        }

        await pushRegistration.handOver(Data([0x01]))
        await pushRegistration.handOver(Data([0x01]))
        await pushRegistration.handOver(Data([0x02]))

        #expect(received.registrations.map(\.deviceToken) == ["01", "01", "02"])
    }

    @Test func topicIsTheAppsBundleIdentifier() throws {
        let pushRegistration = try PushRegistration(environment: .sandbox, bundle: .boards()) { _ in }

        #expect(pushRegistration.registration(from: Data([0x01])).topic == "com.example.boards")
    }

    @Test func environmentIsTheOneTheAppStated() throws {
        let pushRegistration = try PushRegistration(environment: .production, bundle: .boards()) { _ in }

        #expect(pushRegistration.registration(from: Data([0x01])).environment == .production)
    }

    @Test func localeIsTheAppsPreferredLocalization() throws {
        let bundle = try Bundle.boards()
        let pushRegistration = PushRegistration(environment: .sandbox, bundle: bundle) { _ in }
        let preferred = try #require(bundle.preferredLocalizations.first)

        #expect(preferred != "Base")
        #expect(pushRegistration.registration(from: Data([0x01])).locale == Locale(identifier: preferred))
    }

    @Test func localeSkipsBase() {
        #expect(PushRegistration.language(from: ["Base", "fr"]) == Locale(identifier: "fr"))
    }

    @Test func localeIsTheDevicesLanguageWhenTheAppHasOnlyBase() {
        let deviceLanguage = Locale(identifier: Locale.current.language.minimalIdentifier)

        #expect(PushRegistration.language(from: ["Base"]) == deviceLanguage)
        #expect(PushRegistration.language(from: []) == deviceLanguage)
    }
}

@Suite("PushRegistration.Registration — stubs")
struct PushRegistrationStubTests {
    @Test func stubOverridesOnlyWhatItIsGiven() {
        let registration = PushRegistration.Registration.stub(locale: Locale(identifier: "fr"))

        #expect(registration.locale == Locale(identifier: "fr"))
        #expect(registration.deviceToken == PushRegistration.Registration.stub().deviceToken)
        #expect(registration.topic == PushRegistration.Registration.stub().topic)
        #expect(registration.environment == PushRegistration.Registration.stub().environment)
    }

    @Test func stubIsAUsableRegistration() {
        let registration = PushRegistration.Registration.stub()

        #expect(!registration.deviceToken.isEmpty)
        let isHexadecimal = registration.deviceToken.allSatisfy(\.isHexDigit)
        #expect(isHexadecimal)
        #expect(!registration.topic.isEmpty)
    }
}

@MainActor
private final class Received {
    var registrations: [PushRegistration.Registration] = []
}

private extension Bundle {
    /// A bundle identified as `com.example.boards`, localized in English
    static func boards() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PushRegistrationTests-\(UUID().uuidString)")
            .appendingPathComponent("Boards.bundle")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("en.lproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Base.lproj"),
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.boards",
            "CFBundleDevelopmentRegion": "en"
        ]
        try PropertyListSerialization
            .data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
    }
}
#endif
