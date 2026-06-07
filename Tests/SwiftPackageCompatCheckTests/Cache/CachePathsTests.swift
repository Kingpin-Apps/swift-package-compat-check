import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("CachePaths")
struct CachePathsTests {
    @Test("Default root honours $SPI_COMPAT_CACHE when set")
    func envOverride() {
        let root = CachePaths.defaultRoot(env: ["SPI_COMPAT_CACHE": "/tmp/custom-cache"])
        #expect(root.path == "/tmp/custom-cache")
    }

    @Test("Default root falls back to $HOME/.cache/spi-compat-check")
    func homeFallback() {
        let root = CachePaths.defaultRoot(env: ["HOME": "/Users/example"])
        #expect(root.path == "/Users/example/.cache/spi-compat-check")
    }

    @Test("Per-package directory layout matches the bash script")
    func directoryLayout() {
        let cache = CachePaths(
            root: URL(fileURLWithPath: "/tmp/spi"),
            packageBasename: "swift-nacl",
            runTimestamp: "20260606T120000"
        )
        #expect(cache.derivedDataRoot.path == "/tmp/spi/derived-data/swift-nacl")
        #expect(cache.clonedPackagesDir.path == "/tmp/spi/cloned-packages/swift-nacl")
        #expect(cache.runLogDir.path == "/tmp/spi/logs/swift-nacl/20260606T120000")
    }

    @Test("Per-cell paths embed platform-sv")
    func perCellPaths() {
        let cache = CachePaths(
            root: URL(fileURLWithPath: "/tmp/spi"),
            packageBasename: "swift-nacl",
            runTimestamp: "20260606T120000"
        )
        let pair = BuildPair(platform: .ios, swiftVersion: .v6_3)
        #expect(cache.derivedDataDir(for: pair).path == "/tmp/spi/derived-data/swift-nacl/ios-6.3")
        #expect(cache.logPath(for: pair).path == "/tmp/spi/logs/swift-nacl/20260606T120000/ios-6.3.log")
    }
}
