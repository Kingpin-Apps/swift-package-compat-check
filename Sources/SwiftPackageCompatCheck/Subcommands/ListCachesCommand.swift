import ArgumentParser

struct ListCachesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-caches",
        abstract: "Show disk usage of every spi-compat cache volume and log directory."
    )

    func run() async throws {
        print("spcc list-caches: not yet implemented (Phase 5)")
    }
}
