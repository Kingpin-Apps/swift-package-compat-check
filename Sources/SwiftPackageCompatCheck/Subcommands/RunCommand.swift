import ArgumentParser

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the SPI build matrix against a package."
    )

    @Argument(help: "Path to the Swift package. Defaults to the current directory.")
    var path: String = "."

    func run() async throws {
        print("spcc run: not yet implemented (Phase 1)")
        print("  package: \(path)")
    }
}
