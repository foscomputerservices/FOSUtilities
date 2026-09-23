// ProjectRule+Assets.swift
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

import Foundation

extension ProjectRule {
    /// R15 — the app icon name points at an icon set that exists.
    ///
    /// xcodegen writes `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` on every
    /// application target whether or not a catalog exists, so a project with
    /// no `AppIcon` set carries a setting that quietly names nothing. The
    /// build does not fail — `actool` never runs — which is why this is the
    /// table's second warning: the app runs; it cannot be submitted.
    static var appIconSet: ProjectRule {
        ProjectRule(summary: "ASSETCATALOG_COMPILER_APPICON_NAME names an icon set that exists") { project, _ in
            var findings: [Finding] = []

            for target in project.targets where target.kind == .application {
                let names = target.appIconNames
                guard !names.isEmpty else {
                    findings.append(
                        Finding(
                            severity: .warning,
                            target: target.name,
                            summary: "ASSETCATALOG_COMPILER_APPICON_NAME is not set, so the app builds with no icon.",
                            remedy: "Set ASSETCATALOG_COMPILER_APPICON_NAME to AppIcon and add Assets.xcassets/AppIcon.appiconset inside the app's source folder. A synchronized folder compiles the catalog with no further project change."
                        )
                    )
                    continue
                }

                for name in names where !project.appIconSetNames.contains(name) {
                    findings.append(
                        Finding(
                            severity: .warning,
                            target: target.name,
                            summary: "ASSETCATALOG_COMPILER_APPICON_NAME names \(name), but no icon set called \(name) exists under Sources/.",
                            remedy: "Add Assets.xcassets/\(name).appiconset (a .solidimagestack for visionOS) inside the app's source folder and drop the icon art in, or point the setting at the set you have. The build succeeds without it; App Store submission does not."
                        )
                    )
                }
            }

            return findings
        }
    }
}

extension AuditedTarget {
    /// Every app-icon name the target declares, across configurations and SDK
    /// conditions (`ASSETCATALOG_COMPILER_APPICON_NAME[sdk=xros*]` is its own
    /// key), in a stable order with duplicates dropped.
    var appIconNames: [String] {
        var names: [String] = []
        for configuration in configurations {
            let declared = settings[configuration] ?? [:]
            for key in declared.keys.sorted() where key.hasPrefix("ASSETCATALOG_COMPILER_APPICON_NAME") {
                guard let value = declared[key], !value.isEmpty, !names.contains(value) else { continue }
                names.append(value)
            }
        }
        return names
    }
}
