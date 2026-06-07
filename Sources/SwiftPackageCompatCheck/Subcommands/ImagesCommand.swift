import ArgumentParser
import Foundation

struct ImagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "List or remove cached SPI builder images (across all installed container runtimes)."
    )

    @Flag(name: .long, help: "Remove the cached images instead of just listing them.")
    var remove: Bool = false

    func run() async throws {
        var anyFound = false
        for runtime in ContainerRuntime.allCases {
            let ops = CleanupOps(runtime: runtime)
            let images = await ops.listSPIImages()
            guard !images.isEmpty else { continue }
            anyFound = true
            print("[\(runtime.rawValue)]")
            if remove {
                for image in images {
                    print(runtime.removeImageArgv(reference: image.reference).joined(separator: " "))
                    await ops.removeImage(image.reference)
                }
            } else {
                for image in images {
                    print("\(image.size)\t\(image.reference)")
                }
            }
        }
        if !anyFound {
            print("No SPI builder images cached locally.")
        }
    }
}
