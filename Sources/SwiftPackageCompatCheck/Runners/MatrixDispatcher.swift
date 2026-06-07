import Command
import Foundation

/// Routes each `BuildPair` to the runner that owns its platform. Apple cells go to
/// `AppleRunner`, Linux to `LinuxRunner`, Android/Wasm to `CrossSDKRunner`.
public struct MatrixDispatcher: Sendable {
    private let appleRunner: AppleRunner
    private let linuxRunner: LinuxRunner
    private let crossSDKRunner: CrossSDKRunner

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.appleRunner = AppleRunner(commandRunner: commandRunner)
        self.linuxRunner = LinuxRunner(commandRunner: commandRunner)
        self.crossSDKRunner = CrossSDKRunner(commandRunner: commandRunner)
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
        if CrossSDKRunner.supportedPlatforms.contains(pair.platform) {
            return await crossSDKRunner.run(pair: pair, context: context)
        }
        return CellOutcome(state: .pending)
    }
}
