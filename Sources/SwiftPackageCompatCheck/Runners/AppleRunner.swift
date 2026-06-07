import Command
import Foundation
import Path

/// Runs the Apple-platform cells of the SPI matrix: `macos-spm`, `macos-xcodebuild`,
/// `ios`, `tvos`, `watchos`, `visionos`. Streams stdout+stderr to a per-cell log file
/// and reports `.pass`/`.fail` based on the process's termination status.
///
/// Non-Apple platforms (`linux`, `android`, `wasm`) are dispatched to docker-backed
/// runners in Phase 3-4 of [[swift-package-compat-check]]; this runner returns
/// `.pending` for them so the matrix UI still shows progress.
public struct AppleRunner: Sendable {
    public static let supportedPlatforms: Set<Platform> = [
        .macosSPM, .macosXcodebuild, .ios, .tvos, .watchos, .visionos,
    ]

    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func run(pair: BuildPair, context: RunContext) async -> CellOutcome {
        guard Self.supportedPlatforms.contains(pair.platform) else {
            return CellOutcome(state: .pending, durationSeconds: 0)
        }

        let arguments: [String]
        switch pair.platform {
        case .macosSPM:
            arguments = AppleArgvBuilders.macosSPM(
                toolchain: context.options.toolchainForVersion[pair.swiftVersion]
            )
        case .macosXcodebuild, .ios, .tvos, .watchos, .visionos:
            guard let argv = AppleArgvBuilders.xcodebuild(
                pair: pair,
                scheme: context.scheme,
                derivedDataPath: context.cache.derivedDataDir(for: pair),
                clonedPackagesPath: context.cache.clonedPackagesDir
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

        let logPath = context.cache.logPath(for: pair)
        try? FileManager.default.createDirectory(
            at: logPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logPath.path, contents: nil)

        var environment = ProcessInfo.processInfo.environment
        if let developerDir = context.options.developerDir(for: pair.swiftVersion) {
            environment["DEVELOPER_DIR"] = developerDir
        }

        let workingDirectory: Path.AbsolutePath? = try? Path.AbsolutePath(
            validating: context.packagePath.path
        )

        let start = ContinuousClock.now
        let result = await stream(
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            logPath: logPath
        )
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        switch result {
        case .success:
            return CellOutcome(state: .pass, logPath: logPath, durationSeconds: seconds)
        case .failure(let message):
            return CellOutcome(
                state: .fail,
                logPath: logPath,
                durationSeconds: seconds,
                errorMessage: message
            )
        }
    }

    private enum CellResult { case success, failure(String) }

    private func stream(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logPath: URL
    ) async -> CellResult {
        guard let logHandle = try? FileHandle(forWritingTo: logPath) else {
            return .failure("could not open log file at \(logPath.path)")
        }
        defer { try? logHandle.close() }

        do {
            for try await event in commandRunner.run(
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            ) {
                switch event {
                case .standardOutput(let bytes), .standardError(let bytes):
                    try logHandle.write(contentsOf: bytes)
                }
            }
            return .success
        } catch {
            try? logHandle.write(contentsOf: Array("\nspcc: \(error)\n".utf8))
            return .failure("\(error)")
        }
    }
}
