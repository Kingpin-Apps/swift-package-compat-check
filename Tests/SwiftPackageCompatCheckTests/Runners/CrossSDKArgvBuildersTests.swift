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
            pullPolicy: "missing"
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
            pullPolicy: "always",
            fallbackURL: "https://example.com/sdk.zip"
        )
        #expect(argv.contains("SDK_BUILD_ARG=swift-6.3-RELEASE_wasm"))
        #expect(argv.contains("SDK_MATCH=wasi$|wasip1$|_wasm$"))
        #expect(argv.contains("SDK_FALLBACK_URL=https://example.com/sdk.zip"))
        #expect(argv.contains("--pull=always"))
    }

    @Test("Resolver script tries SPI-style fast path before falling back")
    func resolverScriptShape() {
        let script = CrossSDKArgvBuilders.resolverScript
        // Fast path: the verbatim SPI build command.
        #expect(script.contains("swift build --swift-sdk \"$SDK_BUILD_ARG\""))
        // Dynamic resolver fallback hooks.
        #expect(script.contains("swift sdk list"))
        #expect(script.contains("pick_matching_sdk"))
        // Fallback download path is wired up.
        #expect(script.contains("SDK_FALLBACK_URL"))
        #expect(script.contains("swift sdk install"))
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
