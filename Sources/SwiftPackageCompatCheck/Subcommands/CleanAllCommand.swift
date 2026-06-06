import ArgumentParser

struct CleanAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean-all",
        abstract: "Remove all spi-compat cache volumes and logs globally."
    )

    func run() async throws {
        print("spcc clean-all: not yet implemented (Phase 5)")
    }
}
