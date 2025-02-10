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
            name: "FOSMVVMVapor",
            targets: ["FOSMVVMVapor"]
        ),
        .library(
            name: "FOSTesting",
            targets: ["FOSTesting"]
        ),
        .library(
            name: "FOSTestingVapor",
            targets: ["FOSTestingVapor"]
        )
    ],
    dependencies: [
        // 🍎 frameworks
        .package(url: "https://github.com/swiftlang/swift-testing.git", revision: "18c42c19cac3fafd61cab1156d4088664b7424ae"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.10.0")),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),

        // Third 🥳 frameworks
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.111.0")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3")
    ],
    targets: [
        .target(
            name: "FOSFoundation",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ]
        ),
        .macro(
            name: "FOSMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .byName(name: "FOSFoundation")
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
            name: "FOSMVVMVapor",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMacros"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
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
            name: "FOSTestingVapor",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMVVMVapor", condition: .when(platforms: [.macOS, .linux])),
                .byName(name: "FOSTesting"),
                .product(name: "Testing", package: "swift-testing"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux]))
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
        ),
        .testTarget(
            name: "FOSMVVMVaporTests",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .byName(name: "FOSMVVM"),
                .byName(name: "FOSMVVMVapor"),
                .byName(name: "FOSMacros"),
                .byName(name: "FOSTesting"),
                .byName(name: "FOSTestingVapor"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Testing", package: "swift-testing")
            ],
            resources: [
                .copy("TestYAML")
            ]
        )
    ]
)
