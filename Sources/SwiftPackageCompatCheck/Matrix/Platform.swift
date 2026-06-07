public enum Platform: String, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case ios
    case macosSPM = "macos-spm"
    case macosXcodebuild = "macos-xcodebuild"
    case visionos
    case tvos
    case watchos
    case linux
    case wasm
    case android

    public var description: String { rawValue }

    /// The full `-destination` argument string that SPI passes to `xcodebuild` for
    /// this platform. macOS uses the non-generic form `platform=macOS,arch=arm64`;
    /// every other Apple platform uses `generic/platform=<SDK>`. visionOS's SDK is
    /// `xrOS`, not `visionOS` (SPI's terminology gotcha, preserved verbatim).
    /// Returns `nil` for platforms that aren't built via xcodebuild.
    public var xcodebuildDestination: String? {
        xcodebuildDestination(runningTests: false)
    }

    /// Same as ``xcodebuildDestination``, but when `runningTests` is `true`
    /// returns a destination compatible with `xcodebuild test`. iOS/tvOS/watchOS/
    /// visionOS need to target a Simulator SDK rather than the device SDK,
    /// otherwise `xcodebuild test` errors with `requires destination: a device`.
    /// macOS stays the same (the macOS destination is test-compatible already).
    public func xcodebuildDestination(runningTests: Bool) -> String? {
        switch self {
        case .macosXcodebuild: return "platform=macOS,arch=arm64"
        case .ios: return runningTests ? "generic/platform=iOS Simulator" : "generic/platform=iOS"
        case .tvos: return runningTests ? "generic/platform=tvOS Simulator" : "generic/platform=tvOS"
        case .watchos: return runningTests ? "generic/platform=watchOS Simulator" : "generic/platform=watchOS"
        case .visionos: return runningTests ? "generic/platform=xrOS Simulator" : "generic/platform=xrOS"
        case .macosSPM, .linux, .wasm, .android: return nil
        }
    }
}
