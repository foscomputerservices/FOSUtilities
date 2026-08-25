// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PalettePress",
    platforms: [
        .iOS("17.0"),
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "PalettePressViewModels",
            targets: ["PalettePressViewModels"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/foscomputerservices/FOSUtilities.git", from: "0.14.0")
    ],
    targets: [
        .target(
            name: "PalettePressViewModels",
            dependencies: [
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ],
            resources: [
                .copy("Resources/Localizations")
            ]
        ),
        .testTarget(
            name: "PalettePressViewModelsTests",
            dependencies: [
                "PalettePressViewModels",
                .product(name: "FOSTesting", package: "FOSUtilities")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
