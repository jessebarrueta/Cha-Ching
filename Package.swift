// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChaChing",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DoGoodCore",
            targets: ["DoGoodCore"]
        )
    ],
    targets: [
        .target(name: "DoGoodCore"),
        .testTarget(
            name: "DoGoodCoreTests",
            dependencies: ["DoGoodCore"]
        )
    ]
)
