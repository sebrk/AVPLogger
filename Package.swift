// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpatialConsoleLogger",
    platforms: [
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "SpatialConsoleLogger",
            targets: ["SpatialConsoleLogger"]
        )
    ],
    targets: [
        .target(
            name: "SpatialConsoleLogger"
        )
    ]
)
