// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PalettePress",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .library(name: "PalettePressFoundation", targets: ["PalettePressFoundation"]),
        .library(name: "PalettePressViewModels", targets: ["PalettePressViewModels"]),
        .executable(name: "PalettePressServer", targets: ["PalettePressServer"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/foscomputerservices/FOSUtilities.git",
            from: "0.14.0"
        ),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.102.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0")
    ],
    targets: [
        // Shared foundation — the version handshake (SystemVersion) and other base
        // types the server needs WITHOUT importing the display contract. FOSFoundation
        // only. Both the client app and the server depend on this.
        .target(
            name: "PalettePressFoundation",
            dependencies: [
                .product(name: "FOSFoundation", package: "FOSUtilities")
            ]
        ),
        // Shared contract — client + server both compile this. FOS only; NO Vapor,
        // NO Fluent. Display-agnostic: the app source-includes this folder and any
        // future renderer (Leaf/Ignite/React) links this product.
        .target(
            name: "PalettePressViewModels",
            dependencies: [
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities")
            ]
        ),
        .executableTarget(
            name: "PalettePressServer",
            dependencies: [
                .byName(name: "PalettePressFoundation"),
                .byName(name: "PalettePressViewModels"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSMVVMVapor", package: "FOSUtilities")
            ],
            resources: [
                .copy("../Resources")
            ]
        ),
        .testTarget(
            name: "PalettePressViewModelsTests",
            dependencies: [
                .target(name: "PalettePressViewModels"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSTesting", package: "FOSUtilities")
            ],
            resources: [
                .copy("../../Sources/Resources")
            ]
        ),
        .testTarget(
            name: "PalettePressServerTests",
            dependencies: [
                .target(name: "PalettePressServer"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "FOSFoundation", package: "FOSUtilities"),
                .product(name: "FOSMVVM", package: "FOSUtilities"),
                .product(name: "FOSMVVMVapor", package: "FOSUtilities"),
                .product(name: "FOSTesting", package: "FOSUtilities"),
                .product(name: "FOSTestingVapor", package: "FOSUtilities")
            ],
            resources: [
                .copy("../../Sources/Resources")
            ]
        )
    ]
)
