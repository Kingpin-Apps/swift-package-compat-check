import Command
import Foundation

/// Runs the `linux` cells of the SPI matrix via `<runtime> run` against
/// `registry.gitlab.com/swiftpackageindex/spi-images:basic-X.Y-latest`.
/// `runtime` is whichever host-side container CLI the user picked
/// (`docker` by default; `apple/container` opt-in via `--container-runtime`).
/// Non-linux platforms are returned `.pending` so this runner can sit in a
/// dispatcher that asks every platform without branching.
public struct LinuxRunner: Sendable {
    public static let supportedPlatforms: Set<Platform> = [.linux]

    private let streamer: LogStreamer
    private let pullCoordinator: ImagePullCoordinator?

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        pullCoordinator: ImagePullCoordinator? = nil
    ) {
        self.streamer = LogStreamer(commandRunner: commandRunner)
        self.pullCoordinator = pullCoordinator
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

        let runtime = context.options.containerRuntime
        let cellLabel = "\(context.cache.runTimestamp)-\(pair.platform.rawValue)-\(pair.swiftVersion.rawValue)"

        // Container runtime needs an explicit pre-pull (no `run --pull` flag).
        // Docker's inline `--pull=` carries this on `run` so the coordinator
        // is a no-op there. Either way, a failed pull surfaces as a cell .fail.
        if let pullCoordinator {
            do {
                try await pullCoordinator.ensurePulled(
                    image: image, policy: context.options.pullPolicy
                )
            } catch {
                return CellOutcome(
                    state: .fail,
                    errorMessage: "image pull failed: \(error)"
                )
            }
        }

        let arguments = LinuxArgvBuilders.docker(
            packagePath: context.packagePath,
            packageBasename: context.cache.packageBasename,
            swiftVersion: pair.swiftVersion,
            image: image,
            pullPolicy: context.options.pullPolicy,
            cellLabel: cellLabel,
            runTests: context.options.runTests,
            runtime: runtime,
            useRosetta: context.options.useRosetta == true
        )

        let logPath = context.cache.logPath(for: pair)
        let killClosure = runtime.killClosure
        let result = await streamer.run(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            logPath: logPath,
            timeoutSeconds: context.options.timeoutSeconds,
            onTimeout: { await killClosure(cellLabel) }
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
