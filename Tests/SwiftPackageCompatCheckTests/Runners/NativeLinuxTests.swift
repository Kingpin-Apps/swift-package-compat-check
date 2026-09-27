import Command
import Foundation
import Path
import Testing
@testable import SwiftPackageCompatCheck

@Suite("LinuxMode")
struct LinuxModeTests {
    @Test("native uses the official swift:X.Y-jammy image; spi keeps SPI's basic image")
    func defaultImages() {
        #expect(LinuxMode.native.defaultImage(for: .v6_2) == "swift:6.2-jammy")
        #expect(LinuxMode.native.defaultImage(for: .v6_4) == "swift:6.4-jammy")
        #expect(LinuxMode.spi.defaultImage(for: .v6_3)
                == Platform.linux.defaultDockerImage(for: .v6_3))
    }

    @Test("only spi pins linux/amd64")
    func containerPlatform() {
        #expect(LinuxMode.native.containerPlatform == nil)
        #expect(LinuxMode.spi.containerPlatform == "linux/amd64")
    }
}

@Suite("LinuxArgvBuilders native mode")
struct NativeLinuxArgvTests {
    @Test("native argv has no amd64 platform, triple or JAVA_HOME, and its own volume")
    func nativeShape() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/Users/me/swift-nacl"),
            packageBasename: "swift-nacl",
            swiftVersion: .v6_3,
            image: "swift:6.3-jammy",
            pullPolicy: .missing,
            mode: .native
        )
        #expect(argv.prefix(4) == ["docker", "run", "--pull=missing", "--rm"])
        #expect(!argv.contains("--platform"))
        #expect(argv.contains("spi-compat-build-swift-nacl-6.3-native:/build"))
        #expect(!argv.contains { $0.hasPrefix("JAVA_HOME=") })
        #expect(argv.contains("SPI_BUILD=1"))
        #expect(argv.contains("SPI_PROCESSING=1"))
        let script = argv.last ?? ""
        #expect(script.contains("swift build --scratch-path /build"))
        #expect(!script.contains("--triple"))
    }

    @Test("native test mode runs swift test without a triple")
    func nativeTest() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_2,
            image: "swift:6.2-jammy",
            pullPolicy: .missing,
            runTests: true,
            noParallel: true,
            mode: .native
        )
        #expect(argv.last?.contains("swift test --scratch-path /build --no-parallel") == true)
    }

    @Test("native on apple/container drops --platform and never adds --rosetta")
    func nativeContainerRuntime() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "swift:6.3-jammy",
            pullPolicy: .missing,
            cellLabel: "c",
            runtime: .container,
            useRosetta: true,
            mode: .native
        )
        #expect(argv.first == "container")
        #expect(!argv.contains("--platform"))
        #expect(!argv.contains("--rosetta"))
        #expect(argv.contains("--name"))
    }

    @Test("native and spi volumes never collide")
    func volumeNames() {
        #expect(LinuxArgvBuilders.volumeName(packageBasename: "p", swiftVersion: .v6_2)
                == "spi-compat-build-p-6.2")
        #expect(LinuxArgvBuilders.volumeName(packageBasename: "p", swiftVersion: .v6_2, mode: .native)
                == "spi-compat-build-p-6.2-native")
    }

    @Test("container pull argv omits --platform for native images")
    func pullArgv() {
        #expect(ContainerRuntime.container.pullArgv(image: "swift:6.2-jammy", platform: nil)
                == ["container", "image", "pull", "swift:6.2-jammy"])
        #expect(ContainerRuntime.container.pullArgv(image: "img")
                == ["container", "image", "pull", "--platform", "linux/amd64", "img"])
        #expect(ContainerRuntime.docker.pullArgv(image: "img", platform: nil) == nil)
    }
}

/// Writes `chunks` to stdout at `interval`, then stays silent for `silence`
/// before finishing, like a build that prints and then hangs.
final class ChattyCommandRunner: CommandRunning, @unchecked Sendable {
    let chunks: Int
    let interval: Duration
    let silence: Duration
    let failWith: String?

