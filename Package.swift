// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "FOSUtilities",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v13),
        .tvOS(.v12),
        .watchOS(.v6)
        // .windows()
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
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.1.0"))
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
