import Command
import Foundation
import Path
import Testing
@testable import SwiftPackageCompatCheck

/// CommandRunning stub that sleeps for `delay` before finishing — used to
/// exercise LogStreamer's timeout path without launching a real subprocess.
final class SleepingCommandRunner: CommandRunning, @unchecked Sendable {
    let delay: Duration
    init(delay: Duration) { self.delay = delay }

    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        let d = delay
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(for: d)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

@Suite("LogStreamer.timeout")
struct LogStreamerTimeoutTests {
    private static func tmpLog() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-timeout-\(UUID().uuidString).log")
    }

    @Test("Subprocess that finishes within budget reports .success")
    func underBudget() async throws {
        let streamer = LogStreamer(commandRunner: SleepingCommandRunner(delay: .milliseconds(50)))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log,
            timeoutSeconds: 5,
            onTimeout: { Issue.record("onTimeout fired but cell finished in time"); return }
        )
        if case .success = result { /* ok */ } else {
            Issue.record("expected .success, got \(result)")
        }
    }

    @Test("Subprocess that exceeds budget triggers onTimeout and reports .failure")
    func overBudget() async throws {
        let streamer = LogStreamer(commandRunner: SleepingCommandRunner(delay: .seconds(10)))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let killCalled = Locked(false)
        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log,
            timeoutSeconds: 0.2,
            onTimeout: { await killCalled.set(true) }
        )
        guard case .failure(let message, _) = result else {
            Issue.record("expected .failure on timeout, got \(result)")
            return
        }
        #expect(message.contains("timed out"))
        #expect(await killCalled.value == true)
        // The log file should also record the timeout.
        let logContents = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(logContents.contains("timed out"))
    }

    @Test("Setting timeoutSeconds=nil keeps the old fast path (no timeout watchdog)")
    func noTimeoutConfigured() async {
        let streamer = LogStreamer(commandRunner: SleepingCommandRunner(delay: .milliseconds(20)))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log,
            timeoutSeconds: nil,
            onTimeout: nil
        )
        if case .success = result { /* ok */ } else {
            Issue.record("expected .success, got \(result)")
        }
    }
}

/// Trivial actor-backed lock for the timeout tests. Avoids importing third-party
/// sync primitives just for these two tests.
actor Locked<T: Sendable> {
    var value: T
    init(_ initial: T) { self.value = initial }
    func set(_ new: T) { self.value = new }
}

@Suite("Cross-SDK + Linux argv carry the spcc-cell label when provided")
struct DockerLabelTests {
    @Test("Linux docker argv includes --label spcc-cell=<label> when given")
    func linuxLabelled() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            cellLabel: "RUN-linux-6.3"
        )
        #expect(argv.contains("--label"))
        #expect(argv.contains("spcc-cell=RUN-linux-6.3"))
    }

    @Test("Cross-SDK android argv includes the same label structure")
    func androidLabelled() {
        let argv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            cellLabel: "RUN-android-6.3"
        )
        #expect(argv.contains("--label"))
        #expect(argv.contains("spcc-cell=RUN-android-6.3"))
    }

    @Test("Without a cellLabel the --label arg is absent (no timeout configured)")
    func labelOptional() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            cellLabel: nil
        )
        #expect(!argv.contains("--label"))
    }
}
