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

    /// Container-kill hook the timeout watchdog calls when a cell exceeds its
    /// budget. Runners pick the concrete closure from
    /// `ContainerRuntime.killClosure` based on whichever runtime they're
    /// targeting.
    typealias KillHandler = @Sendable (String) async -> Void

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
    ///
    /// When `timeoutSeconds` is set, a watchdog task races against the subprocess
    /// stream and calls `onTimeout` if the budget is exceeded. For docker-backed
    /// runners `onTimeout` should fire `docker kill` against a container labelled
    /// with `cellLabel` — Task cancellation alone wouldn't reach the container.
    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logPath: URL,
        timeoutSeconds: Double? = nil,
        onTimeout: (@Sendable () async -> Void)? = nil
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

        // Fast path: no timeout configured, run the stream directly.
        guard let timeoutSeconds, timeoutSeconds > 0 else {
            return await streamUntilExit(
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory,
                logHandle: logHandle,
                start: start
            )
        }

        return await withTaskGroup(of: TimedRunResult.self) { group in
            group.addTask {
                let result = await self.streamUntilExit(
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    logHandle: logHandle,
                    start: start
                )
                return .completed(result)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if Task.isCancelled { return .timedOut(false) }
                await onTimeout?()
                return .timedOut(true)
            }
            guard let first = await group.next() else {
                group.cancelAll()
                return .failure(message: "task group returned no results", durationSeconds: 0)
            }
            switch first {
            case .completed(let r):
                group.cancelAll()
                return r
            case .timedOut(let killed):
                let elapsed = Self.elapsedSeconds(since: start)
                let reason = killed
                    ? "timed out after \(Int(timeoutSeconds))s; container killed"
                    : "timed out after \(Int(timeoutSeconds))s"
                try? logHandle.write(contentsOf: Array("\nspcc: \(reason)\n".utf8))
                // Cancel the streaming task BEFORE draining it — otherwise
                // group.next() would wait the full natural duration.
                group.cancelAll()
                _ = await group.next()
                return .failure(message: reason, durationSeconds: elapsed)
            }
        }
    }

    private enum TimedRunResult: Sendable {
        case completed(Result)
        case timedOut(Bool)
    }

    private func streamUntilExit(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logHandle: FileHandle,
        start: ContinuousClock.Instant
    ) async -> Result {
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
