// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GraphKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "GraphKit",
            targets: ["GraphKit"]
        )
    ],
    targets: [
        .target(
            name: "GraphKit",
            path: "Sources/GraphKit"
        ),
        .testTarget(name: "GraphKitTests", dependencies: ["GraphKit"])
    ],
    swiftLanguageModes: [
        .v5
    ]
)
