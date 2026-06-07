import Testing
import SwiftPackageCompatCheck

@Suite("BuildPair")
struct BuildPairTests {
    @Test("all enumerates every platform × Swift version")
    func enumeratesFullGrid() {
        #expect(BuildPair.all.count == Platform.allCases.count * SwiftVersion.allCases.count)
    }

    @Test("supported drops Android@6.0 and WASM@6.0")
    func supportedMatchesSPI() {
        // 9 platforms × 4 Swift versions − 2 = 34 cells, matching SPI's BuildPair.all.
        #expect(BuildPair.supported.count == 34)
        #expect(!BuildPair.supported.contains(BuildPair(platform: .android, swiftVersion: .v6_0)))
        #expect(!BuildPair.supported.contains(BuildPair(platform: .wasm, swiftVersion: .v6_0)))
        #expect(BuildPair.supported.contains(BuildPair(platform: .android, swiftVersion: .v6_1)))
        #expect(BuildPair.supported.contains(BuildPair(platform: .wasm, swiftVersion: .v6_1)))
    }

    @Test("isSupportedBySPI matches the skip rule")
    func skipRule() {
        #expect(BuildPair(platform: .android, swiftVersion: .v6_0).isSupportedBySPI == false)
        #expect(BuildPair(platform: .wasm, swiftVersion: .v6_0).isSupportedBySPI == false)
        #expect(BuildPair(platform: .linux, swiftVersion: .v6_0).isSupportedBySPI == true)
        #expect(BuildPair(platform: .android, swiftVersion: .v6_3).isSupportedBySPI == true)
    }

    @Test("filtered intersects requested platforms × Swift versions")
    func filteredIntersection() {
        let filtered = BuildPair.filtered(
            platforms: [.linux, .android],
            swiftVersions: [.v6_2, .v6_3]
        )
        #expect(filtered.count == 4)
        #expect(filtered.allSatisfy { [.linux, .android].contains($0.platform) })
        #expect(filtered.allSatisfy { [.v6_2, .v6_3].contains($0.swiftVersion) })
    }
}
