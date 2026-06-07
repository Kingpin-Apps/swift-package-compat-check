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
}

@Suite("SwiftVersion")
struct SwiftVersionTests {
    @Test("rawValue matches X.Y formatting")
    func rawValueFormat() {
        #expect(SwiftVersion.allCases.map(\.rawValue) == ["6.0", "6.1", "6.2", "6.3"])
    }
}
