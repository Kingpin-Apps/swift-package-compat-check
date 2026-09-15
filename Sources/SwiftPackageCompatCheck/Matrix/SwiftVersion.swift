public enum SwiftVersion: String, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case v6_0 = "6.0"
    case v6_1 = "6.1"
    case v6_2 = "6.2"
    case v6_3 = "6.3"
    case v6_4 = "6.4"

    public var description: String { rawValue }

    /// Tag suffix of SPI's builder images (`<plat>-<sv>-<suffix>`). SPI only
    /// publishes `-latest` from spi-images' main branch, so versions added on a
    /// release tag before main catches up are pinned to that release.
    public var spiImageTagSuffix: String {
        switch self {
        case .v6_4: "1.33.0"
        default: "latest"
        }
    }
}
