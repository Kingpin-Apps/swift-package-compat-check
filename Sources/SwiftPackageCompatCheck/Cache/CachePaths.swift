import Foundation

/// Resolves the cache directory layout shared with `spi-compat-check.sh`.
/// Layout (per the bash script — see [[spi-compat-check]] § Reproducing SPI fidelity):
///
///     <root>/derived-data/<pkg>/<platform>-<sv>      ← xcodebuild -derivedDataPath
///     <root>/cloned-packages/<pkg>                   ← xcodebuild -IDEClonedSourcePackagesDirPathOverride
///     <root>/logs/<pkg>/<RUN_TS>/<platform>-<sv>.log ← per-cell stdout+stderr
///
/// Root resolution: `$SPI_COMPAT_CACHE` env var if set, else `$HOME/.cache/spi-compat-check`.
/// Matching the bash script's `CACHE_DIR="${SPI_COMPAT_CACHE:-$HOME/.cache/spi-compat-check}"`.
public struct CachePaths: Sendable, Equatable {
    public let root: URL
    public let packageBasename: String
    public let runTimestamp: String

    public init(root: URL, packageBasename: String, runTimestamp: String) {
        self.root = root
        self.packageBasename = packageBasename
        self.runTimestamp = runTimestamp
    }

    /// Resolve the cache root from `$SPI_COMPAT_CACHE` or fall back to `$HOME/.cache/spi-compat-check`.
    public static func defaultRoot(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = env["SPI_COMPAT_CACHE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("spi-compat-check", isDirectory: true)
    }

    public var derivedDataRoot: URL {
        root.appendingPathComponent("derived-data", isDirectory: true)
            .appendingPathComponent(packageBasename, isDirectory: true)
    }

    public var clonedPackagesDir: URL {
        root.appendingPathComponent("cloned-packages", isDirectory: true)
            .appendingPathComponent(packageBasename, isDirectory: true)
    }

    public var runLogDir: URL {
        root.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent(packageBasename, isDirectory: true)
            .appendingPathComponent(runTimestamp, isDirectory: true)
    }

    public func derivedDataDir(for pair: BuildPair) -> URL {
        derivedDataRoot.appendingPathComponent(
            "\(pair.platform.rawValue)-\(pair.swiftVersion.rawValue)",
            isDirectory: true
        )
    }

    public func logPath(for pair: BuildPair) -> URL {
        runLogDir.appendingPathComponent(
            "\(pair.platform.rawValue)-\(pair.swiftVersion.rawValue).log"
        )
    }

    /// Create all directories needed before any runner starts writing.
    public func createDirectories() throws {
        let fm = FileManager.default
        for dir in [derivedDataRoot, clonedPackagesDir, runLogDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Auto-trim the package's log directory to the `maxRuns` most recent timestamped
    /// subdirectories, preserving the current run. Mirrors the bash script's
    /// `trim_old_logs` (`ls -1t | tail -n +$((MAX_LOG_RUNS + 1))`).
    public func trimOldLogs(maxRuns: Int = 5) {
        let logsRoot = root
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent(packageBasename, isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: logsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let dirs = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        let sorted = dirs.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        guard sorted.count > maxRuns else { return }

        for url in sorted.dropFirst(maxRuns) {
            if url.lastPathComponent == runTimestamp { continue }
            try? fm.removeItem(at: url)
        }
    }
}
