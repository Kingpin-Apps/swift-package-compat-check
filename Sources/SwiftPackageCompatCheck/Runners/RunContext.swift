import Foundation

/// Per-version overrides and global toggles parsed from the CLI flags.
public struct RunOptions: Sendable {
    public var xcodeForVersion: [SwiftVersion: URL]
    public var toolchainForVersion: [SwiftVersion: String]
    public var linuxImageForVersion: [SwiftVersion: String]
    public var pullAlways: Bool
    public var verbose: Bool

    public init(
        xcodeForVersion: [SwiftVersion: URL] = [:],
        toolchainForVersion: [SwiftVersion: String] = [:],
        linuxImageForVersion: [SwiftVersion: String] = [:],
        pullAlways: Bool = false,
        verbose: Bool = false
    ) {
        self.xcodeForVersion = xcodeForVersion
        self.toolchainForVersion = toolchainForVersion
        self.linuxImageForVersion = linuxImageForVersion
        self.pullAlways = pullAlways
        self.verbose = verbose
    }

    /// `DEVELOPER_DIR=<xcode>/Contents/Developer` for the given Swift version,
    /// or `nil` to inherit the active Xcode.
    public func developerDir(for version: SwiftVersion) -> String? {
        xcodeForVersion[version]
            .map { $0.appendingPathComponent("Contents/Developer").path }
    }

    /// `--pull=always` (when toggled) or `--pull=missing` (default) for docker
    /// invocations. Matches the bash script's `PULL_POLICY` default of `missing`.
    public var pullPolicy: String { pullAlways ? "always" : "missing" }
}

public extension Platform {
    /// SPI's public builder image tag for this platform + Swift version, in the
    /// `registry.gitlab.com/swiftpackageindex/spi-images:<plat>-<sv>-latest` shape.
    /// Returns `nil` for Apple platforms (no docker image needed).
    func defaultDockerImage(for swiftVersion: SwiftVersion) -> String? {
        let suffix: String
        switch self {
        case .linux: suffix = "basic"
        case .android: suffix = "android"
        case .wasm: suffix = "wasm"
        default: return nil
        }
        return "registry.gitlab.com/swiftpackageindex/spi-images:\(suffix)-\(swiftVersion.rawValue)-latest"
    }
}

public struct RunContext: Sendable {
    public let packagePath: URL
    public let scheme: String
    public let cache: CachePaths
    public let options: RunOptions

    public init(packagePath: URL, scheme: String, cache: CachePaths, options: RunOptions) {
        self.packagePath = packagePath
        self.scheme = scheme
        self.cache = cache
        self.options = options
    }
}

public struct CellOutcome: Sendable, Equatable {
    public let state: CellState
    public let logPath: URL?
    public let durationSeconds: Double
    public let errorMessage: String?

    public init(
        state: CellState,
        logPath: URL? = nil,
        durationSeconds: Double = 0,
        errorMessage: String? = nil
    ) {
        self.state = state
        self.logPath = logPath
        self.durationSeconds = durationSeconds
        self.errorMessage = errorMessage
    }
}
