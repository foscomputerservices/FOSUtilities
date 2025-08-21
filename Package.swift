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
            .package(url: "https://github.com/swiftlang/swift-testing.git", revision: "43b6f88e2f2712e0f2a97e6acc75b55f22234299"),
            .package(url: "https://github.com/apple/swift-docc-plugin", .upToNextMajor(from: "1.4.3")),
            .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.10.0")),
            .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "601.0.1"),

            // Third 🥳 frameworks
            .package(url: "https://github.com/jpsim/Yams.git", .upToNextMajor(from: "5.1.3"))
        ]

        #if os(macOS) || os(Linux)
        result.append(.package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.115.1")))
        result.append(.package(url: "https://github.com/vapor/fluent-kit.git", .upToNextMajor(from: "1.52.2")))
        #endif

        return result
    }(),
    targets: {
        var result: [Target] = [
            .target(
                name: "FOSFoundation",
                dependencies: [
                    .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
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
                ]
            ),
            .target(
                name: "FOSTesting",
                dependencies: [
                    .byName(name: "FOSFoundation"),
                    .byName(name: "FOSMVVM"),
                    .product(name: "Testing", package: "swift-testing")
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
                    .byName(name: "FOSTesting"),
                    .product(name: "Testing", package: "swift-testing")
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
                    .byName(name: "FOSMacros"),
                    .product(name: "Testing", package: "swift-testing")
                ],
                resources: [
                    .copy("TestYAML")
                ]
            )
        ]

        #if os(macOS) || os(Linux)
        result.append(.target(
            name: "FOSMVVMVapor",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMacros"),
                .product(name: "Vapor", package: "Vapor"),
                .product(name: "FluentKit", package: "fluent-kit"),
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
                .product(name: "Testing", package: "swift-testing"),
                .product(name: "Vapor", package: "Vapor")
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
                .product(name: "Testing", package: "swift-testing"),
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
