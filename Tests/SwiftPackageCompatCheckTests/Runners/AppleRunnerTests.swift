import Command
import Foundation
import Path
import Testing
@testable import SwiftPackageCompatCheck

/// Records argv passed to `run(arguments:environment:workingDirectory:)` and emits an
/// empty success stream so the runner reports `.pass`. No real subprocess is launched.
final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Sendable {
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String?
    }

    private(set) var calls: [Call] = []
    var failOnNext: Error?

    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        calls.append(.init(
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory?.pathString
        ))
        let failure = failOnNext
        failOnNext = nil
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.finish()
            }
        }
    }
}

@Suite("AppleRunner")
struct AppleRunnerTests {
    private static func makeContext(scheme: String = "Pkg") -> (RunContext, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-test-\(UUID().uuidString)", isDirectory: true)
        let cache = CachePaths(
            root: tmp,
            packageBasename: "pkg",
            runTimestamp: "20260606T120000"
        )
        try? cache.createDirectories()
        return (
            RunContext(
                packagePath: URL(fileURLWithPath: "/private/tmp/pkg"),
                scheme: scheme,
                cache: cache,
                options: RunOptions()
            ),
            tmp
        )
    }

    @Test("Returns .pending for non-Apple platforms instead of attempting to run")
    func nonApplePlatforms() async {
        let recorder = RecordingCommandRunner()
        let runner = AppleRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()
        let outcome = await runner.run(
            pair: BuildPair(platform: .linux, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .pending)
        #expect(recorder.calls.isEmpty)
    }

    @Test("macos-spm dispatches `xcrun swift build --arch arm64`")
    func macosSPMDispatch() async {
        let recorder = RecordingCommandRunner()
        let runner = AppleRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()
        let outcome = await runner.run(
            pair: BuildPair(platform: .macosSPM, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .pass)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0].arguments == ["xcrun", "swift", "build", "--arch", "arm64"])
    }

    @Test("ios dispatches xcrun xcodebuild with the cell's derived-data path")
    func iosDispatch() async {
        let recorder = RecordingCommandRunner()
        let runner = AppleRunner(commandRunner: recorder)
        let (context, tmp) = Self.makeContext(scheme: "SwiftNaCl")
        let pair = BuildPair(platform: .ios, swiftVersion: .v6_3)

        let outcome = await runner.run(pair: pair, context: context)
        #expect(outcome.state == .pass)
        #expect(recorder.calls.count == 1)

        let argv = recorder.calls[0].arguments
        #expect(argv.first == "xcrun")
        #expect(argv.contains("xcodebuild"))
        #expect(argv.contains("-scheme"))
        #expect(argv.contains("SwiftNaCl"))
        #expect(argv.contains("-destination"))
        #expect(argv.contains("generic/platform=iOS"))
        let derivedDataPath = tmp.appendingPathComponent("derived-data/pkg/ios-6.3").path
        #expect(argv.contains(derivedDataPath))
        #expect(argv.contains("-IDEClonedSourcePackagesDirPathOverride=\(tmp.appendingPathComponent("cloned-packages/pkg").path)"))
    }

    @Test("--xcode-X.Y sets DEVELOPER_DIR for the cell's Swift version only")
    func developerDirOverride() async {
        let recorder = RecordingCommandRunner()
        let runner = AppleRunner(commandRunner: recorder)
        var (context, _) = Self.makeContext()
        context = RunContext(
            packagePath: context.packagePath,
            scheme: context.scheme,
            cache: context.cache,
            options: RunOptions(
                xcodeForVersion: [.v6_3: URL(fileURLWithPath: "/Applications/Xcode-26.4.app")]
            )
        )

        _ = await runner.run(
            pair: BuildPair(platform: .ios, swiftVersion: .v6_3),
            context: context
        )
        _ = await runner.run(
            pair: BuildPair(platform: .ios, swiftVersion: .v6_2),
            context: context
        )

        #expect(recorder.calls.count == 2)
        #expect(recorder.calls[0].environment["DEVELOPER_DIR"]
                == "/Applications/Xcode-26.4.app/Contents/Developer")
        #expect(recorder.calls[1].environment["DEVELOPER_DIR"] == nil)
    }

    @Test("Non-zero subprocess exit produces .fail and the log file captures the error")
    func failureCapturesLog() async throws {
        let recorder = RecordingCommandRunner()
        recorder.failOnNext = CommandError.terminated(2, stderr: "boom", command: ["xcrun"])
        let runner = AppleRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()
        let outcome = await runner.run(
            pair: BuildPair(platform: .macosSPM, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .fail)
        let logPath = try #require(outcome.logPath)
        let contents = try String(contentsOf: logPath, encoding: .utf8)
        #expect(contents.contains("spcc:"))
    }
}

@Suite("MatrixDispatcher")
struct MatrixDispatcherTests {
    @Test("Reports .skipped for SPI-unsupported pairs without launching a subprocess")
    func skipsUnsupportedPairs() async {
        let recorder = RecordingCommandRunner()
        let dispatcher = MatrixDispatcher(commandRunner: recorder)
        let outcome = await dispatcher.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_0),
            context: RunContext(
                packagePath: URL(fileURLWithPath: "/tmp/pkg"),
                scheme: "Pkg",
                cache: CachePaths(root: URL(fileURLWithPath: "/tmp/spi"), packageBasename: "pkg", runTimestamp: "X"),
                options: RunOptions()
            )
        )
        #expect(outcome.state == .skipped)
        #expect(recorder.calls.isEmpty)
    }
}
