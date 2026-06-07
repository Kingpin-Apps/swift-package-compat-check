import Command
import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("LinuxRunner")
struct LinuxRunnerTests {
    private static func makeContext(
        packageBasename: String = "pkg",
        options: RunOptions = RunOptions()
    ) -> (RunContext, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-test-\(UUID().uuidString)", isDirectory: true)
        let cache = CachePaths(
            root: tmp,
            packageBasename: packageBasename,
            runTimestamp: "20260606T120000"
        )
        try? cache.createDirectories()
        return (
            RunContext(
                packagePath: URL(fileURLWithPath: "/private/tmp/\(packageBasename)"),
                scheme: "Pkg",
                cache: cache,
                options: options
            ),
            tmp
        )
    }

    @Test("Returns .pending for non-Linux platforms without launching docker")
    func nonLinuxPlatforms() async {
        let recorder = RecordingCommandRunner()
        let runner = LinuxRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()
        let outcome = await runner.run(
            pair: BuildPair(platform: .ios, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .pending)
        #expect(recorder.calls.isEmpty)
    }

    @Test("linux dispatches `docker run ... swift build --triple x86_64-unknown-linux-gnu`")
    func linuxDispatch() async {
        let recorder = RecordingCommandRunner()
        let runner = LinuxRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(packageBasename: "swift-nacl")
        let pair = BuildPair(platform: .linux, swiftVersion: .v6_3)

        let outcome = await runner.run(pair: pair, context: context)
        #expect(outcome.state == .pass)
        #expect(recorder.calls.count == 1)

        let argv = recorder.calls[0].arguments
        #expect(argv.first == "docker")
        #expect(argv.contains("--platform"))
        #expect(argv.contains("linux/amd64"))
        #expect(argv.contains("spi-compat-build-swift-nacl-6.3:/build"))
        #expect(argv.contains("registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest"))
        #expect(argv.contains("--pull=missing"))
        #expect(argv.last?.contains("--triple x86_64-unknown-linux-gnu --scratch-path /build") == true)
    }

    @Test("--pull-always flips the docker pull policy")
    func pullAlwaysFlag() async {
        let recorder = RecordingCommandRunner()
        let runner = LinuxRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(options: RunOptions(pullAlways: true))
        _ = await runner.run(
            pair: BuildPair(platform: .linux, swiftVersion: .v6_3),
            context: context
        )
        #expect(recorder.calls[0].arguments.contains("--pull=always"))
        #expect(!recorder.calls[0].arguments.contains("--pull=missing"))
    }

    @Test("--linux-image-X.Y overrides the default SPI image for that version only")
    func imageOverrideIsScopedToVersion() async {
        let recorder = RecordingCommandRunner()
        let runner = LinuxRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(
            options: RunOptions(
                linuxImageForVersion: [.v6_3: "my-custom-image:tag"]
            )
        )
        _ = await runner.run(
            pair: BuildPair(platform: .linux, swiftVersion: .v6_3),
            context: context
        )
        _ = await runner.run(
            pair: BuildPair(platform: .linux, swiftVersion: .v6_2),
            context: context
        )

        #expect(recorder.calls[0].arguments.contains("my-custom-image:tag"))
        #expect(recorder.calls[1].arguments.contains(
            "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.2-latest"
        ))
    }

    @Test("Non-zero docker exit produces .fail and the log captures the error")
    func failureCapturesLog() async throws {
        let recorder = RecordingCommandRunner()
        recorder.failOnNext = CommandError.terminated(125, stderr: "docker: not found", command: ["docker"])
        let runner = LinuxRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()

        let outcome = await runner.run(
            pair: BuildPair(platform: .linux, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .fail)
        let logPath = try #require(outcome.logPath)
        let contents = try String(contentsOf: logPath, encoding: .utf8)
        #expect(contents.contains("spcc:"))
    }
}
