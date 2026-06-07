import Testing
import SwiftPackageCompatCheck

@Suite("Platform")
struct PlatformTests {
    @Test("rawValue strings match the bash script's accepted inputs")
    func rawValueParity() {
        // Order matches the bash script's `PLATFORMS` default.
        let expected = [
            "ios", "macos-spm", "macos-xcodebuild", "visionos",
            "tvos", "watchos", "linux", "wasm", "android",
        ]
        #expect(Platform.allCases.map(\.rawValue) == expected)
    }

    @Test("xcodebuildDestination matches SPI's verbatim -destination strings")
    func destinationStringParity() {
        #expect(Platform.macosXcodebuild.xcodebuildDestination == "platform=macOS,arch=arm64")
        #expect(Platform.ios.xcodebuildDestination == "generic/platform=iOS")
        #expect(Platform.tvos.xcodebuildDestination == "generic/platform=tvOS")
        #expect(Platform.watchos.xcodebuildDestination == "generic/platform=watchOS")
        #expect(Platform.visionos.xcodebuildDestination == "generic/platform=xrOS")
        #expect(Platform.macosSPM.xcodebuildDestination == nil)
        #expect(Platform.linux.xcodebuildDestination == nil)
        #expect(Platform.wasm.xcodebuildDestination == nil)
        #expect(Platform.android.xcodebuildDestination == nil)
    }

    @Test("xcodebuildDestination(runningTests:) swaps non-macOS Apple platforms to Simulator")
    func destinationStringForTests() {
        // macOS is test-compatible without changes.
        #expect(Platform.macosXcodebuild.xcodebuildDestination(runningTests: true) == "platform=macOS,arch=arm64")
        // Non-macOS Apple platforms shift to Simulator SDKs.
        #expect(Platform.ios.xcodebuildDestination(runningTests: true) == "generic/platform=iOS Simulator")
        #expect(Platform.tvos.xcodebuildDestination(runningTests: true) == "generic/platform=tvOS Simulator")
        #expect(Platform.watchos.xcodebuildDestination(runningTests: true) == "generic/platform=watchOS Simulator")
        #expect(Platform.visionos.xcodebuildDestination(runningTests: true) == "generic/platform=xrOS Simulator")
        // Non-xcodebuild platforms still return nil.
        #expect(Platform.linux.xcodebuildDestination(runningTests: true) == nil)
        #expect(Platform.macosSPM.xcodebuildDestination(runningTests: true) == nil)
    }
}

@Suite("SwiftVersion")
struct SwiftVersionTests {
    @Test("rawValue matches X.Y formatting")
    func rawValueFormat() {
        #expect(SwiftVersion.allCases.map(\.rawValue) == ["6.0", "6.1", "6.2", "6.3"])
    }
}
