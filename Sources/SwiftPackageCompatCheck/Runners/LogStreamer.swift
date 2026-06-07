import Command
import Foundation
import Path

/// Shared subprocess-streaming helper used by every runner. Opens a per-cell log
/// file, streams stdout+stderr through it, times the run, and reports a typed
/// outcome. Lifted out of `AppleRunner` in Phase 3 so the Linux/Android/Wasm
/// runners don't duplicate the same setup.
struct LogStreamer: Sendable {
    let commandRunner: any CommandRunning

    init(commandRunner: any CommandRunning) {
        self.commandRunner = commandRunner
    }

    enum Result: Sendable {
        case success(durationSeconds: Double)
        case failure(message: String, durationSeconds: Double)

        var durationSeconds: Double {
            switch self {
            case .success(let d), .failure(_, let d): d
            }
        }

        func cellOutcome(logPath: URL) -> CellOutcome {
            switch self {
            case .success(let d):
                CellOutcome(state: .pass, logPath: logPath, durationSeconds: d)
            case .failure(let m, let d):
                CellOutcome(state: .fail, logPath: logPath, durationSeconds: d, errorMessage: m)
            }
        }
    }

    /// Streams the subprocess's stdout+stderr to `logPath`. Caller is responsible
    /// for choosing the cwd / environment / argv. Returns `.success` if the stream
    /// completes without throwing; `.failure(message)` if the subprocess exits
    /// non-zero or the stream throws for any other reason.
    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logPath: URL
    ) async -> Result {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: logPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fm.createFile(atPath: logPath.path, contents: nil)

        guard let logHandle = try? FileHandle(forWritingTo: logPath) else {
            return .failure(message: "could not open log file at \(logPath.path)", durationSeconds: 0)
        }
        defer { try? logHandle.close() }

        let start = ContinuousClock.now

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
            return .success(durationSeconds: Self.elapsedSeconds(since: start))
        } catch {
            try? logHandle.write(contentsOf: Array("\nspcc: \(error)\n".utf8))
            return .failure(message: "\(error)", durationSeconds: Self.elapsedSeconds(since: start))
        }
    }

    private static func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
    }
}
