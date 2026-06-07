import Command
import Foundation

/// Routes each `BuildPair` to the runner that owns its platform. Apple cells go to
/// `AppleRunner`; Linux/Android/Wasm return `.pending` until Phase 3-4 of
/// [[swift-package-compat-check]] adds their docker-backed runners.
public struct MatrixDispatcher: Sendable {
    private let appleRunner: AppleRunner

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.appleRunner = AppleRunner(commandRunner: commandRunner)
    }

    public func run(pair: BuildPair, context: RunContext) async -> CellOutcome {
        if !pair.isSupportedBySPI {
            return CellOutcome(state: .skipped)
        }
        if AppleRunner.supportedPlatforms.contains(pair.platform) {
            return await appleRunner.run(pair: pair, context: context)
        }
        // Linux / Android / Wasm — Phase 3-4.
        return CellOutcome(state: .pending)
    }
}
