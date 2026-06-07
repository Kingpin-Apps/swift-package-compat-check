import Foundation

/// Per-version overrides parsed from the `--xcode-X.Y` and `--toolchain-X.Y` flags.
public struct RunOptions: Sendable {
    public var xcodeForVersion: [SwiftVersion: URL]
    public var toolchainForVersion: [SwiftVersion: String]
    public var verbose: Bool

    public init(
        xcodeForVersion: [SwiftVersion: URL] = [:],
        toolchainForVersion: [SwiftVersion: String] = [:],
        verbose: Bool = false
    ) {
        self.xcodeForVersion = xcodeForVersion
        self.toolchainForVersion = toolchainForVersion
        self.verbose = verbose
    }

    /// `DEVELOPER_DIR=<xcode>/Contents/Developer` for the given Swift version,
    /// or `nil` to inherit the active Xcode.
    public func developerDir(for version: SwiftVersion) -> String? {
        xcodeForVersion[version]
            .map { $0.appendingPathComponent("Contents/Developer").path }
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
