// PushPayloadTests.swift
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

#if APNs
@testable import FOSMVVMVapor
import Foundation
import Testing

/// Pins the internal payload to Apple's `aps` dictionary; never published.
@Suite("PushPayload — the aps dictionary sent to Apple")
struct PushPayloadTests {
    @Test func alertCarriesTitleBodyBadgeSoundAndLevel() throws {
        let aps = try encodedAPS(PushPayload(
            title: "New card",
            body: "A card was assigned to you",
            badge: 2,
            sound: .default,
            interruptionLevel: .timeSensitive
        ))

        let alert = try #require(aps["alert"] as? [String: Any])
        #expect(alert["title"] as? String == "New card")
        #expect(alert["body"] as? String == "A card was assigned to you")
        #expect(aps["badge"] as? Int == 2)
        #expect(aps["sound"] as? String == "default")
        #expect(aps["interruption-level"] as? String == "time-sensitive")
    }

    @Test func everyInterruptionLevelHasAppleSpelling() throws {
        let expected: [PushNotification.InterruptionLevel: String] = [
            .passive: "passive",
            .active: "active",
            .timeSensitive: "time-sensitive",
            .critical: "critical"
        ]
        for level in PushNotification.InterruptionLevel.allCases {
            let aps = try encodedAPS(PushPayload(title: "t", body: nil, badge: nil, sound: nil, interruptionLevel: level))
            #expect(aps["interruption-level"] as? String == expected[level])
        }
    }

    @Test func criticalSoundIsTheCriticalDictionary() throws {
        let aps = try encodedAPS(PushPayload(
            title: "t",
            body: nil,
            badge: nil,
            sound: .named("alarm.caf"),
            interruptionLevel: .critical
        ))

        let sound = try #require(aps["sound"] as? [String: Any])
        #expect(sound["critical"] as? Int == 1)
        #expect(sound["name"] as? String == "alarm.caf")
        #expect(sound["volume"] as? Double == 1.0)
    }

    @Test func badgeOnlyCarriesOnlyTheBadge() throws {
        let aps = try encodedAPS(PushPayload(title: nil, body: nil, badge: 5, sound: nil, interruptionLevel: .active))

        #expect(aps.count == 1)
        #expect(aps["badge"] as? Int == 5)
    }

    private func encodedAPS(_ payload: PushPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root.count == 1)
        return try #require(root["aps"] as? [String: Any])
    }
}
#endif
