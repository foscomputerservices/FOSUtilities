// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FOSUtilities",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .macCatalyst(.v13),
        .tvOS(.v15),
        .watchOS(.v8)
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
        )
    ],
    dependencies: [
        // 🍎 frameworks
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.7.0")),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),

        // Third 🥳 frameworks
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.102.0")),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2")
    ],
    targets: [
        .target(
            name: "FOSFoundation",
            swiftSettings: [
            ]
        ),
        .target(
            name: "FOSMVVM",
            dependencies: [
                .byName(name: "FOSFoundation"),
                .product(name: "Vapor", package: "Vapor", condition: .when(platforms: [.macOS, .linux])),
                .product(name: "Yams", package: "Yams")
            ],
            swiftSettings: [
            ]
        )
    ]
)
