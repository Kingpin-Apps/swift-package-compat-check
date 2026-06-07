import Command
import Foundation
import Path

/// Runs the Apple-platform cells of the SPI matrix: `macos-spm`, `macos-xcodebuild`,
/// `ios`, `tvos`, `watchos`, `visionos`. Streams stdout+stderr to a per-cell log file
/// and reports `.pass`/`.fail` based on the process's termination status.
///
/// Non-Apple platforms (`linux`, `android`, `wasm`) are dispatched to docker-backed
/// runners; this runner returns `.pending` for them so the matrix UI still renders.
public struct AppleRunner: Sendable {
    public static let supportedPlatforms: Set<Platform> = [
        .macosSPM, .macosXcodebuild, .ios, .tvos, .watchos, .visionos,
    ]

    private let streamer: LogStreamer

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.streamer = LogStreamer(commandRunner: commandRunner)
    }

    public func run(pair: BuildPair, context: RunContext) async -> CellOutcome {
        guard Self.supportedPlatforms.contains(pair.platform) else {
            return CellOutcome(state: .pending)
        }

        let arguments: [String]
        switch pair.platform {
        case .macosSPM:
            arguments = AppleArgvBuilders.macosSPM(
                toolchain: context.options.toolchainForVersion[pair.swiftVersion],
                runTests: context.options.runTests
            )
        case .macosXcodebuild, .ios, .tvos, .watchos, .visionos:
            guard let argv = AppleArgvBuilders.xcodebuild(
                pair: pair,
                scheme: context.scheme,
                derivedDataPath: context.cache.derivedDataDir(for: pair),
                clonedPackagesPath: context.cache.clonedPackagesDir,
                runTests: context.options.runTests
            ) else {
                return CellOutcome(
                    state: .fail,
                    errorMessage: "no xcodebuild destination for \(pair.platform.rawValue)"
                )
            }
            arguments = argv
        case .linux, .android, .wasm:
            return CellOutcome(state: .pending)
        }

        var environment = ProcessInfo.processInfo.environment
        if let developerDir = context.options.developerDir(for: pair.swiftVersion) {
            environment["DEVELOPER_DIR"] = developerDir
        }

        let workingDirectory: Path.AbsolutePath? = try? Path.AbsolutePath(
            validating: context.packagePath.path
        )

        let logPath = context.cache.logPath(for: pair)
        let result = await streamer.run(
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            logPath: logPath
        )
        return result.cellOutcome(logPath: logPath)
    }
}
