// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LottieKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "LottieKit",
            targets: ["LottieKit"]
        )
    ],
    targets: [
        .target(
            name: "GZip",
            path: "Sources/GZip",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "RLottieBinding",
            path: "Sources/RLottieBinding",
            exclude: [
                "rlottie/src/vector/pixman/pixman-arm-neon-asm.S"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("rlottie/inc"),
                .headerSearchPath("rlottie/src/vector"),
                .headerSearchPath("rlottie/src/vector/pixman"),
                .headerSearchPath("rlottie/src/vector/freetype"),
                .unsafeFlags([
                    "-Dpixman_region_selfcheck(x)=1",
                    "-DLOTTIE_DISABLE_ARM_NEON=1",
                    "-DLOTTIE_THREAD_SAFE=1",
                    "-DLOTTIE_IMAGE_MODULE_DISABLED=1"
                ])
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("rlottie/inc"),
                .headerSearchPath("rlottie/src/vector"),
                .headerSearchPath("rlottie/src/vector/pixman"),
                .headerSearchPath("rlottie/src/vector/freetype"),
                .unsafeFlags([
                    "-Dpixman_region_selfcheck(x)=1",
                    "-DLOTTIE_DISABLE_ARM_NEON=1",
                    "-DLOTTIE_THREAD_SAFE=1",
                    "-DLOTTIE_IMAGE_MODULE_DISABLED=1"
                ])
            ]
        ),
        .target(
            name: "LottieKit",
            dependencies: [
                "GZip",
                "RLottieBinding"
            ],
            path: "Sources/LottieKit"
        )
    ],
    cxxLanguageStandard: .gnucxx17
)
