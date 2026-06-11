import Command
import Foundation

/// Installs extra system packages on the host Mac via Homebrew before the
/// Apple-platform cells (`macos-spm`, `ios`, …) run their `swift test` /
/// `xcodebuild test`. Unlike the container installs, these run **once** up front
/// — the host is shared across every Apple cell — and they **persist** on the
/// user's machine after the run, since brew installs aren't sandboxed.
///
/// Gated behind `--test` and only invoked when the selected platforms include at
/// least one Apple cell. A brew failure is non-fatal: it's reported and the run
/// continues so container cells still execute.
public struct HostInstaller: Sendable {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Runs `brew install <packages>`, streaming its output to stdout unless
    /// `quiet`. Returns `true` on success, `false` if brew exits non-zero or
    /// isn't found — the caller warns and continues rather than aborting.
    public func brewInstall(_ packages: [String], quiet: Bool = false) async -> Bool {
        guard !packages.isEmpty else { return true }
        if !quiet {
            print("Host install: brew install \(packages.joined(separator: " "))")
        }
        do {
            for try await event in commandRunner.run(arguments: ["brew", "install"] + packages) {
                guard !quiet else { continue }
                switch event {
                case .standardOutput(let bytes), .standardError(let bytes):
                    try FileHandle.standardOutput.write(contentsOf: bytes)
                }
            }
            if !quiet { print("") }
            return true
        } catch {
            if !quiet { print("spcc: brew install failed: \(error)") }
            return false
        }
    }
}
