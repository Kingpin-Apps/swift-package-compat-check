import ArgumentParser
import Foundation

struct ListCachesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-caches",
        abstract: "Show disk usage of every spi-compat cache volume and log directory."
    )

    func run() async throws {
        let root = CachePaths.defaultRoot()
        let dockerOps = CleanupOps(runtime: .docker)

        print("Cache root: \(root.path)")
        if FileManager.default.fileExists(atPath: root.path) {
            print("  Total:        \(await dockerOps.pathSize(root))")
            for sub in ["logs", "derived-data", "cloned-packages"] {
                let subURL = root.appendingPathComponent(sub)
                guard FileManager.default.fileExists(atPath: subURL.path) else { continue }
                print("  \(sub)/")
                let pkgs = (try? FileManager.default.contentsOfDirectory(
                    at: subURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for pkg in pkgs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let isDir = (try? pkg.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    guard isDir else { continue }
                    let size = await dockerOps.pathSize(pkg)
                    print("    \(size.paddingLeft(to: 9))  \(pkg.lastPathComponent)")
                }
            }
        } else {
            print("  (does not exist)")
        }

        // Report volumes + images per installed runtime. Runtimes whose CLI
        // isn't installed return empty lists, so unused branches stay silent.
        for runtime in ContainerRuntime.allCases {
            let ops = CleanupOps(runtime: runtime)
            let volumes = await ops.listSPIVolumes()
            let images = await ops.listSPIImages()
            guard !volumes.isEmpty || !images.isEmpty else { continue }

            print("")
            print("[\(runtime.rawValue)] volumes (spi-compat-*):")
            if volumes.isEmpty {
                print("  (none)")
            } else {
                for volume in volumes {
                    let size = await ops.volumeSize(volume)
                    print("  \(size.paddingLeft(to: 9))  \(volume)")
                }
            }
            print("[\(runtime.rawValue)] images (spi-images):")
            if images.isEmpty {
                print("  (none)")
            } else {
                for image in images {
                    print("  \(image.size.paddingLeft(to: 9))  \(image.reference)")
                }
            }
        }
    }
}

private extension String {
    func paddingLeft(to width: Int) -> String {
        guard count < width else { return self }
        return String(repeating: " ", count: width - count) + self
    }
}
