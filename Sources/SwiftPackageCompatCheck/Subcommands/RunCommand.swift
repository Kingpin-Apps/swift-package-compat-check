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
        if !quiet {
            print("Logs:      \(cache.runLogDir.path)")
            print("")
        }

        let context = RunContext(
            packagePath: packageURL,
            scheme: detectedScheme,
            cache: cache,
            options: runOptions
        )
        let dispatcher = MatrixDispatcher()

        var outcomes: [BuildPair: CellOutcome] = [:]
        for swiftVersion in swiftVersions {
            for platform in platforms {
                let pair = BuildPair(platform: platform, swiftVersion: swiftVersion)
                let outcome = await dispatcher.run(pair: pair, context: context)
                outcomes[pair] = outcome
                if !quiet {
                    let symbol = outcome.state.symbol
                    let secs = String(format: "%.1fs", outcome.durationSeconds)
                    print("  \(symbol) \(platform.rawValue) × Swift \(swiftVersion.rawValue) (\(secs))")
                }
            }
        }

        if !quiet { print("") }
        MatrixRenderer().render(platforms: platforms, swiftVersions: swiftVersions) { pair in
            outcomes[pair]?.state ?? (pair.isSupportedBySPI ? .pending : .skipped)
        }

        let failed = outcomes.values.contains { $0.state == .fail }
        if failed {
            throw ExitCode.failure
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
