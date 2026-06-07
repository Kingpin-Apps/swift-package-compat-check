import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the SPI build matrix against a package."
    )

    @Argument(help: "Path to the Swift package. Defaults to the current directory.")
    var path: String = "."

    @Option(
        name: [.short, .customLong("swift")],
        help: "Comma-separated Swift versions (default: 6.0,6.1,6.2,6.3)."
    )
    var swiftRaw: String?

    @Option(
        name: [.short, .customLong("platforms")],
        help: "Comma-separated platforms (default: all)."
    )
    var platformsRaw: String?

    @Option(
        name: [.customShort("S"), .customLong("scheme")],
        help: "Override the auto-detected scheme used by xcodebuild cells."
    )
    var scheme: String?

    @Option(name: .customLong("xcode-6.0"), help: "Xcode.app path for Swift 6.0 xcodebuild jobs.")
    var xcode60: String?

    @Option(name: .customLong("xcode-6.1"), help: "Xcode.app path for Swift 6.1 xcodebuild jobs.")
    var xcode61: String?

    @Option(name: .customLong("xcode-6.2"), help: "Xcode.app path for Swift 6.2 xcodebuild jobs.")
    var xcode62: String?

    @Option(name: .customLong("xcode-6.3"), help: "Xcode.app path for Swift 6.3 xcodebuild jobs.")
    var xcode63: String?

    @Option(name: .customLong("toolchain-6.0"), help: "Toolchain identifier for Swift 6.0 macos-spm jobs.")
    var toolchain60: String?

    @Option(name: .customLong("toolchain-6.1"), help: "Toolchain identifier for Swift 6.1 macos-spm jobs.")
    var toolchain61: String?

    @Option(name: .customLong("toolchain-6.2"), help: "Toolchain identifier for Swift 6.2 macos-spm jobs.")
    var toolchain62: String?

    @Option(name: .customLong("toolchain-6.3"), help: "Toolchain identifier for Swift 6.3 macos-spm jobs.")
    var toolchain63: String?

    @Option(name: .customLong("linux-image-6.0"), help: "Override the Linux builder image for Swift 6.0 (default: SPI's basic-6.0-latest).")
    var linuxImage60: String?

    @Option(name: .customLong("linux-image-6.1"), help: "Override the Linux builder image for Swift 6.1.")
    var linuxImage61: String?

    @Option(name: .customLong("linux-image-6.2"), help: "Override the Linux builder image for Swift 6.2.")
    var linuxImage62: String?

    @Option(name: .customLong("linux-image-6.3"), help: "Override the Linux builder image for Swift 6.3.")
    var linuxImage63: String?

    @Option(name: .customLong("android-image-6.1"), help: "Override the Android builder image for Swift 6.1.")
    var androidImage61: String?

    @Option(name: .customLong("android-image-6.2"), help: "Override the Android builder image for Swift 6.2.")
    var androidImage62: String?

    @Option(name: .customLong("android-image-6.3"), help: "Override the Android builder image for Swift 6.3.")
    var androidImage63: String?

    @Option(name: .customLong("wasm-image-6.1"), help: "Override the Wasm builder image for Swift 6.1.")
    var wasmImage61: String?

    @Option(name: .customLong("wasm-image-6.2"), help: "Override the Wasm builder image for Swift 6.2.")
    var wasmImage62: String?

    @Option(name: .customLong("wasm-image-6.3"), help: "Override the Wasm builder image for Swift 6.3.")
    var wasmImage63: String?

    @Option(name: .customLong("wasm-sdk-url-6.1"), help: "Override the Wasm SDK fallback URL for Swift 6.1.")
    var wasmSDKURL61: String?

    @Option(name: .customLong("wasm-sdk-url-6.2"), help: "Override the Wasm SDK fallback URL for Swift 6.2.")
    var wasmSDKURL62: String?

    @Option(name: .customLong("wasm-sdk-url-6.3"), help: "Override the Wasm SDK fallback URL for Swift 6.3.")
    var wasmSDKURL63: String?

    @Flag(name: .customLong("pull-always"), help: "Pass --pull=always to docker (default: --pull=missing).")
    var pullAlways: Bool = false

    @Option(
        name: .customLong("max-parallel"),
        help: "Max cells to run concurrently within each Swift version (default: activeProcessorCount / 2)."
    )
    var maxParallel: Int?

    @Flag(name: .customLong("no-live"), help: "Disable the live-updating matrix; stream one line per cell + final matrix instead.")
    var noLive: Bool = false

    @Flag(name: .long, help: "Print the matrix that would run without building anything.")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress non-essential output.")
    var quiet: Bool = false

    func run() async throws {
        let swiftVersions = try parseSwiftVersions(swiftRaw)
        let platforms = try parsePlatforms(platformsRaw)

        let detectedScheme: String
        if let scheme {
            detectedScheme = scheme
        } else {
            do {
                detectedScheme = try await SchemeDetector().detectScheme(packagePath: path)
            } catch {
                throw ValidationError("Scheme detection failed: \(error)")
            }
        }

        let packageURL = URL(fileURLWithPath: path).standardizedFileURL
        let packageBasename = packageURL.lastPathComponent.isEmpty
            ? "package"
            : packageURL.lastPathComponent
        let cache = CachePaths(
            root: CachePaths.defaultRoot(),
            packageBasename: packageBasename,
            runTimestamp: Self.runTimestamp()
        )
        let runOptions = RunOptions(
            xcodeForVersion: parseXcodeOverrides(),
            toolchainForVersion: parseToolchainOverrides(),
            linuxImageForVersion: parseLinuxImageOverrides(),
            androidImageForVersion: parseAndroidImageOverrides(),
            wasmImageForVersion: parseWasmImageOverrides(),
            wasmSDKURLForVersion: parseWasmSDKURLOverrides(),
            pullAlways: pullAlways,
            verbose: verbose
        )

        if !quiet {
            print("Package:   \(path)")
            print("Scheme:    \(detectedScheme)")
            print("Versions:  \(swiftVersions.map(\.rawValue).joined(separator: ", "))")
            print("Platforms: \(platforms.map(\.rawValue).joined(separator: ", "))")
            print("")
        }

        if dryRun {
            MatrixRenderer().render(platforms: platforms, swiftVersions: swiftVersions) { pair in
                pair.isSupportedBySPI ? .pending : .skipped
            }
            return
        }

        try cache.createDirectories()
        cache.trimOldLogs()
        let parallelism = max(1, maxParallel ?? (ProcessInfo.processInfo.activeProcessorCount / 2))
        let useLive = !quiet && !noLive && isStdoutTTY()
        if !quiet {
            print("Logs:      \(cache.runLogDir.path)")
            print("Parallel:  \(parallelism) cell\(parallelism == 1 ? "" : "s") per Swift version")
            print("")
        }

        let context = RunContext(
            packagePath: packageURL,
            scheme: detectedScheme,
            cache: cache,
            options: runOptions
        )
        let dispatcher = MatrixDispatcher()

        let outcomes: [BuildPair: CellOutcome]
        if useLive {
            outcomes = await runLive(
                platforms: platforms,
                swiftVersions: swiftVersions,
                context: context,
                dispatcher: dispatcher,
                parallelism: parallelism
            )
        } else {
            outcomes = await runStreaming(
                platforms: platforms,
                swiftVersions: swiftVersions,
                context: context,
                dispatcher: dispatcher,
                parallelism: parallelism
            )
        }

        let failed = outcomes.values.contains { $0.state == .fail }
        if failed {
            throw ExitCode.failure
        }
    }

    /// Live-updating matrix mode: paints the table once with all cells `?`, then
    /// redraws in place as cells flip to `⋯` (running) → `✓`/`✗`. Nothing else may
    /// write to stdout while this is in flight — Noora's renderer is stateful and
    /// any interleaved `print` would desynchronise the cursor math.
    private func runLive(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        context: RunContext,
        dispatcher: MatrixDispatcher,
        parallelism: Int
    ) async -> [BuildPair: CellOutcome] {
        let (stream, continuation) = AsyncStream<[BuildPair: CellState]>.makeStream()
        let initialState: @Sendable (BuildPair) -> CellState = { pair in
            pair.isSupportedBySPI ? .pending : .skipped
        }

        // Pre-populate the snapshot so unsupported cells render `—` on the very
        // first paint instead of `?`.
        var snapshot: [BuildPair: CellState] = [:]
        for sv in swiftVersions {
            for p in platforms {
                let pair = BuildPair(platform: p, swiftVersion: sv)
                snapshot[pair] = initialState(pair)
            }
        }

        async let renderTask: () = MatrixRenderer().renderLive(
            platforms: platforms,
            swiftVersions: swiftVersions,
            initialState: initialState,
            updates: stream
        )

        var outcomes: [BuildPair: CellOutcome] = [:]
        for swiftVersion in swiftVersions {
            await runCellsConcurrently(
                platforms: platforms,
                swiftVersion: swiftVersion,
                context: context,
                dispatcher: dispatcher,
                maxParallel: parallelism,
                onStart: { pair in
                    snapshot[pair] = .running
                    continuation.yield(snapshot)
                },
                onComplete: { pair, outcome in
                    outcomes[pair] = outcome
                    snapshot[pair] = outcome.state
                    continuation.yield(snapshot)
                }
            )
        }
        continuation.finish()
        await renderTask
        return outcomes
    }

    /// Streaming + final-matrix mode: prints one `✓ ios × Swift 6.3 (9.2s)` line per
    /// cell as it completes, then renders the canonical matrix once at the end. Used
    /// when stdout is piped, `--no-live` is set, or `-q` (which also suppresses the
    /// streaming lines).
    private func runStreaming(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        context: RunContext,
        dispatcher: MatrixDispatcher,
        parallelism: Int
    ) async -> [BuildPair: CellOutcome] {
        let isQuiet = quiet
        var outcomes: [BuildPair: CellOutcome] = [:]
        for swiftVersion in swiftVersions {
            await runCellsConcurrently(
                platforms: platforms,
                swiftVersion: swiftVersion,
                context: context,
                dispatcher: dispatcher,
                maxParallel: parallelism,
                onStart: nil,
                onComplete: { pair, outcome in
                    outcomes[pair] = outcome
                    if !isQuiet {
                        let symbol = outcome.state.symbol
                        let secs = String(format: "%.1fs", outcome.durationSeconds)
                        print("  \(symbol) \(pair.platform.rawValue) × Swift \(pair.swiftVersion.rawValue) (\(secs))")
                    }
                }
            )
        }
        if !isQuiet { print("") }
        MatrixRenderer().render(platforms: platforms, swiftVersions: swiftVersions) { pair in
            outcomes[pair]?.state ?? (pair.isSupportedBySPI ? .pending : .skipped)
        }
        return outcomes
    }

    /// Bounded per-Swift-version fan-out: at most `maxParallel` platform cells run
    /// concurrently. Reports cell lifecycle via the callbacks; emits no output itself.
    private func runCellsConcurrently(
        platforms: [Platform],
        swiftVersion: SwiftVersion,
        context: RunContext,
        dispatcher: MatrixDispatcher,
        maxParallel: Int,
        onStart: ((BuildPair) -> Void)?,
        onComplete: (BuildPair, CellOutcome) -> Void
    ) async {
        let pairs = platforms.map { BuildPair(platform: $0, swiftVersion: swiftVersion) }
        await withTaskGroup(of: (BuildPair, CellOutcome).self) { group in
            var iterator = pairs.makeIterator()
            var inFlight = 0

            func enqueueNext() -> Bool {
                guard let pair = iterator.next() else { return false }
                onStart?(pair)
                group.addTask {
                    let outcome = await dispatcher.run(pair: pair, context: context)
                    return (pair, outcome)
                }
                inFlight += 1
                return true
            }

            while inFlight < maxParallel, enqueueNext() {}

            while let result = await group.next() {
                inFlight -= 1
                onComplete(result.0, result.1)
                _ = enqueueNext()
            }
        }
    }

    private static func runTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        // Compact, filesystem-safe timestamp similar to bash `date +%Y%m%dT%H%M%S`.
        let date = Date()
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02dT%02d%02d%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0
        )
    }

    private func parseSwiftVersions(_ raw: String?) throws -> [SwiftVersion] {
        guard let raw, !raw.isEmpty else { return SwiftVersion.allCases }
        return try raw.split(separator: ",").map { token in
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard let version = SwiftVersion(rawValue: trimmed) else {
                throw ValidationError(
                    "Unknown Swift version: \(trimmed). Allowed: \(SwiftVersion.allCases.map(\.rawValue).joined(separator: ", "))."
                )
            }
            return version
        }
    }

    private func parsePlatforms(_ raw: String?) throws -> [Platform] {
        guard let raw, !raw.isEmpty else { return Platform.allCases }
        return try raw.split(separator: ",").map { token in
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard let platform = Platform(rawValue: trimmed) else {
                throw ValidationError(
                    "Unknown platform: \(trimmed). Allowed: \(Platform.allCases.map(\.rawValue).joined(separator: ", "))."
                )
            }
            return platform
        }
    }

    private func parseXcodeOverrides() -> [SwiftVersion: URL] {
        var map: [SwiftVersion: URL] = [:]
        let pairs: [(SwiftVersion, String?)] = [
            (.v6_0, xcode60), (.v6_1, xcode61), (.v6_2, xcode62), (.v6_3, xcode63),
        ]
        for (sv, raw) in pairs where raw != nil {
            map[sv] = URL(fileURLWithPath: raw!)
        }
        return map
    }

    private func parseToolchainOverrides() -> [SwiftVersion: String] {
        var map: [SwiftVersion: String] = [:]
        let pairs: [(SwiftVersion, String?)] = [
            (.v6_0, toolchain60), (.v6_1, toolchain61), (.v6_2, toolchain62), (.v6_3, toolchain63),
        ]
        for (sv, raw) in pairs where raw != nil {
            map[sv] = raw
        }
        return map
    }

    private func parseLinuxImageOverrides() -> [SwiftVersion: String] {
        var map: [SwiftVersion: String] = [:]
        let pairs: [(SwiftVersion, String?)] = [
            (.v6_0, linuxImage60), (.v6_1, linuxImage61), (.v6_2, linuxImage62), (.v6_3, linuxImage63),
        ]
        for (sv, raw) in pairs where raw != nil {
            map[sv] = raw
        }
        return map
    }

    private func parseAndroidImageOverrides() -> [SwiftVersion: String] {
        var map: [SwiftVersion: String] = [:]
        let pairs: [(SwiftVersion, String?)] = [
            (.v6_1, androidImage61), (.v6_2, androidImage62), (.v6_3, androidImage63),
        ]
        for (sv, raw) in pairs where raw != nil {
            map[sv] = raw
        }
        return map
    }

    private func parseWasmImageOverrides() -> [SwiftVersion: String] {
        var map: [SwiftVersion: String] = [:]
        let pairs: [(SwiftVersion, String?)] = [
            (.v6_1, wasmImage61), (.v6_2, wasmImage62), (.v6_3, wasmImage63),
        ]
        for (sv, raw) in pairs where raw != nil {
            map[sv] = raw
        }
        return map
    }

    private func parseWasmSDKURLOverrides() -> [SwiftVersion: String] {
        var map: [SwiftVersion: String] = [:]
        let pairs: [(SwiftVersion, String?)] = [
            (.v6_1, wasmSDKURL61), (.v6_2, wasmSDKURL62), (.v6_3, wasmSDKURL63),
        ]
        for (sv, raw) in pairs where raw != nil {
            map[sv] = raw
        }
        return map
    }
}
