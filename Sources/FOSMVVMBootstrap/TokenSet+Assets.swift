// TokenSet+Assets.swift
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

/// The app icon set follows the config's platforms: each platform the app
/// target hosts contributes the slots Xcode's own template gives it, so the
/// emitted `AppIcon.appiconset` is exactly what Xcode would have created for
/// the same destinations — and nothing a platform the app never builds for
/// would leave empty.
extension TokenSet {
    /// The `images` entries of `AppIcon.appiconset/Contents.json`, or an
    /// empty string when no platform contributes a slot.
    ///
    /// visionOS is absent on purpose: its icon is a layered
    /// `AppIcon.solidimagestack`, emitted as a platform tree by `Emitter`
    /// rather than as entries here. tvOS is absent because its icon is a
    /// `.brandassets` stack the scaffolder does not yet emit.
    static func appIconImagesJSON(config: BootstrapConfig) -> String {
        var entries: [String] = []

        if config.platforms[.iOS] != nil {
            entries.append(iOSSlot(appearance: nil))
            entries.append(iOSSlot(appearance: "dark"))
            entries.append(iOSSlot(appearance: "tinted"))
        }
        if config.platforms[.macOS] != nil {
            for size in [16, 32, 128, 256, 512] {
                entries.append(macSlot(size: size, scale: 1))
                entries.append(macSlot(size: size, scale: 2))
            }
        }
        if config.platforms[.watchOS] != nil {
            entries.append(
                """
                    {
                      "idiom" : "universal",
                      "platform" : "watchos",
                      "size" : "1024x1024"
                    }
                """
            )
        }

        return entries.joined(separator: ",\n")
    }

    private static func iOSSlot(appearance: String?) -> String {
        let appearances = appearance.map {
            """
                  "appearances" : [
                    {
                      "appearance" : "luminosity",
                      "value" : "\($0)"
                    }
                  ],

            """
        } ?? ""
        return """
            {
        \(appearances)      "idiom" : "universal",
              "platform" : "ios",
              "size" : "1024x1024"
            }
        """
    }

    private static func macSlot(size: Int, scale: Int) -> String {
        """
            {
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(size)x\(size)"
            }
        """
    }
}
