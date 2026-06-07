import Command
import Foundation

/// Runs the `linux` cells of the SPI matrix via `docker run` against
/// `registry.gitlab.com/swiftpackageindex/spi-images:basic-X.Y-latest`. Non-linux
/// platforms are returned `.pending` so this runner can sit in a dispatcher that
/// asks every platform without branching.
public struct LinuxRunner: Sendable {
    public static let supportedPlatforms: Set<Platform> = [.linux]

    private let streamer: LogStreamer

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.streamer = LogStreamer(commandRunner: commandRunner)
    }

    public func run(pair: BuildPair, context: RunContext) async -> CellOutcome {
        guard pair.platform == .linux else {
            return CellOutcome(state: .pending)
        }

        guard let image = resolveImage(for: pair.swiftVersion, options: context.options) else {
            return CellOutcome(
                state: .fail,
                errorMessage: "no Linux builder image configured for Swift \(pair.swiftVersion.rawValue)"
            )
        }

        let cellLabel = "\(context.cache.runTimestamp)-\(pair.platform.rawValue)-\(pair.swiftVersion.rawValue)"
        let arguments = LinuxArgvBuilders.docker(
            packagePath: context.packagePath,
            packageBasename: context.cache.packageBasename,
            swiftVersion: pair.swiftVersion,
            image: image,
            pullPolicy: context.options.pullPolicy,
            cellLabel: cellLabel
        )

        let logPath = context.cache.logPath(for: pair)
        let result = await streamer.run(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            logPath: logPath,
            timeoutSeconds: context.options.timeoutSeconds,
            onTimeout: { await LogStreamer.defaultDockerKill(cellLabel) }
        )
        return result.cellOutcome(logPath: logPath)
    }

    private func resolveImage(for swiftVersion: SwiftVersion, options: RunOptions) -> String? {
        if let override = options.linuxImageForVersion[swiftVersion], !override.isEmpty {
            return override
        }
        return Platform.linux.defaultDockerImage(for: swiftVersion)
    }
}
