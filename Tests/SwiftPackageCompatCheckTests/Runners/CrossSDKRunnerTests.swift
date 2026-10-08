import Command
import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("CrossSDKRunner")
struct CrossSDKRunnerTests {
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

    @Test("Returns .pending for non-android/wasm platforms without launching docker")
    func nonCrossSDKPlatforms() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()
        let outcome = await runner.run(
            pair: BuildPair(platform: .linux, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .pending)
        #expect(recorder.calls.isEmpty)
    }

    @Test("android@6.0 short-circuits to .skipped (SPI's BuildPair.all rule)")
    func androidSixZeroSkipped() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext()
        let outcome = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_0),
            context: context
        )
        #expect(outcome.state == .skipped)
        #expect(recorder.calls.isEmpty)
    }

    @Test("--linux-mode spi: android dispatches docker with the SPI android image")
    func androidDispatch() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(
            packageBasename: "swift-nacl", options: RunOptions(linuxMode: .spi)
        )

        let outcome = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .pass)
        let argv = recorder.calls[0].arguments
        #expect(argv.first == "docker")
        #expect(argv.contains("registry.gitlab.com/swiftpackageindex/spi-images:android-6.3-latest"))
        #expect(argv.contains("SDK_BUILD_ARG=aarch64-unknown-linux-android28"))
        #expect(argv.contains("spi-compat-build-swift-nacl-android-6.3:/build"))
    }

    @Test("--linux-mode spi: wasm dispatches with the SPI wasm image + default fallback URL")
    func wasmDispatchUsesDefaults() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(options: RunOptions(linuxMode: .spi))

        _ = await runner.run(
            pair: BuildPair(platform: .wasm, swiftVersion: .v6_3),
            context: context
        )
        let argv = recorder.calls[0].arguments
        #expect(argv.contains("registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest"))
        #expect(argv.contains("SDK_BUILD_ARG=swift-6.3-RELEASE_wasm"))
        // Default wasm fallback URL is wired in even when the user didn't override.
        #expect(argv.contains { $0.hasPrefix("SDK_FALLBACK_URL=https://github.com/swiftwasm") })
    }

    @Test("--linux-mode spi: --android-image-X.Y / --wasm-image-X.Y overrides are scoped to their version")
    func imageOverridesScoped() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(
            options: RunOptions(
                androidImageForVersion: [.v6_3: "my-android-image"],
                wasmImageForVersion: [.v6_2: "my-wasm-image"],
                linuxMode: .spi
            )
        )

        _ = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_3),
            context: context
        )
        _ = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_2),
            context: context
        )
        _ = await runner.run(
            pair: BuildPair(platform: .wasm, swiftVersion: .v6_2),
            context: context
        )

        #expect(recorder.calls[0].arguments.contains("my-android-image"))
        #expect(recorder.calls[1].arguments.contains(
            "registry.gitlab.com/swiftpackageindex/spi-images:android-6.2-latest"
        ))
        #expect(recorder.calls[2].arguments.contains("my-wasm-image"))
    }

    @Test("--linux-mode spi: --wasm-sdk-url-X.Y override beats the default swiftwasm URL")
    func wasmSDKURLOverride() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(
            options: RunOptions(
                wasmSDKURLForVersion: [.v6_3: "https://internal.example/sdk.zip"],
                linuxMode: .spi
            )
        )

        _ = await runner.run(
            pair: BuildPair(platform: .wasm, swiftVersion: .v6_3),
            context: context
        )
        #expect(recorder.calls[0].arguments.contains(
            "SDK_FALLBACK_URL=https://internal.example/sdk.zip"
        ))
    }

    @Test("--linux-mode spi, runtime=.container: android dispatches `container run` with --name, no --pull")
    func androidContainerRuntime() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(
            options: RunOptions(linuxMode: .spi, containerRuntime: .container)
        )
        _ = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_3),
            context: context
        )
        let argv = recorder.calls[0].arguments
        #expect(argv.first == "container")
        #expect(!argv.contains { $0.hasPrefix("--pull=") })
        #expect(argv.contains("--name"))
        #expect(argv.contains("spcc-cell-20260606T120000-android-6.3"))
        #expect(argv.contains("SDK_BUILD_ARG=aarch64-unknown-linux-android28"))
    }
    @Test("native (default): android runs the pinned official image with its SDK, at the host's architecture")
    func nativeAndroidDispatch() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(packageBasename: "swift-nacl")

        let outcome = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_3),
            context: context
        )
        #expect(outcome.state == .pass)
        let argv = recorder.calls[0].arguments
        let sdk = NativeCrossSDK.entry(for: .android, swiftVersion: .v6_3)!
        #expect(argv.contains(sdk.image))
        #expect(!argv.contains("--platform"))
        #expect(!argv.contains { $0.contains("swiftpackageindex/spi-images") })
        #expect(argv.contains("SDK_SELECTOR=aarch64-unknown-linux-android28"))
        #expect(argv.contains("spi-compat-build-swift-nacl-android-6.3-native:/build"))
        #expect(argv.contains("spi-compat-sdk-cache:/sdk-cache"))
    }

    @Test("native: an --android-image-X.Y override still replaces the pinned image")
    func nativeImageOverride() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(commandRunner: recorder)
        let (context, _) = Self.makeContext(
            options: RunOptions(androidImageForVersion: [.v6_3: "my-android-image"])
        )
        _ = await runner.run(
            pair: BuildPair(platform: .android, swiftVersion: .v6_3),
            context: context
        )
        let argv = recorder.calls[0].arguments
        #expect(argv.contains("my-android-image"))
        #expect(argv.contains { $0.hasPrefix("SDK_URL=https://download.swift.org/") })
    }

    @Test("native on apple/container pre-pulls at the host's architecture, not linux/amd64")
    func nativeContainerPull() async {
        let recorder = RecordingCommandRunner()
        let runner = CrossSDKRunner(
            commandRunner: recorder,
            pullCoordinator: ImagePullCoordinator(runtime: .container, runner: recorder)
        )
        let (context, _) = Self.makeContext(options: RunOptions(containerRuntime: .container))
        _ = await runner.run(
            pair: BuildPair(platform: .wasm, swiftVersion: .v6_4),
            context: context
        )
        let pull = recorder.calls[0].arguments
        #expect(pull == ["container", "image", "pull", "swift:6.4.0-jammy"])
        #expect(!recorder.calls[1].arguments.contains("--platform"))
    }
}
