// swift-tools-version: 6.2

import PackageDescription

let sharedUpcomingFeatures = [
    "ConciseMagicFile",
    "ForwardTrailingClosures",
    "GlobalConcurrency",
    "ImplicitOpenExistentials",
    "ImportObjcForwardDeclarations",
    "IsolatedDefaultValues",
    "NonfrozenEnumExhaustivity",
    "RegionBasedIsolation",
    "StrictConcurrency",
    "DisableOutwardActorInference",
    "GlobalActorIsolatedTypesUsability",
    "InferIsolatedConformances",
    "InferSendableFromCaptures",
    "NonisolatedNonsendingByDefault",
    "BareSlashRegexLiterals",
]

let sharedSwiftSettings: [SwiftSetting] =
    sharedUpcomingFeatures.map { .enableUpcomingFeature($0) } + [
        .unsafeFlags(
            [
                "-swift-version", "5",
            ]
        ),
        .unsafeFlags(
            [
                "-Xfrontend", "-strict-concurrency=complete",
            ]
        ),
        .unsafeFlags(
            [
                "-Xfrontend", "-warn-long-expression-type-checking=100",
                "-Xfrontend", "-warn-long-function-bodies=200",
            ],
            .when(configuration: .debug)
        ),
        .unsafeFlags(
            [
                "-Xfrontend", "-disable-dynamic-actor-isolation",
            ],
            .when(configuration: .release)
        ),
    ]

let contextMenuKitDependency: Target.Dependency = .product(name: "ContextMenuKit", package: "ContextMenuKit")

func airLibrary(_ name: String, type: Product.Library.LibraryType? = nil) -> Product {
    .library(name: name, type: type, targets: [name])
}

func airTarget(
    _ name: String,
    dependencies: [Target.Dependency] = [],
    swiftSettings: [SwiftSetting]? = nil,
) -> Target {
    .target(
        name: name,
        dependencies: dependencies,
        path: "SubModules/\(name)",
        swiftSettings: swiftSettings ?? sharedSwiftSettings
    )
}

func airTestTarget(
    _ name: String,
    dependencies: [Target.Dependency] = [],
    swiftSettings: [SwiftSetting]? = nil,
) -> Target {
    .testTarget(
        name: name,
        dependencies: dependencies,
        path: "Tests/\(name)",
        swiftSettings: swiftSettings ?? sharedSwiftSettings
    )
}

