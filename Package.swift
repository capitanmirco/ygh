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
        .library(name: "YGOFeatureCardDetail", targets: ["YGOFeatureCardDetail"]),
        .library(name: "YGOFeatureBanlist", targets: ["YGOFeatureBanlist"]),
        .library(name: "YGOFeatureDeckBuilder", targets: ["YGOFeatureDeckBuilder"]),
        .library(name: "YGOFeatureCollection", targets: ["YGOFeatureCollection"]),
        .library(name: "YGOFeatureAnalytics", targets: ["YGOFeatureAnalytics"]),
        .library(name: "YGOFeaturePricing", targets: ["YGOFeaturePricing"]),
        .library(name: "YGOValidation", targets: ["YGOValidation"]),
        .library(name: "YGODeckIO", targets: ["YGODeckIO"]),
        .library(name: "YGOAnalytics", targets: ["YGOAnalytics"]),
        .library(name: "YGOPricing", targets: ["YGOPricing"]),
        .library(name: "YGOBanlistHistory", targets: ["YGOBanlistHistory"]),
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

        // A timeline is a list of dated statuses, so this depends on YGOCore
        // alone and every question it answers is provable without a database.
        .target(
            name: "YGOBanlistHistory",
            dependencies: ["YGOCore"],
            path: "Packages/YGOBanlistHistory/Sources/YGOBanlistHistory",
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
            dependencies: ["YGOCore"],
            path: "Packages/YGODesignSystem/Sources/YGODesignSystem",
            swiftSettings: strictConcurrency),

        // Feature modules depend on YGOCore protocols only, never on a
        // concrete persistence or networking implementation.
        .target(
            name: "YGOFeatureBrowser",
            dependencies: ["YGOCore", "YGODesignSystem"],
            path: "Packages/Features/YGOFeatureBrowser/Sources/YGOFeatureBrowser",
            swiftSettings: strictConcurrency),

        // Valuation. Depends on YGOCore alone: the sums are checkable without
        // a database, and the prices arrive through a protocol.
        // The detail panel. Depends on YGOCore protocols alone, so the whole
        // of it is provable against stubs: no SQLite, no network, no view.
        // Reading a Forbidden & Limited List as a document rather than as a
        // filter over the catalog.
        .target(
            name: "YGOFeatureBanlist",
            dependencies: ["YGOCore", "YGODesignSystem", "YGOFeatureCardDetail"],
            path: "Packages/Features/YGOFeatureBanlist/Sources/YGOFeatureBanlist",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOFeatureCardDetail",
            dependencies: ["YGOCore", "YGODesignSystem", "YGOBanlistHistory"],
            path: "Packages/Features/YGOFeatureCardDetail/Sources/YGOFeatureCardDetail",
            swiftSettings: strictConcurrency),

        .target(
            name: "YGOPricing",
            dependencies: ["YGOCore"],
            path: "Packages/YGOPricing/Sources/YGOPricing",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOPricingTests",
            dependencies: ["YGOPricing", "YGOCore", "YGOFeaturePricing"],
            path: "Tests/YGOPricingTests",
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
            dependencies: ["YGOAnalytics", "YGOCore", "YGOFeatureAnalytics", "YGOFeaturePricing", "YGOPricing"],
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
            dependencies: ["YGOCore", "YGODesignSystem", "YGOValidation"],
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

        .target(
            name: "YGOFeaturePricing",
            dependencies: ["YGOCore", "YGOPricing", "YGODesignSystem"],
            path: "Packages/Features/YGOFeaturePricing/Sources/YGOFeaturePricing",
            swiftSettings: strictConcurrency),

        // The composition root: the only target allowed to know every
        // concrete implementation at once.
        .target(
            name: "YGOComposition",
            dependencies: ["YGOCore", "YGOPersistence", "YGONetworking", "YGOSync",
                           "YGOImageStore", "YGOValidation", "YGODeckIO", "YGOPricing",
                           "YGOBanlistHistory",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Packages/YGOComposition/Sources/YGOComposition",
            swiftSettings: strictConcurrency),

        .executableTarget(
            name: "YGODeckManagerApp",
            dependencies: ["YGOComposition", "YGOCore", "YGODesignSystem",
                           "YGOFeatureBrowser", "YGOFeatureCardDetail", "YGOFeatureBanlist",
                           "YGOFeatureDeckBuilder", "YGOFeatureCollection",
                           "YGOFeatureAnalytics", "YGOFeaturePricing", "YGOPricing"],
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
            dependencies: ["YGOSync", "YGOCore", "YGOPersistence", "YGONetworking", "YGOValidation", "YGODeckIO", "YGOFeatureDeckBuilder", "YGOFeatureCollection", "YGOFeatureBrowser", "YGOFeatureCardDetail", "YGOFeatureBanlist", "YGOPricing", "YGOBanlistHistory", "YGOComposition",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/YGOSyncTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOFeatureBanlistTests",
            dependencies: ["YGOFeatureBanlist", "YGOCore"],
            path: "Tests/YGOFeatureBanlistTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOFeatureCardDetailTests",
            dependencies: ["YGOFeatureCardDetail", "YGOCore", "YGOBanlistHistory",
                           "YGOFeatureBrowser", "YGOPersistence",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/YGOFeatureCardDetailTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGODesignSystemTests",
            dependencies: ["YGODesignSystem", "YGOCore"],
            path: "Tests/YGODesignSystemTests",
            swiftSettings: strictConcurrency),

        .testTarget(
            name: "YGOBanlistHistoryTests",
            dependencies: ["YGOBanlistHistory", "YGOCore"],
            path: "Tests/YGOBanlistHistoryTests",
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
