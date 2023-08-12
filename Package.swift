// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "FOSUtilities",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v13),
        .tvOS(.v12),
        .watchOS(.v6)
        // .linux()
    ],
    products: [
        .library(
            name: "FOSFoundation",
            targets: ["FOSFoundation"]
        ),
        .library(
            name: "FOSTesting",
            targets: ["FOSTesting"]
        )
    ],
    dependencies: [
        // 🍎 frameworks
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "2.4.0"))
    ],
    targets: [
        .target(
            name: "FOSFoundation"
        ),
        .target(
            name: "FOSTesting",
            dependencies: [
                .byName(name: "FOSFoundation")
            ]
        ),
        .testTarget(
            name: "FOSFoundationTests",
            dependencies: [
                .byName(name: "FOSFoundation")
            ]
        )
    ]
)
