// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SwiftSVG",
    platforms: [.macOS(.v10_14), .iOS(.v8), .tvOS(.v9)],
    products: [
        .library(
            name: "SwiftSVG",
            targets: ["SwiftSVG"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftSVG",
            dependencies: [],
            path: "SwiftSVG",
            resources: [.process("SVG/Helpers/cssColorNames.json")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
