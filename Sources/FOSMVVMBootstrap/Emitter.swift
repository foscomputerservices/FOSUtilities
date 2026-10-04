// Emitter.swift
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

// Emitter.swift
import Foundation

public enum EmitterError: Error, Equatable {
    /// Paths the project would write that already exist, relative to the
    /// output directory. Nothing was written.
    case pathsAlreadyExist([String])
    case templatesNotFound(String)
    case shapeNotImplemented(String)
    case fosUtilitiesCheckoutNotFound(String)
}

extension EmitterError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pathsAlreadyExist(let paths):
            "already exist, nothing written: \(paths.joined(separator: ", "))"
        case .templatesNotFound(let detail):
            "templates not found: \(detail)"
        case .shapeNotImplemented(let shape):
            "project shape not implemented by this version: \(shape)"
        case .fosUtilitiesCheckoutNotFound(let path):
            "no FOSUtilities Package.swift at: \(path)"
        }
    }
}

/// Composes a new FOSMVVM project on disk:
/// `try Emitter.emit(config: config, into: outputDir)` renders
/// `Templates/shared` (doctrine common to every shape) plus
/// `Templates/<shape>` — and, for app shapes, `Templates/platforms/<platform>`
/// for each platform the config declares — into `outputDir`, returning the
/// emitted relative paths. `outputDir` may be absent, empty, or an existing
/// repository with no project in it yet (`docs/`, `plans/`, a `.git`).
/// Never overwrites — when any path it would write already exists, it throws
/// `EmitterError.pathsAlreadyExist` naming them all, and writes nothing.
public enum Emitter {
    /// Renders the shared + shape template trees into `outputDir` and
    /// returns the emitted relative paths (sorted, for stable assertions):
    /// `let paths = try Emitter.emit(config: config, into: url)`.
    ///
    /// The generated project pins the FOSUtilities release this scaffolder
    /// ships with. Pass `fosUtilities: .localCheckout(url)` to resolve
    /// FOSUtilities from a checkout on this machine instead — see
    /// ``FOSUtilitiesSource``.
    ///
    /// Throws `EmitterError.shapeNotImplemented` when `config.shape` has no
    /// template tree in this version, `EmitterError.pathsAlreadyExist`
    /// when a path it would write already exists, `EmitterError.fosUtilitiesCheckoutNotFound`
    /// when a local checkout has no `Package.swift`, and `TemplateError.unrenderedToken`
    /// if any emitted file or path would still contain a `{{TOKEN}}`.
    @discardableResult
    public static func emit(
        config: BootstrapConfig,
        into outputDir: URL,
        fosUtilities: FOSUtilitiesSource = .release
    ) throws -> [String] {
        let fm = FileManager.default

        // Shape guard — the VERY FIRST thing emit() does, before TokenSet.derive
        // (which validates the config) and before any directory is created. A
        // shape whose template tree is absent must fail cleanly here rather than
        // part-emit the shared/ tree and blow up opaquely inside the generated
        // project's build. Running before validation is deliberate: don't
        // validate a config for a shape this version cannot emit.
        guard let templatesRoot = Bundle.module.url(forResource: "Templates", withExtension: nil) else {
            throw EmitterError.templatesNotFound("Templates not in Bundle.module")
        }
        let shapeDirName = shapeDirName(config.shape)
        var isDir: ObjCBool = false
        let shapeTemplateDir = templatesRoot.appendingPathComponent(shapeDirName)
        guard fm.fileExists(atPath: shapeTemplateDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw EmitterError.shapeNotImplemented(shapeDirName)
        }

        if case .localCheckout(let checkout) = fosUtilities,
           !fm.fileExists(atPath: checkout.appendingPathComponent("Package.swift").path) {
            throw EmitterError.fosUtilitiesCheckoutNotFound(checkout.path)
        }

        let tokens = try TokenSet.derive(from: config, fosUtilities: fosUtilities)

        var roots = ["shared", shapeDirName].map { templatesRoot.appendingPathComponent($0) }

        // Platform trees — `Templates/platforms/<platform>` — ride along when the
        // config declares that platform. Only app shapes receive them: what they
        // carry (the visionOS and tvOS icon stacks) lives in the app folder, which a
        // package has no counterpart for.
        if hasAppTarget(config.shape) {
            for platform in config.platforms.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                let root = templatesRoot
                    .appendingPathComponent("platforms")
                    .appendingPathComponent(platform.rawValue)
                guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
                roots.append(root)
            }
        }

