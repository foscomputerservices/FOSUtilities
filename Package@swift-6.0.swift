// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "FOSUtilities",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .macCatalyst(.v13),
        .tvOS(.v15),
        .watchOS(.v8),
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

        // Third 🥳 frameworks
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.102.0")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.0")
    ],
    targets: [
        .target(
            name: "FOSFoundation",
            swiftSettings: [
            ],
            plugins: plugins
        ),
        .target(
            name: "FOSMVVM",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Yams", package: "Yams")
            ],
            swiftSettings: [
            ],
            plugins: plugins
        ),
        .target(
            name: "FOSTesting",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "FOSFoundationTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSTesting"),
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "FOSMVVMTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSTesting"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Testing", package: "swift-testing")
            ],
            resources: [
                .copy("TestYAML")
            ]
        )
    ]
)

#if os(macOS)
let plugins: [PackageDescription.Target.PluginUsage]? = [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
]
#else
let plugins: [PackageDescription.Target.PluginUsage]? = nil
#endif
