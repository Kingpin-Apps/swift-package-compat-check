import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("NativeCrossSDK")
struct NativeCrossSDKTests {
    @Test("every Android/Wasm pair SPI builds has a pinned native SDK; 6.0 and other platforms don't")
    func coverage() {
        for pair in BuildPair.all where [.android, .wasm].contains(pair.platform) {
            let entry = NativeCrossSDK.entry(for: pair.platform, swiftVersion: pair.swiftVersion)
            #expect((entry != nil) == pair.isSupportedBySPI, "\(pair)")
        }
        #expect(NativeCrossSDK.entry(for: .linux, swiftVersion: .v6_3) == nil)
        #expect(NativeCrossSDK.entry(for: .ios, swiftVersion: .v6_3) == nil)
    }

    @Test("entries pin an exact-patch official image and carry a SHA-256")
    func entryShape() {
        for platform in [Platform.android, .wasm] {
            for version in SwiftVersion.allCases {
                guard let entry = NativeCrossSDK.entry(for: platform, swiftVersion: version) else { continue }
                #expect(entry.image.hasPrefix("swift:\(version.rawValue)."), "\(entry.image)")
                #expect(entry.image.hasSuffix("-jammy"))
                #expect(entry.sdkURL.hasPrefix("https://"))
                #expect(entry.sdkSHA256.count == 64)
                let isHex = entry.sdkSHA256.allSatisfy { $0.isHexDigit }
                #expect(isHex)
                #expect((entry.ndk != nil) == (platform == .android))
            }
        }
    }

    @Test("official swift.org SDKs: Wasm from 6.2, Android from 6.3")
    func officialSDKs() {
        let wasm = NativeCrossSDK.entry(for: .wasm, swiftVersion: .v6_3)!
        #expect(wasm.image == "swift:6.3.3-jammy")
        #expect(wasm.sdkURL == "https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz")
        #expect(wasm.sdkID == "swift-6.3.3-RELEASE_wasm")
        #expect(wasm.sdkSelector == wasm.sdkID)

        let android = NativeCrossSDK.entry(for: .android, swiftVersion: .v6_4)!
        #expect(android.image == "swift:6.4.0-jammy")
        #expect(android.sdkID == "swift-6.4.0-RELEASE_android")
        #expect(android.sdkSelector == "aarch64-unknown-linux-android28")
        #expect(android.ndk == .r27d)

        #expect(NativeCrossSDK.entry(for: .wasm, swiftVersion: .v6_2)!.sdkURL.contains("download.swift.org"))
    }

    @Test("community bundles before the official SDKs, pinned to the compiler they were built with")
    func communitySDKs() {
        let android62 = NativeCrossSDK.entry(for: .android, swiftVersion: .v6_2)!
        #expect(android62.image == "swift:6.2.0-jammy")
        #expect(android62.sdkURL == "https://github.com/finagolfin/swift-android-sdk/releases/download/6.2/swift-6.2-RELEASE-android-24-0.1.artifactbundle.tar.gz")
        #expect(android62.sdkID == "swift-6.2-RELEASE-android-24-0.1")
        #expect(android62.sdkSelector == "aarch64-unknown-linux-android24")

        let android61 = NativeCrossSDK.entry(for: .android, swiftVersion: .v6_1)!
        #expect(android61.image == "swift:6.1.3-jammy")
        #expect(android61.sdkID == "swift-6.1.3-RELEASE-android-24-0.1")

        let wasm61 = NativeCrossSDK.entry(for: .wasm, swiftVersion: .v6_1)!
        #expect(wasm61.image == "swift:6.1.3-jammy")
        #expect(wasm61.sdkURL.contains("github.com/swiftwasm/swift/releases"))
    }
}

@Suite("CrossSDKArgvBuilders native mode")
struct NativeCrossSDKArgvTests {
    private static func argv(
        platform: Platform = .android,
        version: SwiftVersion = .v6_3,
        runtime: ContainerRuntime = .docker,
        runTests: Bool = false,
        noParallel: Bool = false
    ) -> [String] {
        let sdk = NativeCrossSDK.entry(for: platform, swiftVersion: version)!
        return CrossSDKArgvBuilders.native(
            packagePath: URL(fileURLWithPath: "/Users/me/swift-nacl"),
            packageBasename: "swift-nacl",
            platform: platform,
            swiftVersion: version,
            image: sdk.image,
            sdk: sdk,
            pullPolicy: .missing,
            cellLabel: "c",
            runTests: runTests,
            runtime: runtime,
            noParallel: noParallel
        )
    }

