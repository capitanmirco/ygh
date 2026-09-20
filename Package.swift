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

        // The composition root: the only target allowed to know every
        // concrete implementation at once.
        .target(
            name: "YGOComposition",
            dependencies: ["YGOCore", "YGOPersistence", "YGONetworking", "YGOSync",
                           "YGOImageStore", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Packages/YGOComposition/Sources/YGOComposition",
            swiftSettings: strictConcurrency),

        .executableTarget(
            name: "YGODeckManagerApp",
            dependencies: ["YGOComposition", "YGOCore", "YGOFeatureBrowser"],
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
            dependencies: ["YGOSync", "YGOCore", "YGOPersistence", "YGONetworking",
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
