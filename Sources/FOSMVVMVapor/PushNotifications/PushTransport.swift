// PushTransport.swift
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
import FOSMVVM
import Foundation

/// Delivers one finished payload to one device token
///
/// The production conformer talks to Apple (``APNSPushTransport``); tests install a
/// recording conformer through `PushNotificationService.configure(transport:onRetiredToken:)`, so no
/// test ever reaches Apple.
protocol PushTransport: Sendable {
    func deliver(
        _ payload: PushPayload,
        to deviceToken: String,
        topic: String,
        environment: PushEnvironment
    ) async throws -> PushDeliveryResult

    func shutdown() async throws
}

enum PushDeliveryResult: Sendable, Equatable {
    case delivered

    /// Apple will never deliver to this token again (HTTP 410)
    case retired
}

/// A notification after localization: what one destination receives
///
/// The encoded shape is the APNs `aps` dictionary, with the app's payload keys beside
/// it. Internal on purpose: the shape is Apple's wire format, pinned by PushPayloadTests,
/// never published.
struct PushPayload: Encodable, Sendable {
    let title: String?
    let body: String?
    let badge: Int?
    let sound: PushNotification.Sound?
    let interruptionLevel: PushNotification.InterruptionLevel
    let contentAvailable: Bool
    let appPayload: PushNotification.AppPayload?

    init(
        title: String?,
        body: String?,
        badge: Int?,
        sound: PushNotification.Sound?,
        interruptionLevel: PushNotification.InterruptionLevel,
        contentAvailable: Bool = false,
        appPayload: PushNotification.AppPayload? = nil
    ) {
        self.title = title
        self.body = body
        self.badge = badge
        self.sound = sound
        self.interruptionLevel = interruptionLevel
        self.contentAvailable = contentAvailable
        self.appPayload = appPayload
    }

    var isBadgeOnly: Bool {
        title == nil && body == nil && sound == nil
    }

    /// Apple's background push: only `content-available`, no alert, sound or badge.
    /// It must be sent with push type `background` and priority 5; anything the user
    /// sees, a badge included, is an `alert` push.
    var isBackground: Bool {
        contentAvailable && isBadgeOnly && badge == nil
    }

    func encode(to encoder: any Encoder) throws {
        // The app's keys first: JSONEncoder merges the keyed container requested below
        // into the same object. send(_:to:) has already proven the payload is an object
        // without an "aps" key.
        try appPayload?.encode(encoder)
        var container = encoder.container(keyedBy: RootKeys.self)
        try container.encode(APS(payload: self), forKey: .aps)
    }

    private enum RootKeys: String, CodingKey {
        case aps
    }

    private struct APS: Encodable {
        let payload: PushPayload

        enum CodingKeys: String, CodingKey {
            case alert
            case badge
            case sound
            case interruptionLevel = "interruption-level"
            case contentAvailable = "content-available"
        }

        struct Alert: Encodable {
            let title: String?
            let body: String?
        }

        struct CriticalSound: Encodable {
            let critical = 1
            let name: String
            let volume = 1.0
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if payload.title != nil || payload.body != nil {
                try container.encode(Alert(title: payload.title, body: payload.body), forKey: .alert)
            }
            try container.encodeIfPresent(payload.badge, forKey: .badge)
            if let sound = payload.sound {
                let fileName = switch sound {
                case .default: "default"
                case .named(let fileName): fileName
                }
                // A critical alert's sound must be the critical dictionary, or the
                // device plays it at the normal volume and honors the mute switch.
                if payload.interruptionLevel == .critical {
                    try container.encode(CriticalSound(name: fileName), forKey: .sound)
                } else {
                    try container.encode(fileName, forKey: .sound)
                }
            }
            // A badge-only notification has nothing to present, so no level.
            if !payload.isBadgeOnly {
                try container.encode(interruptionLevelValue, forKey: .interruptionLevel)
            }
            if payload.contentAvailable {
                try container.encode(1, forKey: .contentAvailable)
            }
        }

        private var interruptionLevelValue: String {
            switch payload.interruptionLevel {
            case .passive: "passive"
            case .active: "active"
            case .timeSensitive: "time-sensitive"
            case .critical: "critical"
            }
        }
    }
}
#endif
