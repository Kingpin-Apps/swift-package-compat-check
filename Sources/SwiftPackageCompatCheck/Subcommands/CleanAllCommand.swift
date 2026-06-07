import ArgumentParser
import Foundation

struct CleanAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean-all",
        abstract: "Remove all spi-compat cache volumes and logs globally."
    )

    @Flag(name: .customLong("remove-images"), help: "Also remove cached SPI builder images.")
    var removeImages: Bool = false

    func run() async throws {
        let root = CachePaths.defaultRoot()

        print("Cleaning ALL spi-compat caches.")
        if FileManager.default.fileExists(atPath: root.path) {
            print("  rm -rf \(root.path)")
            try? FileManager.default.removeItem(at: root)
        }

        // Sweep volumes / images across both runtimes — a missing runtime
        // returns empty list, so the unused branch is a silent no-op.
        var totalImages = 0
        for runtime in ContainerRuntime.allCases {
            let ops = CleanupOps(runtime: runtime)
            let volumes = await ops.listSPIVolumes()
            for volume in volumes {
                print("  \(runtime.removeVolumeArgv(name: volume).joined(separator: " "))")
                await ops.removeVolume(volume)
            }
            let images = await ops.listSPIImages()
            totalImages += images.count
            if removeImages {
                for image in images {
                    print("  \(runtime.removeImageArgv(reference: image.reference).joined(separator: " "))")
                    await ops.removeImage(image.reference)
                }
            }
        }
        if !removeImages, totalImages > 0 {
            print("  (\(totalImages) SPI builder images kept; pass --remove-images to also drop them)")
        }
        print("Done.")
    }
}
