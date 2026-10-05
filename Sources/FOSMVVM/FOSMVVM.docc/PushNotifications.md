# Push Notifications

Register an app install for Apple push notifications and hand its device token to your server.

## Overview

``PushRegistration`` asks the user for permission, registers with Apple, and passes each device token to the app to send to its server. Create one in the app delegate and ask at every launch:

```swift
final class AppDelegate: NSObject, UIApplicationDelegate {
    let pushRegistration = PushRegistration(environment: pushEnvironment) { registration in
        let request = RegisterDeviceRequest(requestBody: .init(
            deviceToken: registration.deviceToken,
            topic: registration.topic,
            environment: registration.environment,
            locale: registration.locale
        ))
        try? await request.processRequest(mvvmEnv: BoardsApp.mvvmEnv)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { try? await pushRegistration.requestPermission() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pushRegistration.deviceTokenReceived(deviceToken)
    }
}
```

Adapt the delegate in your `App` with `@UIApplicationDelegateAdaptor` (`@NSApplicationDelegateAdaptor` on macOS, `@WKApplicationDelegateAdaptor` on watchOS).

### Ask at every launch

Apple hands over the token each time, and registering each time keeps the language your server stores current. Your `onDeviceToken` hook is also called whenever Apple replaces the token, so the server's register request should insert or update.

> Tip: tvOS shows only badges, so ask with `requestPermission(badgeOnly: true)` there.

### Choosing the environment

Development-signed builds get ``PushEnvironment/sandbox`` tokens; TestFlight and App Store builds get ``PushEnvironment/production``. The app states which it is when creating the registration, and the token carries it to the server.

### Sending notifications

The server half, storing the token and sending notifications, is FOSMVVMVapor behind the `APNs` package trait. Its `PushNotificationService` sends text localized into each install's language, badge-only and silent (content-available) notifications, and an app-defined payload.

### Reading your payload

The server sends your payload as a `Codable` type of your own, beside Apple's `aps` block. Decode it on the device with the same type:

```swift
struct CardAssignedPayload: Codable, Sendable {
    let boardName: String
}

func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    let userInfo = response.notification.request.content.userInfo
    guard
        let data = try? JSONSerialization.data(withJSONObject: userInfo),
        let payload = try? JSONDecoder().decode(CardAssignedPayload.self, from: data)
    else { return }
    // show payload.boardName
}
```

## Topics

- ``PushRegistration``
- ``PushEnvironment``
