import Command
import Foundation

/// Wrappers around `du -sh`, `docker volume ls/rm`, and `docker images/rmi` used by
/// the cleanup subcommands. Mirrors the bash script's helpers — `list_spi_volumes`,
/// `volume_size`, `list_spi_images`, etc. — so the user-facing output matches the
/// existing tool's format.
public struct CleanupOps: Sendable {
    public static let imageRepository = "registry.gitlab.com/swiftpackageindex/spi-images"

    private let runner: any CommandRunning

    public init(runner: any CommandRunning = CommandRunner()) {
        self.runner = runner
    }

    // MARK: - Listing

    /// `docker volume ls --filter "name=spi-compat" --format "{{.Name}}"`.
    public func listSPIVolumes() async -> [String] {
        await captureLines(arguments: [
            "docker", "volume", "ls",
            "--filter", "name=spi-compat",
            "--format", "{{.Name}}",
        ])
    }

    /// Volumes belonging to one package: `docker volume ls --filter name=spi-compat-build-<pkg>-`.
    public func listPackageVolumes(packageBasename: String) async -> [String] {
        await captureLines(arguments: [
            "docker", "volume", "ls",
            "--filter", "name=spi-compat-build-\(packageBasename)-",
            "--format", "{{.Name}}",
        ])
    }

    /// SPI builder images currently cached locally, with their docker-reported size.
    public func listSPIImages() async -> [(reference: String, size: String)] {
        let lines = await captureLines(arguments: [
            "docker", "images", Self.imageRepository,
            "--format", "{{.Repository}}:{{.Tag}}|{{.Size}}",
        ])
        return lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (reference: String(parts[0]), size: String(parts[1]))
        }
    }

    // MARK: - Removal

    /// `docker volume rm <name>`. Silently swallows errors (matches bash `|| true`).
    public func removeVolume(_ name: String) async {
        _ = await captureLines(arguments: ["docker", "volume", "rm", name])
    }

    /// `docker rmi <ref>`. Silently swallows errors.
    public func removeImage(_ reference: String) async {
        _ = await captureLines(arguments: ["docker", "rmi", reference])
    }

    // MARK: - Size reporting

    /// `du -sh <path>` first column, or `"0B"` if the path doesn't exist.
    public func pathSize(_ url: URL) async -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "0B" }
        let lines = await captureLines(arguments: ["du", "-sh", url.path])
        return lines.first?.split(separator: "\t").first.map(String.init) ?? "?"
    }

    /// Size of a docker volume — mounts it via `alpine du -sh /data` (matches bash).
    public func volumeSize(_ name: String) async -> String {
        let lines = await captureLines(arguments: [
            "docker", "run", "--rm", "-v", "\(name):/data", "alpine", "du", "-sh", "/data",
        ])
        return lines.first?.split(separator: "\t").first.map(String.init) ?? "?"
    }

    // MARK: - Internals

    private func captureLines(arguments: [String]) async -> [String] {
        var stdout = Data()
        do {
            for try await event in runner.run(arguments: arguments) {
                if case .standardOutput(let bytes) = event {
                    stdout.append(contentsOf: bytes)
                }
            }
        } catch {
            return []
        }
        return String(data: stdout, encoding: .utf8)?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []
    }
}
