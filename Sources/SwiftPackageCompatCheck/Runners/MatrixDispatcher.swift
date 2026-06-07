import Command
import Foundation

/// Routes each `BuildPair` to the runner that owns its platform. Apple cells go to
/// `AppleRunner`, Linux cells to `LinuxRunner`. Android/Wasm return `.pending`
/// until Phase 4 adds their docker-backed runners.
public struct MatrixDispatcher: Sendable {
    private let appleRunner: AppleRunner
    private let linuxRunner: LinuxRunner

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.appleRunner = AppleRunner(commandRunner: commandRunner)
        self.linuxRunner = LinuxRunner(commandRunner: commandRunner)
    }

    public func run(pair: BuildPair, context: RunContext) async -> CellOutcome {
        if !pair.isSupportedBySPI {
            return CellOutcome(state: .skipped)
        }
        if AppleRunner.supportedPlatforms.contains(pair.platform) {
            return await appleRunner.run(pair: pair, context: context)
        }
        if LinuxRunner.supportedPlatforms.contains(pair.platform) {
            return await linuxRunner.run(pair: pair, context: context)
        }
        // Android / Wasm — Phase 4.
        return CellOutcome(state: .pending)
    }
}
