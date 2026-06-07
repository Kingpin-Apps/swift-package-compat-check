import ArgumentParser
import Foundation

struct CleanAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean-all",
        abstract: "Remove all spi-compat cache volumes and logs globally."
    )

    @Flag(name: .customLong("remove-images"), help: "Also remove cached SPI builder Docker images.")
    var removeImages: Bool = false

    func run() async throws {
        let root = CachePaths.defaultRoot()
        let ops = CleanupOps()

        print("Cleaning ALL spi-compat caches.")
        if FileManager.default.fileExists(atPath: root.path) {
            print("  rm -rf \(root.path)")
            try? FileManager.default.removeItem(at: root)
        }
        for volume in await ops.listSPIVolumes() {
            print("  docker volume rm \(volume)")
            await ops.removeVolume(volume)
        }
        let images = await ops.listSPIImages()
        if removeImages {
            for image in images {
                print("  docker rmi \(image.reference)")
                await ops.removeImage(image.reference)
            }
        } else if !images.isEmpty {
            print("  (\(images.count) SPI builder images kept; pass --remove-images to also drop them)")
        }
        print("Done.")
    }
}
