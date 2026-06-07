public struct BuildPair: Hashable, Codable, Sendable {
    public let platform: Platform
    public let swiftVersion: SwiftVersion

    public init(platform: Platform, swiftVersion: SwiftVersion) {
        self.platform = platform
        self.swiftVersion = swiftVersion
    }

    /// Whether SPI's `BuildPair.all` actually dispatches this pair.
    /// Android and WASM only run against Swift 6.1+.
    public var isSupportedBySPI: Bool {
        switch (platform, swiftVersion) {
        case (.android, .v6_0), (.wasm, .v6_0): false
        default: true
        }
    }

    /// Every platform × Swift version combination, including the two SPI skips.
    public static let all: [BuildPair] = Platform.allCases.flatMap { platform in
        SwiftVersion.allCases.map { BuildPair(platform: platform, swiftVersion: $0) }
    }

    /// SPI's actual matrix — `all` minus the two unsupported pairs.
    public static let supported: [BuildPair] = all.filter(\.isSupportedBySPI)

    /// All pairs across the given platforms × versions, including unsupported ones
    /// (callers can filter via `isSupportedBySPI` if they only want runnable cells).
    public static func filtered(
        platforms: [Platform],
        swiftVersions: [SwiftVersion]
    ) -> [BuildPair] {
        all.filter {
            platforms.contains($0.platform) && swiftVersions.contains($0.swiftVersion)
        }
    }
}
