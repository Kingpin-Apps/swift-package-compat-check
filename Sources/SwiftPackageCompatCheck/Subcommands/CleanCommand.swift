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
        help: "Container runtime whose volumes should be cleaned: docker (default) or container (apple/container)."
    )
    var containerRuntimeRaw: String?

    func run() async throws {
        let path = pathOption ?? pathArgument
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let basename = url.lastPathComponent.isEmpty ? "package" : url.lastPathComponent
        let root = CachePaths.defaultRoot()
        let runtime = try RunCommand.resolveContainerRuntime(
            cli: containerRuntimeRaw, config: nil
        )
        let ops = CleanupOps(runtime: runtime)

        print("Cleaning caches for package: \(basename)")
        for sub in ["logs", "derived-data", "cloned-packages"] {
            let dir = root.appendingPathComponent(sub).appendingPathComponent(basename)
            if FileManager.default.fileExists(atPath: dir.path) {
                print("  rm -rf \(dir.path)")
                try? FileManager.default.removeItem(at: dir)
            }
        }
        for volume in await ops.listPackageVolumes(packageBasename: basename) {
            print("  \(runtime.removeVolumeArgv(name: volume).joined(separator: " "))")
            await ops.removeVolume(volume)
        }
        print("Done.")
    }
}
