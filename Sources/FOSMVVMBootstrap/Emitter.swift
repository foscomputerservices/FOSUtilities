// Emitter.swift
import Foundation

public enum EmitterError: Error, Equatable {
    case outputDirectoryNotEmpty(String)
    case templatesNotFound(String)
    case shapeNotImplemented(String)
}

extension EmitterError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .outputDirectoryNotEmpty(path):
            "output directory not empty: \(path)"
        case let .templatesNotFound(detail):
            "templates not found: \(detail)"
        case let .shapeNotImplemented(shape):
            "project shape not implemented by this version: \(shape)"
        }
    }
}

/// Composes a greenfield FOSMVVM project on disk:
/// `try Emitter.emit(config: config, into: outputDir)` renders
/// `Templates/shared` (doctrine common to every shape) plus
/// `Templates/<shape>` into `outputDir`, returning the emitted relative
/// paths. Never overwrites — an existing non-empty `outputDir` throws
/// `EmitterError.outputDirectoryNotEmpty`, because bootstrap is
/// greenfield-only by design.
public enum Emitter {
    /// Renders the shared + shape template trees into `outputDir` and
    /// returns the emitted relative paths (sorted, for stable assertions):
    /// `let paths = try Emitter.emit(config: config, into: url)`.
    ///
    /// Throws `EmitterError.shapeNotImplemented` when `config.shape` has no
    /// template tree in this version, `EmitterError.outputDirectoryNotEmpty`
    /// when `outputDir` already holds files, and `TemplateError.unrenderedToken`
    /// if any emitted file or path would still contain a `{{TOKEN}}`.
    @discardableResult
    public static func emit(config: BootstrapConfig, into outputDir: URL) throws -> [String] {
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

        let tokens = try TokenSet.derive(from: config)

        if fm.fileExists(atPath: outputDir.path),
           let existing = try? fm.contentsOfDirectory(atPath: outputDir.path),
           !existing.isEmpty
        {
            throw EmitterError.outputDirectoryNotEmpty(outputDir.path)
        }
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var emitted: [String] = []
        for sourceDir in ["shared", shapeDirName] {
            let root = templatesRoot.appendingPathComponent(sourceDir)
            emitted += try emitTree(from: root, into: outputDir, tokens: tokens)
        }
        return emitted.sorted()
    }

    private static func shapeDirName(_ shape: ProjectShape) -> String {
        switch shape {
        case .localOnly: "local-only"
        case .clientServer: "client-server"
        case .hybrid: "hybrid"
        case .sharedLibrary: "shared-library"
        }
    }

    private static func emitTree(from root: URL, into outputDir: URL, tokens: [String: String]) throws -> [String] {
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

        var emitted: [String] = []
        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(fileURL.standardizedFileURL.path.dropFirst(root.path.count + 1))
            if relative.hasSuffix(".gitkeep") {
                continue
            }

            // A `.symlink` template emits a symbolic link, not a file: the destination
            // is the path minus `.symlink`, and the template's (tokenized) contents are
            // the link's target. Keeps a shared, continually-modifiable file in sync
            // between two locations (e.g. TestConfiguration in the app + the UITests).
            if relative.hasSuffix(".symlink") {
                let rendered = try TemplateRenderer.render(relativePath: relative, tokens: tokens)
                let linkRelative = String(rendered.dropLast(".symlink".count))
                let target = try TemplateRenderer.render(
                    content: String(contentsOf: fileURL, encoding: .utf8),
                    tokens: tokens
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let destination = outputDir.appendingPathComponent(linkRelative)
                try fm.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fm.removeItem(at: destination)
                try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
                emitted.append(linkRelative)
                continue
            }

            let renderedRelative = try TemplateRenderer.render(relativePath: relative, tokens: tokens)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let renderedContent = try TemplateRenderer.render(content: content, tokens: tokens)

            let destination = outputDir.appendingPathComponent(renderedRelative)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try renderedContent.write(to: destination, atomically: true, encoding: .utf8)
            emitted.append(renderedRelative)
        }
        return emitted
    }
}
