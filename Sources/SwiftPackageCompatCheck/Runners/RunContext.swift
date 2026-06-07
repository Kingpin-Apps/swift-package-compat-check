import Foundation

/// Per-version overrides and global toggles parsed from the CLI flags.
public struct RunOptions: Sendable {
    public var xcodeForVersion: [SwiftVersion: URL]
    public var toolchainForVersion: [SwiftVersion: String]
    public var linuxImageForVersion: [SwiftVersion: String]
    public var androidImageForVersion: [SwiftVersion: String]
    public var wasmImageForVersion: [SwiftVersion: String]
    public var wasmSDKURLForVersion: [SwiftVersion: String]
    public var pullAlways: Bool
    public var verbose: Bool

    public init(
        xcodeForVersion: [SwiftVersion: URL] = [:],
        toolchainForVersion: [SwiftVersion: String] = [:],
        linuxImageForVersion: [SwiftVersion: String] = [:],
        androidImageForVersion: [SwiftVersion: String] = [:],
        wasmImageForVersion: [SwiftVersion: String] = [:],
        wasmSDKURLForVersion: [SwiftVersion: String] = [:],
        pullAlways: Bool = false,
        verbose: Bool = false
    ) {
        self.xcodeForVersion = xcodeForVersion
        self.toolchainForVersion = toolchainForVersion
        self.linuxImageForVersion = linuxImageForVersion
        self.androidImageForVersion = androidImageForVersion
        self.wasmImageForVersion = wasmImageForVersion
        self.wasmSDKURLForVersion = wasmSDKURLForVersion
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

    /// Default wasm SDK artifact-bundle URL used by the bash resolver when the SPI
    /// image's bundled SDKs don't match. Returns `nil` for non-wasm platforms.
    /// Mirrors the bash script's `WASM_SDK_URL_FOR` defaults verbatim.
    func defaultWasmSDKURL(for swiftVersion: SwiftVersion) -> String? {
        guard self == .wasm else { return nil }
        switch swiftVersion {
        case .v6_0: return nil  // SPI doesn't build wasm on 6.0
        case .v6_1:
            return "https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.1-RELEASE/swift-wasm-6.1-RELEASE-wasm32-unknown-wasi.artifactbundle.zip"
        case .v6_2:
            return "https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.2-RELEASE/swift-wasm-6.2-RELEASE-wasm32-unknown-wasip1.artifactbundle.zip"
        case .v6_3:
            return "https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.3-RELEASE/swift-wasm-6.3-RELEASE-wasm32-unknown-wasip1.artifactbundle.zip"
        }
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
