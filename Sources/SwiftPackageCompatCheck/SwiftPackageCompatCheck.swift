import ArgumentParser

public struct SwiftPackageCompatCheck: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "spcc",
        abstract: "Reproduce the Swift Package Index compatibility matrix locally.",
        discussion: """
            Builds a Swift package across the same (platform × Swift version) matrix that \
            swiftpackageindex.com runs, so you can validate cross-platform compatibility \
            without pushing a tag and waiting for SPI's CI queue.
            """,
        version: Version.number,
        subcommands: [
            RunCommand.self,
            CleanCommand.self,
            CleanAllCommand.self,
            ListCachesCommand.self,
            ImagesCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )

    public init() {}
}
