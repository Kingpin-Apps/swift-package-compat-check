import Configuration
import ConfigurationTOML
import Foundation
import SystemPackage

/// Persistent defaults for `spcc run`. Loaded once at startup; merged with CLI
/// flags so individual invocations can still override anything in the file.
///
/// Resolution order, highest precedence first:
///
/// 1. `--config <path>` CLI flag
/// 2. `$SPCC_CONFIG` environment variable (full path to the config file)
/// 3. No config — every CLI flag uses its built-in default
///
/// File format is picked by extension: `.toml`, `.yaml` / `.yml`, or `.json`.
/// All three are parsed via `swift-configuration`'s `FileProvider`, matching the
/// pattern in `swift-cardano-multitool`.
///
/// Example `.spi-compat.toml`:
///
/// ```toml
/// swift_versions = ["6.2", "6.3"]
/// platforms      = ["ios", "macos-spm", "linux"]
/// scheme         = "MyLibrary"
/// timeout        = 600
/// max_parallel   = 4
/// pull_always    = true
///
/// [xcode]
/// "6.2" = "/Applications/Xcode-26.3.app"
/// "6.3" = "/Applications/Xcode-26.4.app"
///
/// [toolchain]
/// "6.2" = "swift-6.2-RELEASE"
///
/// [linux_image]
/// "6.3" = "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest"
/// ```
public struct SPCCConfig: Sendable {
    public var swiftVersions: [SwiftVersion]?
    public var platforms: [Platform]?
    public var scheme: String?
    public var maxParallel: Int?
    public var timeoutSeconds: Double?
    public var pullAlways: Bool?
    public var test: Bool?
    public var noLive: Bool?
    public var verbose: Bool?
    public var xcode: [SwiftVersion: String]
    public var toolchain: [SwiftVersion: String]
    public var linuxImage: [SwiftVersion: String]
    public var androidImage: [SwiftVersion: String]
    public var wasmImage: [SwiftVersion: String]
    public var wasmSDKURL: [SwiftVersion: String]

    /// Name of the environment variable used to find the config file when no
    /// `--config` flag is given.
    public static let envVariable = "SPCC_CONFIG"

    public init(
        swiftVersions: [SwiftVersion]? = nil,
        platforms: [Platform]? = nil,
        scheme: String? = nil,
        maxParallel: Int? = nil,
        timeoutSeconds: Double? = nil,
        pullAlways: Bool? = nil,
        test: Bool? = nil,
        noLive: Bool? = nil,
        verbose: Bool? = nil,
        xcode: [SwiftVersion: String] = [:],
        toolchain: [SwiftVersion: String] = [:],
        linuxImage: [SwiftVersion: String] = [:],
        androidImage: [SwiftVersion: String] = [:],
        wasmImage: [SwiftVersion: String] = [:],
        wasmSDKURL: [SwiftVersion: String] = [:]
    ) {
        self.swiftVersions = swiftVersions
        self.platforms = platforms
        self.scheme = scheme
        self.maxParallel = maxParallel
        self.timeoutSeconds = timeoutSeconds
        self.pullAlways = pullAlways
        self.test = test
        self.noLive = noLive
        self.verbose = verbose
        self.xcode = xcode
        self.toolchain = toolchain
        self.linuxImage = linuxImage
        self.androidImage = androidImage
        self.wasmImage = wasmImage
        self.wasmSDKURL = wasmSDKURL
    }

    // MARK: - Loading

    /// Load using the precedence chain: explicit path → `$SPCC_CONFIG` env var → `nil`.
    /// Returns `nil` when no config is configured — callers should fall back to
    /// CLI defaults.
    public static func load(
        explicitPath: String? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> SPCCConfig? {
        let path = explicitPath ?? env[envVariable]
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
        return try await load(from: url)
    }

    /// Load from a known file URL. Parser is picked by extension; unknown
    /// extensions are parsed as JSON.
    public static func load(from url: URL) async throws -> SPCCConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SPCCConfigError.fileNotFound(url.path)
        }
        let filePath = FilePath(url.path)
        let ext = url.pathExtension.lowercased()

        var providers: [any ConfigProvider] = []
        switch ext {
        case "toml":
            providers.append(try await FileProvider<TOMLSnapshot>(
                parsingOptions: .default,
                filePath: filePath
            ))
        default:
            // JSON is the safe default — TOML files with no extension would
            // need an explicit `.toml` suffix anyway.
            providers.append(try await FileProvider<JSONSnapshot>(
                filePath: filePath,
                allowMissing: false
            ))
        }

        let reader = ConfigReader(providers: providers)
        return SPCCConfig(reader: reader)
    }

    /// Build from an already-constructed `ConfigReader`. Useful for tests that
    /// want to inject fixture data without touching the filesystem.
    public init(reader: ConfigReader) {
        let rawSwiftVersions = reader.stringArray(forKey: ConfigKey("swift_versions"))
        if let raw = rawSwiftVersions, !raw.isEmpty {
            self.swiftVersions = raw.compactMap { SwiftVersion(rawValue: $0) }
        } else {
            self.swiftVersions = nil
        }

        let rawPlatforms = reader.stringArray(forKey: ConfigKey("platforms"))
        if let raw = rawPlatforms, !raw.isEmpty {
            self.platforms = raw.compactMap { Platform(rawValue: $0) }
        } else {
            self.platforms = nil
        }

        self.scheme = reader.string(forKey: ConfigKey("scheme"))
        self.maxParallel = reader.int(forKey: ConfigKey("max_parallel"))
        if let timeout = reader.double(forKey: ConfigKey("timeout")) {
            self.timeoutSeconds = timeout
        } else if let timeout = reader.int(forKey: ConfigKey("timeout")) {
            self.timeoutSeconds = Double(timeout)
        } else {
            self.timeoutSeconds = nil
        }
        self.pullAlways = reader.bool(forKey: ConfigKey("pull_always"))
        self.test = reader.bool(forKey: ConfigKey("test"))
        self.noLive = reader.bool(forKey: ConfigKey("no_live"))
        self.verbose = reader.bool(forKey: ConfigKey("verbose"))

        func readPerVersion(_ section: String) -> [SwiftVersion: String] {
            var result: [SwiftVersion: String] = [:]
            for sv in SwiftVersion.allCases {
                if let value = reader.string(forKey: ConfigKey("\(section).\(sv.rawValue)")) {
                    result[sv] = value
                }
            }
            return result
        }

        self.xcode = readPerVersion("xcode")
        self.toolchain = readPerVersion("toolchain")
        self.linuxImage = readPerVersion("linux_image")
        self.androidImage = readPerVersion("android_image")
        self.wasmImage = readPerVersion("wasm_image")
        self.wasmSDKURL = readPerVersion("wasm_sdk_url")
    }
}

public enum SPCCConfigError: Error, CustomStringConvertible {
    case fileNotFound(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): "Configuration file not found at \(path)."
        }
    }
}
