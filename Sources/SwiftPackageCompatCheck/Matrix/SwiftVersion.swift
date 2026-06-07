public enum SwiftVersion: String, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case v6_0 = "6.0"
    case v6_1 = "6.1"
    case v6_2 = "6.2"
    case v6_3 = "6.3"

    public var description: String { rawValue }
}
