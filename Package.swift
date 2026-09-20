// swift-tools-version: 6.0
import PackageDescription

/// Every target compiles in Swift 6 language mode; strict concurrency is a
/// project hard rule, not a per-target opt-in.
let strictConcurrency: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "YGODeckManager",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "YGOCore", targets: ["YGOCore"]),
        .library(name: "YGOPersistence", targets: ["YGOPersistence"]),
        .library(name: "YGONetworking", targets: ["YGONetworking"]),
        .library(name: "YGOSync", targets: ["YGOSync"]),
        .library(name: "YGOImageStore", targets: ["YGOImageStore"]),
        .library(name: "YGODesignSystem", targets: ["YGODesignSystem"]),
        .library(name: "YGOFeatureBrowser", targets: ["YGOFeatureBrowser"]),
        .library(name: "YGOFeatureDeckBuilder", targets: ["YGOFeatureDeckBuilder"]),
        .library(name: "YGOFeatureCollection", targets: ["YGOFeatureCollection"]),
        .library(name: "YGOFeatureAnalytics", targets: ["YGOFeatureAnalytics"]),
        .library(name: "YGOValidation", targets: ["YGOValidation"]),
        .library(name: "YGODeckIO", targets: ["YGODeckIO"]),
        .library(name: "YGOAnalytics", targets: ["YGOAnalytics"]),
        .library(name: "YGOComposition", targets: ["YGOComposition"]),
        .executable(name: "YGODeckManager", targets: ["YGODeckManagerApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Domain types and repository protocols. Depends on nothing by design:
        // every other module may depend on it, it may depend on no one.
        .target(
            name: "YGOCore",
            path: "Packages/YGOCore/Sources/YGOCore",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOPersistence",
            dependencies: ["YGOCore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Packages/YGOPersistence/Sources/YGOPersistence",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGONetworking",
            dependencies: ["YGOCore"],
            path: "Packages/YGONetworking/Sources/YGONetworking",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOSync",
            dependencies: ["YGOCore", "YGONetworking"],
            path: "Packages/YGOSync/Sources/YGOSync",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOImageStore",
            dependencies: ["YGOCore", "YGONetworking"],
            path: "Packages/YGOImageStore/Sources/YGOImageStore",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGODesignSystem",
            path: "Packages/YGODesignSystem/Sources/YGODesignSystem",
            swiftSettings: strictConcurrency),

        // Feature modules depend on YGOCore protocols only, never on a
        // concrete persistence or networking implementation.
        .target(
            name: "YGOFeatureBrowser",
            dependencies: ["YGOCore", "YGODesignSystem"],
            path: "Packages/Features/YGOFeatureBrowser/Sources/YGOFeatureBrowser",
            swiftSettings: strictConcurrency),

        // The maths. Depends on YGOCore alone: no database, no network, no
        // view, so every probability is checkable against a figure worked out
        // by hand.
        .target(
            name: "YGOAnalytics",
            dependencies: ["YGOCore"],
            path: "Packages/YGOAnalytics/Sources/YGOAnalytics",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOAnalyticsTests",
            dependencies: ["YGOAnalytics", "YGOCore", "YGOFeatureAnalytics"],
            path: "Tests/YGOAnalyticsTests",
            swiftSettings: strictConcurrency),

        // The interchange formats. Depends on YGOCore alone, so a deck file
        // can be read and written with no database in sight.
        .target(
            name: "YGODeckIO",
            dependencies: ["YGOCore"],
            path: "Packages/YGODeckIO/Sources/YGODeckIO",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGODeckIOTests",
            dependencies: ["YGODeckIO", "YGOCore"],
            path: "Tests/YGODeckIOTests",
            swiftSettings: strictConcurrency),

        // Deck rules. Depends on YGOCore alone: no database, no network, no
        // view, so every rule is testable as arithmetic.
        .target(
            name: "YGOValidation",
            dependencies: ["YGOCore"],
            path: "Packages/YGOValidation/Sources/YGOValidation",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOValidationTests",
            dependencies: ["YGOValidation", "YGOCore"],
            path: "Tests/YGOValidationTests",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOFeatureDeckBuilder",
            dependencies: ["YGOCore", "YGODesignSystem"],
            path: "Packages/Features/YGOFeatureDeckBuilder/Sources/YGOFeatureDeckBuilder",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOFeatureCollection",
            dependencies: ["YGOCore", "YGODesignSystem"],
            path: "Packages/Features/YGOFeatureCollection/Sources/YGOFeatureCollection",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOFeatureAnalytics",
            dependencies: ["YGOCore", "YGOAnalytics", "YGODesignSystem"],
            path: "Packages/Features/YGOFeatureAnalytics/Sources/YGOFeatureAnalytics",
            swiftSettings: strictConcurrency),

        // The composition root: the only target allowed to know every
        // concrete implementation at once.
        .target(
            name: "YGOComposition",
            dependencies: ["YGOCore", "YGOPersistence", "YGONetworking", "YGOSync",
                           "YGOImageStore", "YGOValidation", "YGODeckIO",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Packages/YGOComposition/Sources/YGOComposition",
            swiftSettings: strictConcurrency),

        .executableTarget(
            name: "YGODeckManagerApp",
            dependencies: ["YGOComposition", "YGOCore", "YGODesignSystem",
                           "YGOFeatureBrowser", "YGOFeatureDeckBuilder", "YGOFeatureCollection",
                           "YGOFeatureAnalytics"],
            path: "App",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOCompositionTests",
            dependencies: ["YGOComposition", "YGOCore", "YGOFeatureBrowser", "YGONetworking",
                           "YGOPersistence", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/YGOCompositionTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOFeatureBrowserTests",
            dependencies: ["YGOFeatureBrowser", "YGOCore"],
            path: "Tests/YGOFeatureBrowserTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOImageStoreTests",
            dependencies: ["YGOImageStore", "YGOCore", "YGOPersistence", "YGONetworking",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/YGOImageStoreTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOSyncTests",
            dependencies: ["YGOSync", "YGOCore", "YGOPersistence", "YGONetworking", "YGOValidation", "YGODeckIO", "YGOFeatureDeckBuilder", "YGOFeatureCollection",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/YGOSyncTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGONetworkingTests",
            dependencies: ["YGONetworking", "YGOCore"],
            path: "Tests/YGONetworkingTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOPersistenceTests",
            dependencies: ["YGOPersistence", "YGOCore", "YGONetworking", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/YGOPersistenceTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOCoreTests",
            dependencies: ["YGOCore"],
            path: "Tests/YGOCoreTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "ToolchainHarnessTests",
            dependencies: ["YGOCore"],
            path: "Tests/ToolchainHarnessTests",
            swiftSettings: strictConcurrency),
    ]
)
