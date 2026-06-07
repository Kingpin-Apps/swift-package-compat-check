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
        switch self {
        case .macosXcodebuild: "platform=macOS,arch=arm64"
        case .ios: "generic/platform=iOS"
        case .tvos: "generic/platform=tvOS"
        case .watchos: "generic/platform=watchOS"
        case .visionos: "generic/platform=xrOS"
        case .macosSPM, .linux, .wasm, .android: nil
        }
    }
}