let package = Package(
    name: "AirModules",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        airLibrary("AirAsFramework"),
        airLibrary("GZip"),
        airLibrary("Ledger"),
        airLibrary("MyAgent"),
        airLibrary("RLottieBinding"),
        airLibrary("UIAssets"),
        airLibrary("UIActivityList"),
        airLibrary("UIAgent"),
        airLibrary("UIBrowser"),
        airLibrary("UIComponents"),
        airLibrary("UICreateWallet"),
        airLibrary("UIDapp"),
        airLibrary("UIEarn"),
        airLibrary("UIHome"),
        airLibrary("UIInAppBrowser"),
        airLibrary("UIPasscode"),
        airLibrary("UIQRScan"),
        airLibrary("UIReceive"),
        airLibrary("UISend"),
        airLibrary("UISettings"),
        airLibrary("UISwap"),
        airLibrary("UIToken"),
        airLibrary("UITransaction"),
        airLibrary("WReachability"),
        airLibrary("WalletContext"),
        airLibrary("WalletCore", type: .dynamic),
        airLibrary("YUVConversion"),
    ],
    dependencies: [
        .package(path: "../Packages/ContextMenuKit"),
        .package(
            url: "https://github.com/airbnb/lottie-spm.git",
            exact: "4.5.2"
        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            exact: "1.1.4"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            exact: "7.9.0"
        ),
        .package(
            url: "https://github.com/mytonwallet-org/DGCharts",
            revision: "86929ffb26280d49777e8b2c2311daa419747a49"
        ),
        .package(
            url: "https://github.com/mytonwallet-org/hw-transport-ios-ble",
            revision: "5046ed005e6ce721b533d332ed0744a52d6510b4"
        ),
        .package(
            url: "https://github.com/mytonwallet-org/swift-bigint",
            revision: "0485115b4ef6bd789ea320a1269d89fb09d1e8e6"
        ),
        .package(
            url: "https://github.com/onevcat/Kingfisher",
            exact: "8.6.2"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            exact: "1.10.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-navigation",
            exact: "2.6.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-perception",
            exact: "2.0.9"
        ),
        .package(
            url: "https://github.com/siteline/swiftui-introspect",
            exact: "1.3.0"
        ),
        .package(
            url: "https://github.com/tevelee/SwiftUI-Flow",
            exact: "3.1.1"
        ),
        .package(
            url: "https://github.com/yamoridon/ColorThiefSwift",
            exact: "0.5.0"
        ),
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            from: "0.9.19"
        ),
    ],
    targets: [
        .target(
            name: "GZip",
            path: "SubModules/GZip",
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "RLottieBinding",
            path: "SubModules/RLottieBinding",
            publicHeadersPath: "PublicHeaders",
            cSettings: [
                .unsafeFlags(
                    [
                        "-DLOTTIE_DISABLE_ARM_NEON=1",
                        "-DLOTTIE_IMAGE_MODULE_DISABLED=1",
                        "-D_FORTIFY_SOURCE=1",
                        "-Dpixman_region_selfcheck(x)=1",
                        "-w", // suppress all warnings
                    ]
                ),
                .headerSearchPath("."),
                .headerSearchPath("PublicHeaders"),
                .headerSearchPath("rlottie/inc"),
                .headerSearchPath("rlottie/src/vector"),
                .headerSearchPath("rlottie/src/vector/freetype"),
                .headerSearchPath("rlottie/src/vector/pixman"),
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "WReachability",
            path: "SubModules/WReachability",
            resources: [
                .process("Sources/PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "WalletContext",
            dependencies: [
                .product(name: "BigInt", package: "swift-bigint"),
                .product(name: "ColorThiefSwift", package: "colorthiefswift"),
                .product(name: "GRDB", package: "grdb.swift"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            path: "SubModules/WalletContext",
            exclude: [
                "Resources/Strings/Localizable.xcstrings",
            ],
            resources: [
                .process("Resources/Animations"),
                .process("Resources/Assets.xcassets"),
                .process("Resources/Fonts"),
                .process("Resources/JS"),
                .process("Resources/Sounds"),
                .process("Resources/Strings"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "WalletCore",
            dependencies: [
                "WalletContext",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "grdb.swift"),
                .product(name: "Kingfisher", package: "kingfisher"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
            ],
            path: "SubModules/WalletCore",
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "YUVConversion",
            path: "SubModules/YUVConversion",
            publicHeadersPath: "PublicHeaders",
            cSettings: [
                .headerSearchPath("PublicHeaders"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
        airTarget(
            "UIComponents",
            dependencies: [
                contextMenuKitDependency,
                "WalletContext",
                "WalletCore",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DGCharts", package: "dgcharts"),
                .product(name: "Kingfisher", package: "kingfisher"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Lottie", package: "lottie-spm"),
                "GZip",
                "RLottieBinding",
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                "YUVConversion",
            ]
        ),
        airTarget(
            "UIActivityList",
            dependencies: [
                "UIComponents",
                "WalletContext",
                "WalletCore",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Kingfisher", package: "kingfisher"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
            ],
            swiftSettings: sharedSwiftSettings + [
                .unsafeFlags(
                    [
                        "-Xfrontend", "-strict-concurrency=minimal", // data source snapshot is applied on background queue
                    ]
                ),
            ]
        ),
        airTarget(
            "UIQRScan",
            dependencies: [
                "UIComponents",
                "WalletContext",
                "WalletCore",
            ]
        ),
        airTarget(
            "Ledger",
            dependencies: [
                .product(name: "BleTransport", package: "hw-transport-ios-ble"),
                "WalletCore",
                "WalletContext",
                "UIComponents",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Perception", package: "swift-perception"),
            ]
        ),
        airTarget(
            "UIPasscode",
            dependencies: [
                "WalletContext",
                "WalletCore",
                "UIComponents",
                "Ledger",
                .product(name: "Perception", package: "swift-perception"),
            ]
        ),
        airTarget(
            "UIDapp",
            dependencies: [
                "UIComponents",
                "UIActivityList",
                "WalletCore",
                "WalletContext",
                .product(name: "Perception", package: "swift-perception"),
                "UIPasscode",
                .product(name: "Dependencies", package: "swift-dependencies"),
                "Ledger",
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "Kingfisher", package: "kingfisher"),
            ]
        ),
        airTarget(
            "UIInAppBrowser",
            dependencies: [
                "UIComponents",
                "WalletCore",
                "WalletContext",
                "UIDapp",
                .product(name: "Perception", package: "swift-perception"),
            ]
        ),
        airTarget(
            "UISend",
            dependencies: [
                contextMenuKitDependency,
                "UIComponents",
                "WalletCore",
                "WalletContext",
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                "UIPasscode",
                "Ledger",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),
        airTarget(
            "UISwap",
            dependencies: [
                contextMenuKitDependency,
                "WalletCore",
                "WalletContext",
                "UIPasscode",
                "UIComponents",
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        airTarget(
            "UIReceive",
            dependencies: [
                contextMenuKitDependency,
                "UIComponents",
                "WalletContext",
                "WalletCore",
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
            ]
        ),
        airTarget(
            "UITransaction",
            dependencies: [
                "UIComponents",
                "UIActivityList",
                "WalletContext",
                "WalletCore",
                .product(name: "Kingfisher", package: "kingfisher"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                "UIPasscode",
            ]
        ),
        airTarget(
            "UIAssets",
            dependencies: [
                contextMenuKitDependency,
                "WalletCore",
                "WalletContext",
                .product(name: "Perception", package: "swift-perception"),
                "UIComponents",
                "UIActivityList",
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "grdb.swift"),
                "UIPasscode",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Kingfisher", package: "kingfisher"),
            ]
        ),
        airTarget(
            "UIToken",
            dependencies: [
                "UIComponents",
                "UIActivityList",
                "WalletContext",
                "WalletCore",
                "WReachability",
                .product(name: "Perception", package: "swift-perception"),
            ]
        ),
        airTarget(
            "UIEarn",
            dependencies: [
                "WalletCore",
                "WalletContext",
                "UIComponents",
                .product(name: "Perception", package: "swift-perception"),
                "UIPasscode",
                "Ledger",
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),
        .target(
            name: "MyAgent",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "SubModules/MyAgent",
            resources: [
                .copy("I18n/Translations"),
            ],
            swiftSettings: sharedSwiftSettings
        ),
        airTarget(
            "UIAgent",
            dependencies: [
                "UIComponents",
                "WalletContext",
                "WalletCore",
                "MyAgent",
                .product(name: "GRDB", package: "grdb.swift"),
            ]
        ),
        airTarget(
            "UIBrowser",
            dependencies: [
                .product(name: "Kingfisher", package: "kingfisher"),
                "UIComponents",
                "WalletContext",
                "WalletCore",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Perception", package: "swift-perception"),
                "WReachability",
                "UIDapp",
            ]
        ),
        airTarget(
            "UISettings",
            dependencies: [
                "UIComponents",
                "WalletCore",
                "WalletContext",
                "UIPasscode",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "UIKitNavigation", package: "swift-navigation"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "Flow", package: "swiftui-flow"),
                .product(name: "Kingfisher", package: "kingfisher"),
                .product(name: "Lottie", package: "lottie-spm"),
            ]
        ),
        airTarget(
            "UIHome",
            dependencies: [
                contextMenuKitDependency,
                "UIComponents",
                "UIActivityList",
                "UIAgent",
                "WalletContext",
                "WalletCore",
                "WReachability",
                "UIEarn",
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                "UIAssets",
                "UISettings",
                "UIPasscode",
                "UIBrowser",
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "UIKitNavigation", package: "swift-navigation"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
            ]
        ),
        airTarget(
            "UICreateWallet",
            dependencies: [
                "UIComponents",
                "WalletCore",
                "WalletContext",
                "UIPasscode",
                "Ledger",
                "UISettings",
                .product(name: "Flow", package: "swiftui-flow"),
                .product(name: "Perception", package: "swift-perception"),
            ]
        ),
        airTarget(
            "AirAsFramework",
            dependencies: [
                "UIComponents",
                "UIActivityList",
                "WalletCore",
                "WalletContext",
                .product(name: "GRDB", package: "grdb.swift"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                "UISwap",
                "UITransaction",
                "UIQRScan",
                "UISend",
                "UIAssets",
                "UIAgent",
                "UISettings",
                "UIReceive",
                "UIEarn",
                "UIToken",
                "UIInAppBrowser",
                .product(name: "Perception", package: "swift-perception"),
                "UIHome",
                "UIBrowser",
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                "Ledger",
                "UIPasscode",
                "UIDapp",
                "UICreateWallet",
            ]
        ),
        airTestTarget(
            "WalletContextTests",
            dependencies: [
                "WalletContext",
            ]
        ),
        airTestTarget(
            "WalletCoreTests",
            dependencies: [
                "WalletCore",
                "WalletContext",
            ]
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .gnucxx20
)