    @Test("no amd64 platform; native build volume plus the shared SDK cache")
    func shape() {
        let argv = Self.argv()
        #expect(argv.prefix(4) == ["docker", "run", "--pull=missing", "--rm"])
        #expect(!argv.contains("--platform"))
        #expect(argv.contains("spi-compat-build-swift-nacl-android-6.3-native:/build"))
        #expect(argv.contains("spi-compat-sdk-cache:/sdk-cache"))
        #expect(argv.contains("SPI_BUILD=1"))
        #expect(!argv.contains { $0.hasPrefix("JAVA_HOME=") })
        #expect(argv.contains("swift:6.3.3-jammy"))
        #expect(argv.contains("SDK_ACTION=build"))
    }

    @Test("Android passes the NDK; Wasm passes none")
    func ndkEnvironment() {
        let android = Self.argv(platform: .android)
        #expect(android.contains("NDK_DIR=android-ndk-r27d"))
        #expect(android.contains("NDK_URL=\(AndroidNDK.r27d.url)"))
        #expect(android.contains("NDK_SHA256=\(AndroidNDK.r27d.sha256)"))

        let wasm = Self.argv(platform: .wasm)
        #expect(wasm.contains("NDK_DIR="))
        #expect(wasm.contains("SDK_SELECTOR=swift-6.3.3-RELEASE_wasm"))
    }

    @Test("test mode runs swift test with --no-parallel when asked")
    func testMode() {
        let argv = Self.argv(runTests: true, noParallel: true)
        #expect(argv.contains("SDK_ACTION=test"))
        #expect(argv.contains("SDK_TEST_ARGS=--no-parallel"))
    }

    @Test("apple/container: no --platform, no --rosetta, named for the kill path")
    func containerRuntime() {
        let argv = Self.argv(runtime: .container)
        #expect(argv.first == "container")
        #expect(!argv.contains("--platform"))
        #expect(!argv.contains("--rosetta"))
        #expect(argv.contains("--name"))
    }

    @Test("the resolver verifies checksums, locks the cache, and keeps SDKs per compiler")
    func resolverScript() {
        let script = Self.argv().last ?? ""
        #expect(script.contains("sha256sum -c"))
        #expect(script.contains("flock 9"))
        #expect(script.contains(#"sdks="$cache/swift-sdks/$compiler_v""#))
        #expect(script.contains(#"export ANDROID_NDK_HOME="$cache/$NDK_DIR""#))
        #expect(script.contains(#"--swift-sdks-path "$sdks" --swift-sdk "$SDK_SELECTOR" --scratch-path /build"#))
    }

    @Test("SPI-mode volume names are unchanged; native ones get -native")
    func volumeNames() {
        #expect(CrossSDKArgvBuilders.volumeName(packageBasename: "p", platform: .wasm, swiftVersion: .v6_2)
                == "spi-compat-build-p-wasm-6.2")
        #expect(CrossSDKArgvBuilders.volumeName(packageBasename: "p", platform: .wasm, swiftVersion: .v6_2, mode: .native)
                == "spi-compat-build-p-wasm-6.2-native")
    }
}

@Suite("LogStreamer diagnosis")
struct RegistryDiagnosisTests {
    @Test("a refused pull of SPI's images points at --linux-mode native")
    func spiRegistryRefused() throws {
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-diag-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try Data("""
            Unable to find image 'registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest' locally
            docker: Error response from daemon: error from registry: access forbidden
            """.utf8).write(to: log)
        let message = try #require(LogStreamer.diagnosis(logPath: log))
        #expect(message.contains("--linux-mode native"))
    }

    @Test("an unrelated access-denied line isn't blamed on SPI's registry")
    func unrelatedDenied() throws {
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-diag-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try Data("error: permission denied opening /host/Package.swift\n".utf8).write(to: log)
        #expect(LogStreamer.diagnosis(logPath: log) == nil)
    }
}
