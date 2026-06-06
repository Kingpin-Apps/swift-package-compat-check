import Testing
@testable import SwiftPackageCompatCheck

@Suite("Smoke")
struct SmokeTests {
    @Test("Library configures the root command")
    func rootCommandConfigured() {
        #expect(SPCC.configuration.commandName == "spcc")
        #expect(SPCC.configuration.version == Version.number)
        #expect(SPCC.configuration.subcommands.count == 5)
    }
}
