import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the SPI build matrix against a package."
    )

    @Argument(help: "Path to the Swift package. Defaults to the current directory.")
    var path: String = "."

    @Option(
        name: [.short, .customLong("swift")],
        help: "Comma-separated Swift versions (default: 6.0,6.1,6.2,6.3)."
    )
    var swiftRaw: String?

    @Option(
        name: [.short, .customLong("platforms")],
        help: "Comma-separated platforms (default: all)."
    )
    var platformsRaw: String?

    @Option(
        name: [.customShort("S"), .customLong("scheme")],
        help: "Override the auto-detected scheme used by xcodebuild cells."
    )
    var scheme: String?

    @Flag(name: .long, help: "Print the matrix that would run without building anything.")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress non-essential output.")
    var quiet: Bool = false

    func run() async throws {
        let swiftVersions = try parseSwiftVersions(swiftRaw)
        let platforms = try parsePlatforms(platformsRaw)

        let detectedScheme: String
        if let scheme {
            detectedScheme = scheme
        } else {
            do {
                detectedScheme = try await SchemeDetector().detectScheme(packagePath: path)
            } catch {
                throw ValidationError("Scheme detection failed: \(error)")
            }
        }

        if !quiet {
            print("Package:   \(path)")
            print("Scheme:    \(detectedScheme)")
            print("Versions:  \(swiftVersions.map(\.rawValue).joined(separator: ", "))")
            print("Platforms: \(platforms.map(\.rawValue).joined(separator: ", "))")
            print("")
        }

        MatrixRenderer().render(platforms: platforms, swiftVersions: swiftVersions) { pair in
            if !pair.isSupportedBySPI { return .skipped }
            return .pending
        }

        if !dryRun {
            print("")
            print("spcc run: building cells is not yet implemented (Phase 2-4).")
            print("Use --dry-run to suppress this message.")
        }
    }

    private func parseSwiftVersions(_ raw: String?) throws -> [SwiftVersion] {
        guard let raw, !raw.isEmpty else { return SwiftVersion.allCases }
        return try raw.split(separator: ",").map { token in
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard let version = SwiftVersion(rawValue: trimmed) else {
                throw ValidationError(
                    "Unknown Swift version: \(trimmed). Allowed: \(SwiftVersion.allCases.map(\.rawValue).joined(separator: ", "))."
                )
            }
            return version
        }
    }

    private func parsePlatforms(_ raw: String?) throws -> [Platform] {
        guard let raw, !raw.isEmpty else { return Platform.allCases }
        return try raw.split(separator: ",").map { token in
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            guard let platform = Platform(rawValue: trimmed) else {
                throw ValidationError(
                    "Unknown platform: \(trimmed). Allowed: \(Platform.allCases.map(\.rawValue).joined(separator: ", "))."
                )
            }
            return platform
        }
    }
}
