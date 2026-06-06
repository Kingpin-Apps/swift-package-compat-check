import ArgumentParser

struct ImagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "List or remove cached SPI builder Docker images."
    )

    @Flag(name: .long, help: "Remove the cached images instead of just listing them.")
    var remove: Bool = false

    func run() async throws {
        print("spcc images: not yet implemented (Phase 5)")
    }
}
