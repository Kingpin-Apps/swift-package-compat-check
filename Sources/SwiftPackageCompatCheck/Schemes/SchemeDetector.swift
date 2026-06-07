import Command
import Foundation

public enum SchemeDetectionError: Error, CustomStringConvertible {
    case dumpPackageFailed(stderr: String)
    case manifestParseFailed(underlying: Error)
    case noLibraryProduct(packageName: String)

    public var description: String {
        switch self {
        case .dumpPackageFailed(let stderr):
            "`swift package dump-package` failed:\n\(stderr)"
        case .manifestParseFailed(let underlying):
            "Could not parse `swift package dump-package` output: \(underlying)"
        case .noLibraryProduct(let pkg):
            "Package '\(pkg)' has no library product backed by a regular Swift target. Pass --scheme explicitly."
        }
    }
}

public struct SchemeDetector: Sendable {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = CommandRunner()) {
        self.runner = runner
    }

    /// Run `swift package dump-package --package-path <path>` and pick the first
    /// library product whose backing target is type `.regular` (a Swift target).
    /// Skips system C targets like `Clibsodium` that would alphabetize first.
    public func detectScheme(packagePath: String) async throws -> String {
        let manifest = try await loadManifest(packagePath: packagePath)
        return try Self.pickScheme(from: manifest)
    }

    func loadManifest(packagePath: String) async throws -> PackageManifest {
        var stdout = Data()
        var stderr = Data()
        do {
            for try await event in runner.run(
                arguments: ["swift", "package", "--package-path", packagePath, "dump-package"]
            ) {
                switch event {
                case .standardOutput(let bytes): stdout.append(contentsOf: bytes)
                case .standardError(let bytes): stderr.append(contentsOf: bytes)
                }
            }
        } catch {
            let message = String(data: stderr, encoding: .utf8) ?? "\(error)"
            throw SchemeDetectionError.dumpPackageFailed(stderr: message)
        }

        do {
            return try JSONDecoder().decode(PackageManifest.self, from: stdout)
        } catch {
            throw SchemeDetectionError.manifestParseFailed(underlying: error)
        }
    }

    static func pickScheme(from manifest: PackageManifest) throws -> String {
        let regularTargets = Set(
            manifest.targets.filter { $0.type == .regular }.map(\.name)
        )

        let candidate = manifest.products.first { product in
            guard product.type == .library else { return false }
            return product.targets.contains(where: regularTargets.contains)
        }

        guard let scheme = candidate?.name else {
            throw SchemeDetectionError.noLibraryProduct(packageName: manifest.name)
        }
        return scheme
    }
}
