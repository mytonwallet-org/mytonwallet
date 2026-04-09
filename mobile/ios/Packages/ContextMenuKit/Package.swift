// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ContextMenuKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ContextMenuKit",
            targets: ["ContextMenuKit"]
        )
    ],
    targets: [
        .target(
            name: "ContextMenuKit",
            path: "Sources/ContextMenuKit"
        )
    ]
)
