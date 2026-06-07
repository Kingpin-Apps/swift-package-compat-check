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

    /// SPI's xcodebuild destination uses "xrOS" for visionOS — keep the user-facing
    /// rawValue as `visionos` but emit `xrOS` when constructing the build command.
    public var xcodebuildDestination: String? {
        switch self {
        case .ios: "iOS"
        case .tvos: "tvOS"
        case .watchos: "watchOS"
        case .visionos: "xrOS"
        case .macosXcodebuild: "macOS"
        case .macosSPM, .linux, .wasm, .android: nil
        }
    }
}
