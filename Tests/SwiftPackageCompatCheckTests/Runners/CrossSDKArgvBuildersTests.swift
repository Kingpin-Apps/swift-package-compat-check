import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("CrossSDKArgvBuilders")
struct CrossSDKArgvBuildersTests {
    @Test("Volume name keeps android and wasm in separate per-(pkg, sv) volumes")
    func volumeIsolation() {
        let android = CrossSDKArgvBuilders.volumeName(
            packageBasename: "swift-nacl",
            platform: .android,
            swiftVersion: .v6_3
        )
        let wasm = CrossSDKArgvBuilders.volumeName(
            packageBasename: "swift-nacl",
            platform: .wasm,
            swiftVersion: .v6_3
        )
        #expect(android == "spi-compat-build-swift-nacl-android-6.3")
        #expect(wasm == "spi-compat-build-swift-nacl-wasm-6.3")
        #expect(android != wasm)
    }

    @Test("android argv passes SDK_BUILD_ARG=aarch64-unknown-linux-android28")
    func androidEnvVars() {
        let argv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/Users/me/swift-nacl"),
            packageBasename: "swift-nacl",
            swiftVersion: .v6_3,
            image: "registry.gitlab.com/swiftpackageindex/spi-images:android-6.3-latest",
            pullPolicy: .missing
        )
        #expect(argv.contains("SDK_BUILD_ARG=aarch64-unknown-linux-android28"))
        #expect(argv.contains("SDK_MATCH=android"))
        #expect(argv.contains("SDK_FALLBACK_URL="))  // empty for android
        #expect(argv.contains("registry.gitlab.com/swiftpackageindex/spi-images:android-6.3-latest"))
        #expect(argv.contains("spi-compat-build-swift-nacl-android-6.3:/build"))
    }

    @Test("wasm argv passes the SPI-style SDK_BUILD_ARG and the wasi regex")
    func wasmEnvVars() {
        let argv = CrossSDKArgvBuilders.wasm(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "pkg",
            swiftVersion: .v6_3,
            image: "registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest",
            pullPolicy: .always,
            fallbackURL: "https://example.com/sdk.zip"
        )
        #expect(argv.contains("SDK_BUILD_ARG=swift-6.3-RELEASE_wasm"))
        #expect(argv.contains("SDK_MATCH=wasi$|wasip1$|_wasm$"))
        #expect(argv.contains("SDK_FALLBACK_URL=https://example.com/sdk.zip"))
        #expect(argv.contains("--pull=always"))
    }

    @Test("--test flag propagates SDK_ACTION=test to the container env")
    func sdkActionDefault() {
        let buildArgv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing
        )
        let testArgv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: true
        )
        #expect(buildArgv.contains("SDK_ACTION=build"))
        #expect(testArgv.contains("SDK_ACTION=test"))
    }

    @Test("Resolver script tries SPI-style fast path before falling back")
    func resolverScriptShape() {
        let script = CrossSDKArgvBuilders.resolverScript
        // Fast path runs through build_with_retry (retries on transient errors).
        #expect(script.contains("build_with_retry \"$SDK_BUILD_ARG\""))
        // Dynamic resolver fallback hooks.
        #expect(script.contains("swift sdk list"))
        #expect(script.contains("pick_matching_sdk"))
        // Fallback download path is wired up.
        #expect(script.contains("SDK_FALLBACK_URL"))
        #expect(script.contains("swift sdk install"))
    }

    @Test("Resolver retries on qemu IPC corruption (the swift-cardano-cips hang fingerprint)")
    func resolverRetriesOnTransientErrors() {
        let script = CrossSDKArgvBuilders.resolverScript
        // Default retry budget; configurable via SPCC_RETRY_MAX.
        #expect(script.contains("SPCC_RETRY_MAX"))
        // try_build greps for the exact transient-error fingerprints.
        #expect(script.contains("failed parsing the Swift compiler output"))
        #expect(script.contains("unexpected JSON message"))
        // Distinct exit codes: 0 success, 1 permanent, 2 transient.
        #expect(script.contains("Detected transient IPC error"))
    }

    @Test("runtime=.container: android argv swaps binary, drops --pull, adds --name; resolver body unchanged")
    func androidContainerRuntime() {
        let argv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "swift-nacl",
            swiftVersion: .v6_3,
            image: "registry.gitlab.com/swiftpackageindex/spi-images:android-6.3-latest",
            pullPolicy: .missing,
            cellLabel: "20260607T120000-android-6.3",
            runtime: .container
        )
        #expect(argv.first == "container")
        #expect(!argv.contains { $0.hasPrefix("--pull=") })
        #expect(argv.contains("--name"))
        #expect(argv.contains("spcc-cell-20260607T120000-android-6.3"))
        // The bash resolver tail is unchanged — runs inside the container.
        #expect(argv.last == CrossSDKArgvBuilders.resolverScript)
        // Cross-SDK env vars still threaded through.
        #expect(argv.contains("SDK_BUILD_ARG=aarch64-unknown-linux-android28"))
    }

    @Test("runtime=.container: wasm argv preserves SDK fallback URL plumbing")
    func wasmContainerRuntime() {
        let argv = CrossSDKArgvBuilders.wasm(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            fallbackURL: "https://example.com/sdk.zip",
            cellLabel: "20260607T120000-wasm-6.3",
            runtime: .container
        )
        #expect(argv.first == "container")
        #expect(argv.contains("SDK_FALLBACK_URL=https://example.com/sdk.zip"))
        #expect(argv.contains("--name"))
    }

    @Test("Resolver extracts a specific triple from a multi-arch bundle")
    func resolverExtractsBundleTriple() {
        let script = CrossSDKArgvBuilders.resolverScript
        #expect(script.contains("extract_bundle_triple"))
        // Looks up the bundle's swift-sdk.json (where targetTriples live).
        #expect(script.contains("swift-sdks/${sdk_id}.artifactbundle"))
        #expect(script.contains("swift-sdk.json"))
        #expect(script.contains("targetTriples"))
        // Picks the highest API level <= the hint's (closest to SPI's intent).
        #expect(script.contains("hint_api"))
        // Logs the resolution so the user sees the bundle → triple flip.
        #expect(script.contains("avoiding multi-arch build"))
    }
}

@Suite("Platform.defaultWasmSDKURL")
struct DefaultWasmSDKURLTests {
    @Test("Returns nil for 6.0 (SPI doesn't build wasm there) and the swiftwasm URL otherwise")
    func defaults() {
        #expect(Platform.wasm.defaultWasmSDKURL(for: .v6_0) == nil)
        #expect(Platform.wasm.defaultWasmSDKURL(for: .v6_1)?.contains("swift-wasm-6.1-RELEASE") == true)
        #expect(Platform.wasm.defaultWasmSDKURL(for: .v6_2)?.contains("wasip1") == true)
        #expect(Platform.wasm.defaultWasmSDKURL(for: .v6_3)?.contains("wasip1") == true)
        // Non-wasm platforms: nil.
        #expect(Platform.android.defaultWasmSDKURL(for: .v6_3) == nil)
        #expect(Platform.linux.defaultWasmSDKURL(for: .v6_3) == nil)
    }
}
