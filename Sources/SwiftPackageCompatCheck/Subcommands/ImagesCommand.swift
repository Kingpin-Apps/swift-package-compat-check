import ArgumentParser
import Foundation

struct ImagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "List or remove cached SPI builder Docker images."
    )

    @Flag(name: .long, help: "Remove the cached images instead of just listing them.")
    var remove: Bool = false

    func run() async throws {
        let ops = CleanupOps()
        let images = await ops.listSPIImages()
        if images.isEmpty {
            print("No SPI builder images cached locally.")
            return
        }
        if remove {
            for image in images {
                print("docker rmi \(image.reference)")
                await ops.removeImage(image.reference)
            }
        } else {
            for image in images {
                print("\(image.size)\t\(image.reference)")
            }
        }
    }
}
