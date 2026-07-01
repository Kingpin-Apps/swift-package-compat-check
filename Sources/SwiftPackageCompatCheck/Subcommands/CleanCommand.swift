import ArgumentParser
import Foundation

struct CleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove cache volumes and logs for one package."
    )

    @Argument(help: "Path to the Swift package. Defaults to the current directory. Equivalent to --path.")
    var pathArgument: String = "."

    @Option(
        name: [.customShort("P"), .customLong("path")],
        help: "Path to the Swift package (alternative to the positional argument). Wins if both are given."
    )
    var pathOption: String?

    @Option(
        name: .customLong("container-runtime"),
        help: "Container runtime whose volumes should be cleaned: docker (default), container (apple/container), or podman."
    )
    var containerRuntimeRaw: String?

    func run() async throws {
        let path = pathOption ?? pathArgument
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let basename = url.lastPathComponent.isEmpty ? "package" : url.lastPathComponent
        let root = CachePaths.defaultRoot()

        print("Cleaning caches for package: \(basename)")
        // Host-side dirs first — they don't need a runtime, so they're cleaned
        // even if the runtime preflight below fails.
        for sub in ["logs", "derived-data", "cloned-packages"] {
            let dir = root.appendingPathComponent(sub).appendingPathComponent(basename)
            if FileManager.default.fileExists(atPath: dir.path) {
                print("  rm -rf \(dir.path)")
                try? FileManager.default.removeItem(at: dir)
            }
        }

        // Flush the host-cleanup output before the runtime resolve, which may
        // throw to stderr. stdout is block-buffered when piped (not a TTY), so
        // without this the error would surface ahead of the lines above.
        fflush(stdout)

        // Removing cache volumes needs a live runtime; resolve + preflight it
        // (auto-detects when no flag is given, prefers apple/container).
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: containerRuntimeRaw, config: nil
        )
        let ops = CleanupOps(runtime: runtime)
        for volume in await ops.listPackageVolumes(packageBasename: basename) {
            print("  \(runtime.removeVolumeArgv(name: volume).joined(separator: " "))")
            await ops.removeVolume(volume)
        }
        print("Done.")
    }
}
