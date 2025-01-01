// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "FOSUtilities",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
        // .windows(),
        // .linux(),
        // .wasm()
    ],
    products: [
        .library(
            name: "FOSFoundation",
            targets: ["FOSFoundation"]
        ),
        .library(
            name: "FOSMVVM",
            targets: ["FOSMVVM"]
        ),
        .library(
            name: "FOSTesting",
            targets: ["FOSTesting"]
        )
    ],
    dependencies: [
        // 🍎 frameworks
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.3.0")),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),

        // Third 🥳 frameworks
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.102.0")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2")
    ] + extraDeps,
    targets: [
        .target(
            name: "FOSFoundation",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .macro(
            name: "FOSMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .byName(name: "FOSFoundation")
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "FOSMVVM",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMacros"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Yams", package: "Yams")
            ],
            swiftSettings: swiftSettings,
            plugins: plugins
        ),
        .target(
            name: "FOSTesting",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .product(name: "Testing", package: "swift-testing")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FOSFoundationTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSTesting"),
                .product(name: "Testing", package: "swift-testing")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FOSMacrosTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSTesting"),
                .byName(name: "FOSMacros"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
                // 21-Dec-24 - Macros can only be tested with XCTest - https://forums.swift.org/t/swift-testing-support-for-macros/72720/6
            ]
        ),
        .testTarget(
            name: "FOSMVVMTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSTesting"),
                .byName(name: "FOSMacros"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Testing", package: "swift-testing")
            ],
            resources: [
                .copy("TestYAML")
            ],
            swiftSettings: swiftSettings
        )
    ]
)

let swiftSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-Xswiftc -swift-version",
        "-Xswiftc 6"
    ])
]

#if os(macOS)
let plugins: [PackageDescription.Target.PluginUsage]? = [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
]
let extraDeps: [Package.Dependency] = [
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.0")
]
#else
let plugins: [PackageDescription.Target.PluginUsage]? = [
]
let extraDeps: [Package.Dependency] = [
]
#endif