    init(chunks: Int, interval: Duration, silence: Duration = .zero, failWith: String? = nil) {
        self.chunks = chunks
        self.interval = interval
        self.silence = silence
        self.failWith = failWith
    }

    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        let (chunks, interval, silence, failWith) = (chunks, interval, silence, failWith)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for i in 0..<chunks {
                        continuation.yield(.standardOutput(Array("line \(i)\n".utf8)))
                        try await Task.sleep(for: interval)
                    }
                    try await Task.sleep(for: silence)
                    if let failWith {
                        continuation.yield(.standardError(Array("\(failWith)\n".utf8)))
                        continuation.finish(throwing: CommandError.terminated(125, stderr: failWith, command: arguments))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite("LogStreamer stall watchdog")
struct LogStreamerStallTests {
    private static func tmpLog() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-stall-\(UUID().uuidString).log")
    }

    @Test("a process that goes quiet fails as stalled and gets killed")
    func stalls() async {
        let streamer = LogStreamer(commandRunner: ChattyCommandRunner(
            chunks: 2, interval: .milliseconds(20), silence: .seconds(30)
        ))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let killed = Locked(false)
        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log,
            stallSeconds: 0.3,
            onTimeout: { await killed.set(true) }
        )
        guard case .failure(let message, let duration) = result else {
            Issue.record("expected a stall failure, got \(result)")
            return
        }
        #expect(message.contains("stalled"))
        #expect(message.contains("container killed"))
        #expect(duration < 10)
        #expect(await killed.value)
        let contents = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        #expect(contents.contains("line 1"))
        #expect(contents.contains("stalled"))
    }

    @Test("steady output keeps a long run alive past the stall window")
    func steadyOutputIsNotAStall() async {
        let streamer = LogStreamer(commandRunner: ChattyCommandRunner(
            chunks: 12, interval: .milliseconds(50)
        ))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log,
            timeoutSeconds: 10,
            stallSeconds: 0.3,
            onTimeout: { Issue.record("watchdog fired on a healthy run") }
        )
        if case .success = result { /* ok */ } else {
            Issue.record("expected .success, got \(result)")
        }
    }

    @Test("a stall limit of 0 is off")
    func zeroDisables() async {
        let streamer = LogStreamer(commandRunner: ChattyCommandRunner(
            chunks: 1, interval: .milliseconds(10), silence: .milliseconds(200)
        ))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log,
            stallSeconds: 0,
            onTimeout: { Issue.record("watchdog fired with the stall check off") }
        )
        if case .success = result { /* ok */ } else {
            Issue.record("expected .success, got \(result)")
        }
    }

    @Test("a runtime out of disk is reported as that, not a bare exit code")
    func diskFull() async {
        let streamer = LogStreamer(commandRunner: ChattyCommandRunner(
            chunks: 1, interval: .milliseconds(10),
            failWith: "docker: failed to extract layer: write /var/lib/x: no space left on device"
        ))
        let log = Self.tmpLog()
        defer { try? FileManager.default.removeItem(at: log) }

        let result = await streamer.run(
            arguments: ["fake"],
            environment: [:],
            workingDirectory: nil,
            logPath: log
        )
        guard case .failure(let message, _) = result else {
            Issue.record("expected .failure, got \(result)")
            return
        }
        #expect(message.contains("ran out of disk space"))
    }
}

@Suite("RunCommand Linux mode and limits")
struct RunCommandLinuxModeTests {
    @Test("the flag wins over config, config over the native default")
    func precedence() throws {
        #expect(try RunCommand.parseLinuxMode(cli: nil, config: nil) == .native)
        #expect(try RunCommand.parseLinuxMode(cli: nil, config: .spi) == .spi)
        #expect(try RunCommand.parseLinuxMode(cli: "native", config: .spi) == .native)
        #expect(throws: (any Error).self) {
            try RunCommand.parseLinuxMode(cli: "qemu", config: nil)
        }
    }

    @Test("limits line shows minutes and the off state")
    func limitsLine() {
        #expect(RunCommand.limitsLine(timeout: 3600, stall: 900)
                .hasPrefix("60 min per cell, fail after 15 min without output"))
        #expect(RunCommand.limitsLine(timeout: 0, stall: 90)
                .hasPrefix("no time limit, fail after 90s without output"))
    }

    @Test("config reads linux_mode and stall_timeout")
    func configKeys() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-config-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
            linux_mode = "spi"
            stall_timeout = 600
            """.write(to: url, atomically: true, encoding: .utf8)
        let config = try await SPCCConfig.load(from: url)
        #expect(config.linuxMode == .spi)
        #expect(config.stallSeconds == 600)
    }
}
