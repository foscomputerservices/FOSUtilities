// APNSPushTransport.swift
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
import APNS
import APNSCore
import Crypto
import FOSMVVM
import Foundation
import Vapor

extension PushPayload: APNSMessage {}

/// Sends through APNSwift. An APNSwift client is bound to one environment, so this
/// holds one per ``PushEnvironment``.
struct APNSPushTransport: PushTransport {
    private let sandbox: APNSClient<JSONDecoder, JSONEncoder>
    private let production: APNSClient<JSONDecoder, JSONEncoder>

    init(configuration: PushConfiguration, eventLoopGroup: any EventLoopGroup) throws {
        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: configuration.privateKey)
        } catch {
            throw PushNotificationsError.invalidPrivateKey
        }
        let authentication = APNSClientConfiguration.AuthenticationMethod.jwt(
            privateKey: privateKey,
            keyIdentifier: configuration.keyId,
            teamIdentifier: configuration.teamId
        )

        func client(_ environment: APNSEnvironment) -> APNSClient<JSONDecoder, JSONEncoder> {
            APNSClient(
                configuration: .init(authenticationMethod: authentication, environment: environment),
                eventLoopGroupProvider: .shared(eventLoopGroup),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder()
            )
        }
        self.sandbox = client(.development)
        self.production = client(.production)
    }

    func deliver(
        _ payload: PushPayload,
        to deviceToken: String,
        topic: String,
        environment: PushEnvironment
    ) async throws -> PushDeliveryResult {
        let client = switch environment {
        case .sandbox: sandbox
        case .production: production
        }

        do {
            _ = try await client.send(APNSRequest(
                message: payload,
                deviceToken: deviceToken,
                pushType: .alert,
                expiration: nil,
                priority: .immediately,
                apnsID: nil,
                topic: topic,
                collapseID: nil
            ))
            return .delivered
        } catch let error as APNSError where Self.isRetired(error) {
            return .retired
        }
    }

    func shutdown() async throws {
        var firstError: (any Error)?
        for client in [sandbox, production] {
            do {
                try await client.shutdown()
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw firstError
        }
    }

    /// 410 Gone is Apple's answer for a token that is no longer active for the topic
    /// (`Unregistered`, `ExpiredToken`). `BadDeviceToken` (400) is deliberately not
    /// retirement: it is also Apple's answer for a token sent to the wrong environment,
    /// a configuration error that deleting rows would hide.
    static func isRetired(_ error: APNSError) -> Bool {
        error.responseStatus == 410
    }
}
#endif
