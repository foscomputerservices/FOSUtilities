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
        let registration = try PushRegistration(environment: .sandbox, bundle: .boards()) { token in
            received.tokens.append(token)
        }

        await registration.handOver(Data([0x00, 0x0F, 0xA5, 0xFF]))

        let token = try #require(received.tokens.first)
        #expect(received.tokens.count == 1)
        #expect(token.deviceToken == "000fa5ff")
    }

    @Test func handsOverEveryTokenItReceives() async throws {
        let received = Received()
        let registration = try PushRegistration(environment: .sandbox, bundle: .boards()) { token in
            received.tokens.append(token)
        }

        await registration.handOver(Data([0x01]))
        await registration.handOver(Data([0x01]))
        await registration.handOver(Data([0x02]))

        #expect(received.tokens.map(\.deviceToken) == ["01", "01", "02"])
    }

    @Test func topicIsTheAppsBundleIdentifier() throws {
        let registration = try PushRegistration(environment: .sandbox, bundle: .boards()) { _ in }

        #expect(registration.deviceToken(from: Data([0x01])).topic == "com.example.boards")
    }

    @Test func environmentIsTheOneTheAppStated() throws {
        let registration = try PushRegistration(environment: .production, bundle: .boards()) { _ in }

        #expect(registration.deviceToken(from: Data([0x01])).environment == .production)
    }

    @Test func localeIsTheAppsPreferredLocalization() throws {
        let bundle = try Bundle.boards()
        let registration = PushRegistration(environment: .sandbox, bundle: bundle) { _ in }
        let preferred = try #require(bundle.preferredLocalizations.first)

        #expect(preferred != "Base")
        #expect(registration.deviceToken(from: Data([0x01])).locale == Locale(identifier: preferred))
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

@Suite("PushRegistration.DeviceToken — stubs")
struct PushRegistrationDeviceTokenStubTests {
    @Test func stubOverridesOnlyWhatItIsGiven() {
        let token = PushRegistration.DeviceToken.stub(locale: Locale(identifier: "fr"))

        #expect(token.locale == Locale(identifier: "fr"))
        #expect(token.deviceToken == PushRegistration.DeviceToken.stub().deviceToken)
        #expect(token.topic == PushRegistration.DeviceToken.stub().topic)
        #expect(token.environment == PushRegistration.DeviceToken.stub().environment)
    }

    @Test func stubIsAUsableToken() {
        let token = PushRegistration.DeviceToken.stub()

        #expect(!token.deviceToken.isEmpty)
        let isHexadecimal = token.deviceToken.allSatisfy(\.isHexDigit)
        #expect(isHexadecimal)
        #expect(!token.topic.isEmpty)
    }
}

@MainActor
private final class Received {
    var tokens: [PushRegistration.DeviceToken] = []
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
