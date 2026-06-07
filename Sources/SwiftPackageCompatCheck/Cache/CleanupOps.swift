import Command
import Foundation

/// Wrappers around `du -sh` and the host container runtime's volume / image
/// commands. Mirrors the bash script's helpers — `list_spi_volumes`,
/// `volume_size`, `list_spi_images`, etc. — so the user-facing output matches
/// the existing tool's format regardless of which runtime ran the build.
public struct CleanupOps: Sendable {
    public static let imageRepository = "registry.gitlab.com/swiftpackageindex/spi-images"

    private let runner: any CommandRunning
    public let runtime: ContainerRuntime

    public init(
        runner: any CommandRunning = CommandRunner(),
        runtime: ContainerRuntime = .docker
    ) {
        self.runner = runner
        self.runtime = runtime
    }

    // MARK: - Listing

    /// Volumes whose name begins with `spi-compat`. Docker uses a server-side
    /// `--filter name=`; container has no filter and we parse the JSON output
    /// client-side via `ContainerRuntime.parseVolumeList`.
    public func listSPIVolumes() async -> [String] {
        let stdout = await captureRaw(arguments: runtime.listVolumesArgv(prefix: "spi-compat"))
        return runtime.parseVolumeList(stdout, prefix: "spi-compat")
    }

    /// Volumes belonging to one package — same filter scoped to the package
    /// basename.
    public func listPackageVolumes(packageBasename: String) async -> [String] {
        let prefix = "spi-compat-build-\(packageBasename)-"
        let stdout = await captureRaw(arguments: runtime.listVolumesArgv(prefix: prefix))
        return runtime.parseVolumeList(stdout, prefix: prefix)
    }

    /// SPI builder images currently cached locally, with their runtime-reported size.
    public func listSPIImages() async -> [(reference: String, size: String)] {
        let stdout = await captureRaw(
            arguments: runtime.listImagesArgv(repository: Self.imageRepository)
        )
        return runtime.parseImageList(stdout, repository: Self.imageRepository)
    }

    // MARK: - Removal

    /// `<runtime> volume rm|delete <name>`. Silently swallows errors (matches
    /// bash `|| true`).
    public func removeVolume(_ name: String) async {
        _ = await captureLines(arguments: runtime.removeVolumeArgv(name: name))
    }

    /// `<runtime> rmi | image delete <ref>`. Silently swallows errors.
    public func removeImage(_ reference: String) async {
        _ = await captureLines(arguments: runtime.removeImageArgv(reference: reference))
    }

    // MARK: - Size reporting

    /// `du -sh <path>` first column, or `"0B"` if the path doesn't exist.
    public func pathSize(_ url: URL) async -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "0B" }
        let lines = await captureLines(arguments: ["du", "-sh", url.path])
        return lines.first?.split(separator: "\t").first.map(String.init) ?? "?"
    }

    /// Size of a named volume — mounts it via `alpine du -sh /data` (matches
    /// bash). Uses the active runtime's `run` shape with no pull policy + no
    /// kill label since this is a one-shot read-only mount.
    public func volumeSize(_ name: String) async -> String {
        let head = runtime.runArgvHead(cellLabel: "", pullPolicy: .missing)
        var argv = head
        // Container head already includes a `--name spcc-cell-` (since
        // cellLabel was ""); strip the empty pair so the runtime auto-names.
        if let idx = argv.firstIndex(of: "--name"), idx + 1 < argv.count {
            argv.removeSubrange(idx ... idx + 1)
        }
        argv.append(contentsOf: ["-v", "\(name):/data", "alpine", "du", "-sh", "/data"])
        let lines = await captureLines(arguments: argv)
        return lines.first?.split(separator: "\t").first.map(String.init) ?? "?"
    }

    // MARK: - Internals

    private func captureLines(arguments: [String]) async -> [String] {
        let stdout = await captureRaw(arguments: arguments)
        return stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func captureRaw(arguments: [String]) async -> String {
        var stdout = Data()
        do {
            for try await event in runner.run(arguments: arguments) {
                if case .standardOutput(let bytes) = event {
                    stdout.append(contentsOf: bytes)
                }
            }
        } catch {
            return ""
        }
        return String(data: stdout, encoding: .utf8) ?? ""
    }
}
