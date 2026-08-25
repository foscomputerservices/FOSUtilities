// TokenSet+Watch.swift
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

/// Watch support is a SEPARATE app target: a multiplatform app target cannot
/// contain watchOS (xcodegen validation, mirroring Xcode's model — measured
/// 2026-08-22). The shared frameworks CAN carry the watchOS destination
/// (probe-built green the same day), so the watch target embeds the same
/// frameworks the main app does and compiles the same app sources.
extension TokenSet {
    /// The emitted watch app target, or empty when the config has no watchOS.
    static func watchTargetYAML(config: BootstrapConfig) -> String {
        guard config.platforms[.watchOS] != nil,
              let bundleIdRoot = config.bundleIdRoot
        else { return "" }
        let name = config.projectName

        let sources: String
        let dependencies: String
        switch config.shape {
        case .clientServer:
            sources = """
                  - path: Sources/\(name)
                    type: syncedFolder
                    excludes:
                      - "Info.plist"
                      - "\(name).entitlements"
                  - path: Sources/\(name)ViewModels
                    type: syncedFolder
            """
            dependencies = """
                  - target: SPMLibraries
                    embed: true
                    codeSign: true
                  - target: \(name)Foundation
                    embed: true
                    codeSign: true
                  - target: \(name)ClientViewModels
                    embed: true
                    codeSign: true
            """
        case .localOnly:
            sources = """
                  - path: Sources/\(name)
                    type: syncedFolder
                    excludes:
                      - "Info.plist"
                      - "\(name).entitlements"
            """
            dependencies = """
                  - target: SPMLibraries
                    embed: true
                    codeSign: true
                  - target: ViewModels
                    embed: true
                    codeSign: true
            """
        case .sharedLibrary, .hybrid:
            return ""
        }

        return """


          # Watch companion app: same sources, its own target (a multiplatform
          # app target cannot contain watchOS). The frameworks carry the
          # watchOS destination, so this target embeds the same ones.
          \(name)Watch:
            type: application
            platform: watchOS
            sources:
        \(sources)
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: \(bundleIdRoot).watch
                PRODUCT_NAME: \(name)Watch
                GENERATE_INFOPLIST_FILE: YES
                INFOPLIST_KEY_WKApplication: YES
                MARKETING_VERSION: "0.1"
                CURRENT_PROJECT_VERSION: 1
            dependencies:
        \(dependencies)
        """
    }

    /// A run scheme for the watch target, or empty.
    static func watchSchemeYAML(config: BootstrapConfig) -> String {
        guard config.platforms[.watchOS] != nil,
              config.shape == .clientServer || config.shape == .localOnly
        else { return "" }
        let name = config.projectName
        return """


          \(name)Watch:
            build:
              targets:
                \(name)Watch: all
            run:
              config: Debug
        """
    }
}
