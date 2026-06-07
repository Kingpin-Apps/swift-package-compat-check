import Command
import Foundation

/// Runs the `android` and `wasm` cells via SPI's public builder images. Mirrors
/// the bash script's `run_android` / `run_wasm` functions, which both delegate to
/// the same `run_cross_sdk` core — kept as a single runner here for the same
/// reason.
public struct CrossSDKRunner: Sendable {
    public static let supportedPlatforms: Set<Platform> = [.android, .wasm]

    private let streamer: LogStreamer

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.streamer = LogStreamer(commandRunner: commandRunner)
    }

    public func run(pair: BuildPair, context: RunContext) async -> CellOutcome {
        guard Self.supportedPlatforms.contains(pair.platform) else {
            return CellOutcome(state: .pending)
        }
        guard pair.isSupportedBySPI else {
            return CellOutcome(state: .skipped)
        }

        guard let image = resolveImage(for: pair, options: context.options) else {
            return CellOutcome(
                state: .fail,
                errorMessage: "no \(pair.platform.rawValue) builder image configured for Swift \(pair.swiftVersion.rawValue)"
            )
        }

        let arguments: [String]
        switch pair.platform {
        case .android:
            arguments = CrossSDKArgvBuilders.android(
                packagePath: context.packagePath,
                packageBasename: context.cache.packageBasename,
                swiftVersion: pair.swiftVersion,
                image: image,
                pullPolicy: context.options.pullPolicy
            )
        case .wasm:
            arguments = CrossSDKArgvBuilders.wasm(
                packagePath: context.packagePath,
                packageBasename: context.cache.packageBasename,
                swiftVersion: pair.swiftVersion,
                image: image,
                pullPolicy: context.options.pullPolicy,
                fallbackURL: context.options.wasmSDKURLForVersion[pair.swiftVersion]
                    ?? Platform.wasm.defaultWasmSDKURL(for: pair.swiftVersion)
            )
        default:
            return CellOutcome(state: .pending)
        }

        let logPath = context.cache.logPath(for: pair)
        let result = await streamer.run(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            logPath: logPath
        )
        return result.cellOutcome(logPath: logPath)
    }

    private func resolveImage(for pair: BuildPair, options: RunOptions) -> String? {
        let override: String?
        switch pair.platform {
        case .android: override = options.androidImageForVersion[pair.swiftVersion]
        case .wasm: override = options.wasmImageForVersion[pair.swiftVersion]
        default: override = nil
        }
        if let override, !override.isEmpty { return override }
        return pair.platform.defaultDockerImage(for: pair.swiftVersion)
    }
}
