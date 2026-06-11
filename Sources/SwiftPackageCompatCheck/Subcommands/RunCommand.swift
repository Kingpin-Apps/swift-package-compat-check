import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the SPI build matrix against a package."
    )

    @Argument(help: "Path to the Swift package. Defaults to the current directory. Equivalent to --path.")
    var pathArgument: String = "."

    @Option(
        name: [.customShort("P"), .customLong("path")],
        help: "Path to the Swift package (alternative to the positional argument). Wins if both are given."
    )
    var pathOption: String?

    @Option(
        name: [.customShort("c"), .customLong("config")],
        help: "Path to a TOML/JSON config file with default flag values. Falls back to $SPCC_CONFIG if unset; otherwise built-in defaults are used."
    )
    var configPath: String?

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
        name: .customLong("container-runtime"),
        help: "Container runtime backing Linux/Android/Wasm cells: docker (default) or container (apple/container)."
    )
    var containerRuntimeRaw: String?

    @Option(
        name: .customLong("max-parallel"),
        help: "Max cells to run concurrently within each Swift version (default: activeProcessorCount / 2)."
    )
    var maxParallel: Int?

    @Option(
        name: .customLong("timeout"),
        help: "Per-cell wall-clock timeout in seconds. Docker containers are killed by label on timeout. Default: no timeout."
    )
    var timeoutSeconds: Double?

    @Flag(
        name: [.customShort("t"), .customLong("test")],
        help: "Run `swift test` (or `xcodebuild test`) instead of `swift build` for each cell."
    )
    var runTests: Bool = false

    @Flag(
        name: .customLong("test-no-parallel"),
        help: "When running tests (--test), run them serially: `swift test --no-parallel` / `xcodebuild test -parallel-testing-enabled NO`. For suites that share global state. Distinct from --max-parallel (which bounds cell concurrency). No effect without --test."
    )
    var testNoParallel: Bool = false

    @Option(
        name: .customLong("install-host"),
        help: "Comma-separated system packages to `brew install` on the host Mac before Apple (macos/ios/…) test cells. Persists on your machine. Only applied with --test."
    )
    var installHostRaw: String?

    @Option(
        name: .customLong("install-container"),
        help: "Comma-separated system packages to `apt-get install` inside each Linux/Android/Wasm container before its test cell. Ephemeral. Only applied with --test."
    )
    var installContainerRaw: String?

    @Flag(name: .customLong("no-live"), help: "Disable the live-updating matrix; stream one line per cell + final matrix instead.")
    var noLive: Bool = false

    @Flag(name: .long, help: "Print the matrix that would run without building anything.")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress non-essential output.")
    var quiet: Bool = false

    func run() async throws {
        let config: SPCCConfig?
        do {
            config = try await SPCCConfig.load(explicitPath: configPath)
        } catch {
            throw ValidationError("Could not load config: \(error)")
        }

        let path = pathOption ?? pathArgument
        let swiftVersions = try parseSwiftVersions(swiftRaw, config: config)
        let platforms = try parsePlatforms(platformsRaw, config: config)

        let effectiveRunTests = runTests || (config?.test ?? false)
        // Install lists only take effect under --test (see the AskUserQuestion
        // decision); parse-and-validate always so a bad package name is caught
        // even when ignored, then zero them out when not testing.
        let installHostPackages = try parseInstallList(installHostRaw, configValue: config?.installHost)
        let installContainerPackages = try parseInstallList(installContainerRaw, configValue: config?.installContainer)
        let wantTestNoParallel = testNoParallel || (config?.testNoParallel ?? false)
        let testOnlyOptionRequested = !installHostPackages.isEmpty
            || !installContainerPackages.isEmpty
            || wantTestNoParallel
        if !effectiveRunTests, !quiet, testOnlyOptionRequested {
            print("Note: --install-host/--install-container/--test-no-parallel only apply with --test; ignoring for this build-only run.\n")
        }
        let activeHostPackages = effectiveRunTests ? installHostPackages : []
        let activeContainerPackages = effectiveRunTests ? installContainerPackages : []
        let activeTestNoParallel = effectiveRunTests && wantTestNoParallel

        let detectedScheme: String
        if let scheme {
            detectedScheme = scheme
        } else if let configScheme = config?.scheme, !configScheme.isEmpty {
            detectedScheme = configScheme
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
            xcodeForVersion: mergeXcodeOverrides(config: config),
            toolchainForVersion: mergePerVersion(
                cli: parseToolchainOverrides(), configValue: config?.toolchain
            ),
            linuxImageForVersion: mergePerVersion(
                cli: parseLinuxImageOverrides(), configValue: config?.linuxImage
            ),
            androidImageForVersion: mergePerVersion(
                cli: parseAndroidImageOverrides(), configValue: config?.androidImage
            ),
            wasmImageForVersion: mergePerVersion(
                cli: parseWasmImageOverrides(), configValue: config?.wasmImage
            ),
            wasmSDKURLForVersion: mergePerVersion(
                cli: parseWasmSDKURLOverrides(), configValue: config?.wasmSDKURL
            ),
            pullAlways: pullAlways || (config?.pullAlways ?? false),
            verbose: verbose || (config?.verbose ?? false),
            timeoutSeconds: timeoutSeconds ?? config?.timeoutSeconds,
            runTests: effectiveRunTests,
            testNoParallel: activeTestNoParallel,
            containerRuntime: try Self.resolveContainerRuntime(
                cli: containerRuntimeRaw, config: config?.containerRuntime
            ),
            installContainer: activeContainerPackages
        )

        let effectiveNoLive = noLive || (config?.noLive ?? false)

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
        let parallelism = max(1, maxParallel ?? config?.maxParallel ?? (ProcessInfo.processInfo.activeProcessorCount / 2))
        let useLive = !quiet && !effectiveNoLive && isStdoutTTY()
        if !quiet {
            print("Logs:      \(cache.runLogDir.path)")
            print("Parallel:  \(parallelism) cell\(parallelism == 1 ? "" : "s") per Swift version")
            print("")
        }

        // Host packages install once up front (the Mac is shared across every
        // Apple cell). Skip entirely when no Apple platform is in the selection
        // so a Linux-only `--install-host` run doesn't touch the machine. A brew
        // failure is non-fatal — container cells still run.
        let hasApplePlatform = platforms.contains { AppleRunner.supportedPlatforms.contains($0) }
        if !activeHostPackages.isEmpty, hasApplePlatform {
            let installed = await HostInstaller().brewInstall(activeHostPackages, quiet: quiet)
            if !installed, !quiet {
                print("⚠️  Host install failed; Apple test cells may fail if they need these packages. Continuing.\n")
            }
        }

        let context = RunContext(
            packagePath: packageURL,
            scheme: detectedScheme,
            cache: cache,
            options: runOptions
        )
        let dispatcher = MatrixDispatcher(containerRuntime: runOptions.containerRuntime)

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

        printFailureSummary(
            outcomes: outcomes,
            platforms: platforms,
            swiftVersions: swiftVersions
        )

        let failed = outcomes.values.contains { $0.state == .fail }
        if failed {
            throw ExitCode.failure
        }
    }

    /// Print a "Failed cells:" footer listing each `.fail` outcome with its log
    /// path. Cells are emitted in matrix order (swift version then platform) so
    /// the listing visually mirrors the table that just rendered above it. Safe
    /// in all three output modes — live, streaming, and quiet — because it runs
    /// AFTER Noora's stateful renderer has finished its last erase/redraw cycle,
    /// so the cursor sits naturally below the matrix.
    private func printFailureSummary(
        outcomes: [BuildPair: CellOutcome],
        platforms: [Platform],
        swiftVersions: [SwiftVersion]
    ) {
        var failures: [(pair: BuildPair, logPath: URL)] = []
        for swiftVersion in swiftVersions {
            for platform in platforms {
                let pair = BuildPair(platform: platform, swiftVersion: swiftVersion)
                guard let outcome = outcomes[pair], outcome.state == .fail else { continue }
                guard let logPath = outcome.logPath else { continue }
                failures.append((pair, logPath))
            }
        }
        guard !failures.isEmpty else { return }

        let labels = failures.map { "\($0.pair.platform.rawValue) × Swift \($0.pair.swiftVersion.rawValue)" }
        let width = labels.map(\.count).max() ?? 0

        print("")
        print("Failed cells (\(failures.count)):")
        for (i, (_, logPath)) in failures.enumerated() {
            let padded = labels[i].padding(toLength: width, withPad: " ", startingAt: 0)
            print("  ✗ \(padded)  \(logPath.path)")
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

    static func resolveContainerRuntime(
        cli: String?, config: ContainerRuntime?
    ) throws -> ContainerRuntime {
        if let cli, !cli.isEmpty {
            guard let runtime = ContainerRuntime(rawValue: cli) else {
                throw ValidationError(
                    "Unknown --container-runtime: \(cli). Allowed: \(ContainerRuntime.allCases.map(\.rawValue).joined(separator: ", "))."
                )
            }
            return runtime
        }
        return config ?? .docker
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

    private func parseSwiftVersions(_ raw: String?, config: SPCCConfig?) throws -> [SwiftVersion] {
        if let raw, !raw.isEmpty {
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
        if let configVersions = config?.swiftVersions, !configVersions.isEmpty {
            return configVersions
        }
        return SwiftVersion.allCases
    }

    private func parsePlatforms(_ raw: String?, config: SPCCConfig?) throws -> [Platform] {
        if let raw, !raw.isEmpty {
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
        if let configPlatforms = config?.platforms, !configPlatforms.isEmpty {
            return configPlatforms
        }
        return Platform.allCases
    }

    /// Characters allowed in a system package name. Deliberately strict — these
    /// strings are spliced into a `bash -c` body (apt) and a `brew install` argv,
    /// so anything outside this set is rejected rather than escaped.
    private static let installNameAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"
    )

    /// Parse a comma-separated package list (CLI wins; config is the fallback),
    /// validating each name. Returns `[]` when neither source provides one.
    private func parseInstallList(_ raw: String?, configValue: [String]?) throws -> [String] {
        let source: [String]
        if let raw, !raw.isEmpty {
            source = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            source = configValue ?? []
        }
        let packages = source.filter { !$0.isEmpty }
        for pkg in packages {
            guard !pkg.hasPrefix("-"),
                  pkg.unicodeScalars.allSatisfy({ Self.installNameAllowed.contains($0) })
            else {
                throw ValidationError(
                    "Invalid package name '\(pkg)'. Allowed: ASCII letters, digits, and . _ + - (no leading '-')."
                )
            }
        }
        return packages
    }

    /// Merge per-Swift-version maps: CLI value wins; config fills in missing keys.
    private func mergePerVersion(
        cli: [SwiftVersion: String],
        configValue: [SwiftVersion: String]?
    ) -> [SwiftVersion: String] {
        guard let configValue, !configValue.isEmpty else { return cli }
        var merged = configValue
        for (k, v) in cli { merged[k] = v }
        return merged
    }

    /// Same as mergePerVersion but for the Xcode override which is a URL map.
    private func mergeXcodeOverrides(config: SPCCConfig?) -> [SwiftVersion: URL] {
        let cli = parseXcodeOverrides()
        guard let configXcode = config?.xcode, !configXcode.isEmpty else { return cli }
        var merged: [SwiftVersion: URL] = configXcode.mapValues { URL(fileURLWithPath: $0) }
        for (k, v) in cli { merged[k] = v }
        return merged
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
