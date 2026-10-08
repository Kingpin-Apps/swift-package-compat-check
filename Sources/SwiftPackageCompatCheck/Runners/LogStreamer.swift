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
    ///
    /// When `stallSeconds` is set, a second watchdog fails the cell (through the
    /// same `onTimeout` kill) once the subprocess has written nothing for that
    /// long. A hung process uses no CPU and prints nothing, so this catches it
    /// long before the overall budget runs out.
    ///
    /// A failure whose log shows the container runtime ran out of disk gets a
    /// message saying so instead of the bare exit status.
    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logPath: URL,
        timeoutSeconds: Double? = nil,
        stallSeconds: Double? = nil,
        onTimeout: (@Sendable () async -> Void)? = nil
    ) async -> Result {
        let result = await runWatched(
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            logPath: logPath,
            timeoutSeconds: timeoutSeconds,
            stallSeconds: stallSeconds,
            onTimeout: onTimeout
        )
        if case .failure(let message, let duration) = result,
           let hint = Self.diagnosis(logPath: logPath) {
            return .failure(message: "\(hint) (\(message))", durationSeconds: duration)
        }
        return result
    }

    private func runWatched(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logPath: URL,
        timeoutSeconds: Double?,
        stallSeconds: Double?,
        onTimeout: (@Sendable () async -> Void)?
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
        let timeout = timeoutSeconds.flatMap { $0 > 0 ? $0 : nil }
        let stall = stallSeconds.flatMap { $0 > 0 ? $0 : nil }

        // Fast path: no watchdog configured, run the stream directly.
        guard timeout != nil || stall != nil else {
            return await streamUntilExit(
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory,
                logHandle: logHandle,
                start: start,
                activity: nil
            )
        }

        let activity = OutputActivity(start: start)
        return await withTaskGroup(of: TimedRunResult.self) { group in
            group.addTask {
                let result = await self.streamUntilExit(
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    logHandle: logHandle,
                    start: start,
                    activity: activity
                )
                return .completed(result)
            }
            if let timeout {
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    if Task.isCancelled { return .cancelled }
                    await onTimeout?()
                    return .stopped(
                        reason: "timed out after \(Int(timeout))s",
                        killed: onTimeout != nil
                    )
                }
            }
            if let stall {
                group.addTask {
                    // Check a few times per stall window, at most every 30s.
                    let interval = min(30, max(0.05, stall / 4))
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(interval))
                        if Task.isCancelled { return .cancelled }
                        if await activity.idleSeconds() >= stall { break }
                    }
                    if Task.isCancelled { return .cancelled }
                    await onTimeout?()
                    return .stopped(
                        reason: "no output for \(Int(stall))s (stalled)",
                        killed: onTimeout != nil
                    )
                }
            }
            guard let first = await group.next() else {
                group.cancelAll()
                return .failure(message: "task group returned no results", durationSeconds: 0)
            }
            switch first {
            case .completed(let r):
                group.cancelAll()
                return r
            case .stopped(let why, let killed):
                let elapsed = Self.elapsedSeconds(since: start)
                let reason = killed ? "\(why); container killed" : why
                try? logHandle.write(contentsOf: Array("\nspcc: \(reason)\n".utf8))
                // Cancel the streaming task BEFORE draining it — otherwise
                // group.next() would wait the full natural duration.
                group.cancelAll()
                while await group.next() != nil {}
                return .failure(message: reason, durationSeconds: elapsed)
            case .cancelled:
                group.cancelAll()
                return .failure(message: "watchdog cancelled", durationSeconds: Self.elapsedSeconds(since: start))
            }
        }
    }

    private enum TimedRunResult: Sendable {
        case completed(Result)
        case stopped(reason: String, killed: Bool)
        case cancelled
    }

    /// When the subprocess last wrote anything, for the stall watchdog.
    private actor OutputActivity {
        private var last: ContinuousClock.Instant

        init(start: ContinuousClock.Instant) { last = start }

        func touch() { last = .now }

        func idleSeconds() -> Double {
            let idle = ContinuousClock.now - last
            return Double(idle.components.seconds) + Double(idle.components.attoseconds) / 1e18
        }
    }

    /// A plain-language cause for a failure, read from the end of its log.
    /// Only covers causes outside the package itself; `nil` otherwise.
    static func diagnosis(logPath: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: logPath) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        guard let data = try? handle.readToEnd(),
              let tail = String(data: data, encoding: .utf8)?.lowercased()
        else { return nil }
        if tail.contains("no space left on device") {
            return "the container runtime ran out of disk space; free some (spcc images --remove, spcc clean-all, docker system prune) or raise its disk limit"
        }
        if tail.contains("swiftpackageindex/spi-images"),
           tail.contains("access forbidden") || tail.contains("denied") || tail.contains("unauthorized") {
            return "the registry refused to pull SPI's builder image (registry.gitlab.com/swiftpackageindex/spi-images is no longer public); use --linux-mode native, or an image you can pull via --linux-image-X.Y / --android-image-X.Y / --wasm-image-X.Y"
        }
        return nil
    }

    private func streamUntilExit(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        logHandle: FileHandle,
        start: ContinuousClock.Instant,
        activity: OutputActivity?
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
                    await activity?.touch()
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
