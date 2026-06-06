import ArgumentParser

struct CleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove cache volumes and logs for one package."
    )

    @Argument(help: "Path to the Swift package. Defaults to the current directory.")
    var path: String = "."

    func run() async throws {
        print("spcc clean: not yet implemented (Phase 5)")
    }
}
