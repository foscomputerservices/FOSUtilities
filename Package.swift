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
    products: {
        var result: [Product] = [
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
            ),
            .library(
                name: "FOSTestingUI",
                targets: ["FOSTestingUI"]
            )
        ]

        #if os(macOS) || os(iOS) || os(visionOS) || os(watchOS)
        result.append(.library(
            name: "FOSReporting",
            targets: ["FOSReporting"]
        ))
        #endif

        #if os(macOS) || os(Linux)
        result.append(.library(
            name: "FOSMVVMVapor",
            targets: ["FOSMVVMVapor"]
        ))
        result.append(.library(
            name: "FOSTestingVapor",
            targets: ["FOSTestingVapor"]
        ))
        #endif

        return result
    }(),
    dependencies: {
        var result: [Package.Dependency] = [
            // 🍎 frameworks
            .package(url: "https://github.com/apple/swift-docc-plugin", .upToNextMajor(from: "1.4.3")),
            .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "4.1.0")),
            .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "601.0.1"),

            // Third 🥳 frameworks
            .package(url: "https://github.com/foscomputerservices/Yams.git", branch: "add-wasi-support"), // Local fork for WASM fixes
            .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.19.0")
        ]

        #if os(macOS) || os(Linux)
        result.append(.package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.119.0")))
        result.append(.package(url: "https://github.com/vapor/fluent-kit.git", .upToNextMajor(from: "1.52.2")))
        result.append(.package(url: "https://github.com/vapor/leaf-kit.git", .upToNextMajor(from: "1.11.0")))
        #endif

        return result
    }(),
    targets: {
        var result: [Target] = [
            .target(
                name: "FOSFoundation",
                dependencies: [
                    // Crypto only for Linux (not needed for WASI/WASM)
                    .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
                    .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi]))
                ]
            ),
            .macro(
                name: "FOSMacros",
                dependencies: [
                    .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                    .product(name: "SwiftSyntax", package: "swift-syntax"),
                    .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                    .product(name: "SwiftParser", package: "swift-syntax"),
                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
                ]
            ),
            .target(
                name: "FOSMVVM",
                dependencies: [
                    .byName(name: "FOSFoundation"),
                    .byName(name: "FOSMacros"),
                    .product(name: "Yams", package: "Yams")
                ],
                resources: [
                    .copy("Resources/React")
                ]
            ),
            .target(
                name: "FOSTesting",
                dependencies: [
                    .byName(name: "FOSFoundation"),
                    .byName(name: "FOSMVVM")
                ]
            ),
            .target(
                name: "FOSTestingUI",
                dependencies: [
                    .byName(name: "FOSFoundation"),
                    .byName(name: "FOSMVVM")
                ]
            ),
            .testTarget(
                name: "FOSFoundationTests",
                dependencies: [
                    .byName(name: "FOSFoundation"),
                    .byName(name: "FOSTesting")
                ]
            ),
            .testTarget(
                name: "FOSMacrosTests",
                dependencies: [
                    .byName(name: "FOSFoundation"),
                    .byName(name: "FOSMacros"),
                    .byName(name: "FOSTesting"),
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
                    .byName(name: "FOSMacros")
                ],
                resources: [
                    .copy("TestYAML")
                ]
            )
        ]

        #if os(macOS) || os(iOS) || os(visionOS) || os(watchOS)
        result.append(.target(
            name: "FOSReporting",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM")
            ]
        ))
        result.append(.testTarget(
            name: "FOSReportingTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSTesting"),
                .byName(name: "FOSReporting")
            ]
        ))
        #endif

        #if os(macOS) || os(Linux)
        result.append(.target(
            name: "FOSMVVMVapor",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMacros"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "FluentKit", package: "fluent-kit", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "LeafKit", package: "leaf-kit", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Yams", package: "Yams")
            ]
        ))
        result.append(.target(
            name: "FOSTestingVapor",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMVVMVapor"),
                .byName(name: "FOSTesting"),
                .product(name: "Vapor", package: "Vapor"),
                .product(name: "VaporTesting", package: "vapor")
            ]
        ))
        result.append(.testTarget(
            name: "FOSMVVMVaporTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMVVMVapor"),
                .byName(name: "FOSTesting"),
                .byName(name: "FOSTestingVapor"),
                .product(name: "Vapor", package: "Vapor")
            ],
            resources: [
                .copy("TestYAML")
            ]
        ))
        #endif

        return result
    }(),
    swiftLanguageModes: [.v6]
)
