import Foundation

/// Minimal Codable shape over `swift package dump-package`'s JSON output.
/// Only decodes the fields needed for scheme detection — SwiftPM may include
/// many more keys, but unknown keys are ignored.
public struct PackageManifest: Codable, Sendable {
    public let name: String
    public let products: [Product]
    public let targets: [Target]

    public struct Product: Codable, Sendable {
        public let name: String
        public let type: ProductType
        public let targets: [String]
    }

    public struct Target: Codable, Sendable {
        public let name: String
        public let type: TargetType
    }

    public enum ProductType: Codable, Sendable, Equatable {
        case library
        case executable
        case plugin
        case test
        case other(String)

        private enum CodingKeys: String, CodingKey {
            case library, executable, plugin, test
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.library) { self = .library }
            else if container.contains(.executable) { self = .executable }
            else if container.contains(.plugin) { self = .plugin }
            else if container.contains(.test) { self = .test }
            else {
                let single = try decoder.singleValueContainer()
                let raw = (try? single.decode(String.self)) ?? "unknown"
                self = .other(raw)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .library: try container.encode([String](), forKey: .library)
            case .executable: try container.encodeNil(forKey: .executable)
            case .plugin: try container.encodeNil(forKey: .plugin)
            case .test: try container.encodeNil(forKey: .test)
            case .other(let raw):
                var single = encoder.singleValueContainer()
                try single.encode(raw)
            }
        }
    }

    public enum TargetType: String, Codable, Sendable {
        case regular
        case executable
        case test
        case system
        case binary
        case plugin
        case macro
    }
}
