// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SwiftPackageCompatCheck",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "spcc", targets: ["SwiftPackageCompatCheckApp"]),
        .library(name: "SwiftPackageCompatCheck", targets: ["SwiftPackageCompatCheck"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.6.4"),
        .package(
            url: "https://github.com/apple/swift-configuration",
            from: "1.2.0",
            traits: [.defaults, "YAML"]
        ),
        .package(url: "https://github.com/mattt/swift-configuration-toml.git", from: "2.0.0"),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMinor(from: "0.14.2")),
        .package(url: "https://github.com/tuist/Noora", .upToNextMajor(from: "0.56.0")),
        .package(url: "https://github.com/Kolos65/Mockable", .upToNextMinor(from: "0.6.2")),
        .package(url: "https://github.com/mgacy/swift-version-file-plugin", from: "0.2.1"),
    ],
    targets: [
        .target(
            name: "SwiftPackageCompatCheck",
            dependencies: [
                "Noora",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Command", package: "Command"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "ConfigurationTOML", package: "swift-configuration-toml"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: [
                .define("MOCKING", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "SwiftPackageCompatCheckApp",
            dependencies: ["SwiftPackageCompatCheck"]
        ),
        .testTarget(
            name: "SwiftPackageCompatCheckTests",
            dependencies: [
                "SwiftPackageCompatCheck",
                .product(name: "Mockable", package: "Mockable"),
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