        var planned: [PlannedFile] = []
        for root in roots {
            planned += try plan(tree: root, tokens: tokens)
        }

        var claimed = planned.map(\.relativePath)
        // xcodegen writes the project next to project.yml once emitting is done.
        if claimed.contains("project.yml") {
            claimed.append("\(config.projectName).xcodeproj")
        }
        let collisions = existingPaths(claimed, in: outputDir)
        guard collisions.isEmpty else {
            throw EmitterError.pathsAlreadyExist(collisions)
        }

        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for file in planned {
            try write(file, into: outputDir)
        }
        return planned.map(\.relativePath).sorted()
    }

    private static func hasAppTarget(_ shape: ProjectShape) -> Bool {
        switch shape {
        case .localOnly, .clientServer, .hybrid: true
        case .sharedLibrary: false
        }
    }

    private static func shapeDirName(_ shape: ProjectShape) -> String {
        switch shape {
        case .localOnly: "local-only"
        case .clientServer: "client-server"
        case .hybrid: "hybrid"
        case .sharedLibrary: "shared-library"
        }
    }

    private struct PlannedFile {
        let relativePath: String
        let content: String
        let isSymbolicLink: Bool
    }

    /// Renders a template tree in memory. Writing waits until every path is
    /// known to be free.
    private static func plan(tree root: URL, tokens: [String: String]) throws -> [PlannedFile] {
        let fm = FileManager.default
        // Standardize so /var vs /private/var symlink differences don't
        // corrupt the prefix arithmetic that derives the relative path.
        let root = root.standardizedFileURL
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [] // include hidden files (.github, .swiftformat)
        ) else {
            throw EmitterError.templatesNotFound(root.path)
        }

        var planned: [PlannedFile] = []
        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(fileURL.standardizedFileURL.path.dropFirst(root.path.count + 1))
            if relative.hasSuffix(".gitkeep") {
                continue
            }

            let renderedRelative = try TemplateRenderer.render(relativePath: relative, tokens: tokens)
            let renderedContent = try TemplateRenderer.render(
                content: String(contentsOf: fileURL, encoding: .utf8),
                tokens: tokens
            )

            // A `.symlink` template emits a symbolic link, not a file: the destination
            // is the path minus `.symlink`, and the template's (tokenized) contents are
            // the link's target. Keeps a shared, continually-modifiable file in sync
            // between two locations (e.g. TestConfiguration in the app + the UITests).
            if renderedRelative.hasSuffix(".symlink") {
                planned.append(PlannedFile(
                    relativePath: String(renderedRelative.dropLast(".symlink".count)),
                    content: renderedContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    isSymbolicLink: true
                ))
            } else {
                planned.append(PlannedFile(
                    relativePath: renderedRelative,
                    content: renderedContent,
                    isSymbolicLink: false
                ))
            }
        }
        return planned
    }

    /// The claimed paths something already occupies — the path itself (a file,
    /// a directory, or a link, even a dangling one), or a file where one of its
    /// parent directories would go.
    private static func existingPaths(_ claimed: [String], in outputDir: URL) -> [String] {
        let fm = FileManager.default
        func occupied(_ relative: String) -> Bool {
            (try? fm.attributesOfItem(atPath: outputDir.appendingPathComponent(relative).path)) != nil
        }
        func isDirectory(_ relative: String) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: outputDir.appendingPathComponent(relative).path, isDirectory: &isDir)
                && isDir.boolValue
        }

        var collisions: Set<String> = []
        for path in claimed {
            if occupied(path) {
                collisions.insert(path)
                continue
            }
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if occupied(parent), !isDirectory(parent) {
                    collisions.insert(parent)
                    break
                }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return collisions.sorted()
    }

    private static func write(_ file: PlannedFile, into outputDir: URL) throws {
        let fm = FileManager.default
        let destination = outputDir.appendingPathComponent(file.relativePath)
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if file.isSymbolicLink {
            // Only an earlier tree of this same run can be here; existing
            // paths were refused before anything was written.
            try? fm.removeItem(at: destination)
            try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: file.content)
        } else {
            try file.content.write(to: destination, atomically: true, encoding: .utf8)
        }
    }
}
