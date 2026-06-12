import Testing
@testable import SwiftPackageCompatCheck

@Suite("Smoke")
struct SmokeTests {
    @Test("Library configures the root command")
    func rootCommandConfigured() {
        #expect(SwiftPackageCompatCheck.configuration.commandName == "spcc")
        #expect(SwiftPackageCompatCheck.configuration.version == Version.number)
        #expect(SwiftPackageCompatCheck.configuration.subcommands.count == 5)
    }
}
