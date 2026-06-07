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

    @Test("xcodebuildDestination uses xrOS for visionos")
    func visionOSDestinationName() {
        #expect(Platform.visionos.xcodebuildDestination == "xrOS")
        #expect(Platform.ios.xcodebuildDestination == "iOS")
        #expect(Platform.watchos.xcodebuildDestination == "watchOS")
        #expect(Platform.linux.xcodebuildDestination == nil)
    }
}

@Suite("SwiftVersion")
struct SwiftVersionTests {
    @Test("rawValue matches X.Y formatting")
    func rawValueFormat() {
        #expect(SwiftVersion.allCases.map(\.rawValue) == ["6.0", "6.1", "6.2", "6.3"])
    }
}
