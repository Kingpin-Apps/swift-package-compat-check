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
    /// Per-cell wall-clock timeout in seconds. `nil` disables timeouts entirely.
    /// When set, container-backed runners attach a label / name and kill the
    /// container if the cell exceeds the budget.
    public var timeoutSeconds: Double?
    /// When `true`, every runner replaces `swift build` with `swift test` (or
    /// `xcodebuild build` with `xcodebuild test`). xcodebuild destinations for
    /// iOS/tvOS/watchOS/visionOS shift to the matching Simulator SDK since
    /// `xcodebuild test` rejects generic device destinations. Cross-SDK cells
    /// (android, wasm) pass `swift test --swift-sdk` through, which compiles
    /// the tests but typically can't execute them without a target device.
    public var runTests: Bool
    /// When `true` (and `runTests` is set), test runs go serial:
    /// `swift test --no-parallel` for SPM/Linux/cross-SDK cells and
    /// `xcodebuild test -parallel-testing-enabled NO` for xcodebuild cells.
    /// Distinct from `--max-parallel`, which bounds how many *cells* run at once;
    /// this bounds parallelism *within* a single cell's test process — the knob
    /// you want for suites that share global state (keyrings, ports, temp files).
    /// No effect in build mode.
    public var testNoParallel: Bool
    /// Host runtime backing Linux / Android / Wasm cells. Defaults to `.docker`
    /// (status-quo behaviour). `.container` routes through apple/container.
    public var containerRuntime: ContainerRuntime
    /// Opt-in Rosetta translation for the container runtime. `nil` and `false`
    /// behave identically (no `--rosetta`); `true` appends `--rosetta`. Only
    /// meaningful when `containerRuntime == .container`. Phase 1 always
    /// resolves to nil — Phase 2 measures whether enabling it is a net win.
    public var useRosetta: Bool?
    /// Extra system packages to `apt-get install` inside each Linux / Android /
    /// Wasm container before its build/test body runs. Populated only when
    /// `--test` is active (see `RunCommand`); empty otherwise. Host (Apple) cells
    /// are provisioned separately via `HostInstaller` since they share one
    /// machine rather than a fresh per-cell container.
    public var installContainer: [String]

    public init(
        xcodeForVersion: [SwiftVersion: URL] = [:],
        toolchainForVersion: [SwiftVersion: String] = [:],
        linuxImageForVersion: [SwiftVersion: String] = [:],
        androidImageForVersion: [SwiftVersion: String] = [:],
        wasmImageForVersion: [SwiftVersion: String] = [:],
        wasmSDKURLForVersion: [SwiftVersion: String] = [:],
        pullAlways: Bool = false,
        verbose: Bool = false,
        timeoutSeconds: Double? = nil,
        runTests: Bool = false,
        testNoParallel: Bool = false,
        containerRuntime: ContainerRuntime = .docker,
        useRosetta: Bool? = nil,
        installContainer: [String] = []
    ) {
        self.xcodeForVersion = xcodeForVersion
        self.toolchainForVersion = toolchainForVersion
        self.linuxImageForVersion = linuxImageForVersion
        self.androidImageForVersion = androidImageForVersion
        self.wasmImageForVersion = wasmImageForVersion
        self.wasmSDKURLForVersion = wasmSDKURLForVersion
        self.pullAlways = pullAlways
        self.verbose = verbose
        self.timeoutSeconds = timeoutSeconds
        self.runTests = runTests
        self.testNoParallel = testNoParallel
        self.containerRuntime = containerRuntime
        self.useRosetta = useRosetta
        self.installContainer = installContainer
    }

    /// `DEVELOPER_DIR=<xcode>/Contents/Developer` for the given Swift version,
    /// or `nil` to inherit the active Xcode.
    public func developerDir(for version: SwiftVersion) -> String? {
        xcodeForVersion[version]
            .map { $0.appendingPathComponent("Contents/Developer").path }
    }

    /// `--pull=always` (when toggled) or `--pull=missing` (default) for docker
    /// invocations. Matches the bash script's `PULL_POLICY` default of `missing`.
    public var pullPolicy: PullPolicy { pullAlways ? .always : .missing }
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
