import Command
import Foundation
import Path
import Testing
@testable import SwiftPackageCompatCheck

/// Recording runner that returns canned stdout lines per matching command.
/// Used to test that CleanupOps issues the right docker commands and parses
/// their output correctly.
final class StubCommandRunner: CommandRunning, @unchecked Sendable {
    var responses: [(prefix: [String], stdout: String)] = []
    private(set) var calls: [[String]] = []

    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        calls.append(arguments)
        let stdout = responses.first { Array(arguments.prefix($0.prefix.count)) == $0.prefix }?.stdout ?? ""
        return AsyncThrowingStream { continuation in
            if !stdout.isEmpty {
                continuation.yield(.standardOutput(Array(stdout.utf8)))
            }
            continuation.finish()
        }
    }
}

@Suite("CleanupOps")
struct CleanupOpsTests {
    @Test("listSPIVolumes parses one volume per line")
    func listVolumes() async {
        let stub = StubCommandRunner()
        stub.responses = [(["docker", "volume", "ls"], "spi-compat-build-pkg-6.3\nspi-compat-build-pkg-android-6.3\n")]
        let ops = CleanupOps(runner: stub)
        let volumes = await ops.listSPIVolumes()
        #expect(volumes == ["spi-compat-build-pkg-6.3", "spi-compat-build-pkg-android-6.3"])
        #expect(stub.calls[0].contains("--filter"))
        #expect(stub.calls[0].contains("name=spi-compat"))
    }

    @Test("listPackageVolumes scopes the docker filter to one package basename")
    func listPackageVolumes() async {
        let stub = StubCommandRunner()
        let ops = CleanupOps(runner: stub)
        _ = await ops.listPackageVolumes(packageBasename: "swift-nacl")
        #expect(stub.calls[0].contains("name=spi-compat-build-swift-nacl-"))
    }

    @Test("listSPIImages parses repo:tag|size lines")
    func listImages() async {
        let stub = StubCommandRunner()
        stub.responses = [(["docker", "images"], """
            registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest|1.2GB
            registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest|6.5GB
            """)]
        let ops = CleanupOps(runner: stub)
        let images = await ops.listSPIImages()
        #expect(images.count == 2)
        #expect(images[0].reference == "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest")
        #expect(images[0].size == "1.2GB")
        #expect(images[1].size == "6.5GB")
        // Query targets only the spi-images repo.
        #expect(stub.calls[0].contains(CleanupOps.imageRepository))
    }

    @Test("removeVolume issues docker volume rm <name>")
    func removeVolume() async {
        let stub = StubCommandRunner()
        let ops = CleanupOps(runner: stub)
        await ops.removeVolume("spi-compat-build-pkg-6.3")
        #expect(stub.calls[0] == ["docker", "volume", "rm", "spi-compat-build-pkg-6.3"])
    }

    @Test("removeImage issues docker rmi <ref>")
    func removeImage() async {
        let stub = StubCommandRunner()
        let ops = CleanupOps(runner: stub)
        await ops.removeImage("registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest")
        #expect(stub.calls[0] == ["docker", "rmi", "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest"])
    }

    @Test("pathSize returns 0B for a missing path without launching du")
    func pathSizeMissing() async {
        let stub = StubCommandRunner()
        let ops = CleanupOps(runner: stub)
        let size = await ops.pathSize(URL(fileURLWithPath: "/nonexistent/path/spi-compat"))
        #expect(size == "0B")
        #expect(stub.calls.isEmpty)
    }

    @Test("volumeSize parses the du -sh output's first column")
    func volumeSizeParses() async {
        let stub = StubCommandRunner()
        stub.responses = [(["docker", "run"], "1.2G\t/data\n")]
        let ops = CleanupOps(runner: stub)
        let size = await ops.volumeSize("spi-compat-build-pkg-6.3")
        #expect(size == "1.2G")
    }

    // MARK: - container runtime variants

    @Test("runtime=.container: listSPIVolumes parses --format json + prefix-filters client-side")
    func containerListVolumes() async {
        let stub = StubCommandRunner()
        stub.responses = [(["container", "volume", "list"], """
            [
              { "name": "spi-compat-build-pkg-6.3", "size": 1 },
              { "name": "spi-compat-build-pkg-android-6.3", "size": 1 },
              { "name": "unrelated", "size": 1 }
            ]
            """)]
        let ops = CleanupOps(runner: stub, runtime: .container)
        let volumes = await ops.listSPIVolumes()
        #expect(volumes == [
            "spi-compat-build-pkg-6.3",
            "spi-compat-build-pkg-android-6.3",
        ])
        #expect(stub.calls[0] == [
            "container", "volume", "list", "--format", "json",
        ])
    }

    @Test("runtime=.container: removeVolume uses 'volume delete' not 'volume rm'")
    func containerRemoveVolume() async {
        let stub = StubCommandRunner()
        let ops = CleanupOps(runner: stub, runtime: .container)
        await ops.removeVolume("spi-compat-build-pkg-6.3")
        #expect(stub.calls[0] == [
            "container", "volume", "delete", "spi-compat-build-pkg-6.3",
        ])
    }

    @Test("runtime=.container: removeImage uses 'image delete' not 'rmi'")
    func containerRemoveImage() async {
        let stub = StubCommandRunner()
        let ops = CleanupOps(runner: stub, runtime: .container)
        await ops.removeImage("registry.gitlab.com/spi/img:tag")
        #expect(stub.calls[0] == [
            "container", "image", "delete", "registry.gitlab.com/spi/img:tag",
        ])
    }

    @Test("runtime=.container: listSPIImages parses JSON + formats byte size")
    func containerListImages() async {
        let stub = StubCommandRunner()
        stub.responses = [(["container", "image", "list"], """
            [
              { "reference": "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest", "size": 1288490189 },
              { "reference": "ghcr.io/other/img:tag", "size": 1 }
            ]
            """)]
        let ops = CleanupOps(runner: stub, runtime: .container)
        let images = await ops.listSPIImages()
        #expect(images.count == 1)
        #expect(images[0].reference == "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest")
        #expect(images[0].size.hasSuffix("GB"))
    }

    @Test("runtime=.container: volumeSize uses 'container run' head with no --pull, no --name")
    func containerVolumeSize() async {
        let stub = StubCommandRunner()
        stub.responses = [(["container", "run"], "1.2G\t/data\n")]
        let ops = CleanupOps(runner: stub, runtime: .container)
        let size = await ops.volumeSize("spi-compat-build-pkg-6.3")
        #expect(size == "1.2G")
        let argv = stub.calls[0]
        #expect(argv.first == "container")
        #expect(!argv.contains { $0.hasPrefix("--pull=") })
        // No --name on the read-only size probe (the runtime auto-names).
        #expect(!argv.contains("--name"))
        #expect(argv.contains("spi-compat-build-pkg-6.3:/data"))
        #expect(argv.contains("alpine"))
    }
}

@Suite("CachePaths.trimOldLogs")
struct CachePathsTrimTests {
    @Test("Keeps the N most recent timestamped log dirs and the current run")
    func trimsOldest() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-trim-\(UUID().uuidString)", isDirectory: true)
        let cache = CachePaths(
            root: tmp,
            packageBasename: "pkg",
            runTimestamp: "20260606T120010"
        )
        try cache.createDirectories()

        let logsRoot = tmp.appendingPathComponent("logs").appendingPathComponent("pkg")
        let now = Date()
        for (idx, stamp) in [
            "20260606T120001", "20260606T120002", "20260606T120003",
            "20260606T120004", "20260606T120005", "20260606T120006",
            "20260606T120007", // 7 historical dirs in addition to the current
        ].enumerated() {
            let dir = logsRoot.appendingPathComponent(stamp)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Older index -> earlier modification date
            let mtime = now.addingTimeInterval(TimeInterval(idx))
            try FileManager.default.setAttributes(
                [.modificationDate: mtime],
                ofItemAtPath: dir.path
            )
        }

        cache.trimOldLogs(maxRuns: 5)

        let remaining = try FileManager.default.contentsOfDirectory(
            atPath: logsRoot.path
        ).sorted()
        // The current run (mtime: createDirectories) plus the 5 newest historicals
        // are kept; the oldest 2 historicals get pruned. Result: 6 dirs total.
        #expect(remaining.count <= 6)
        #expect(remaining.contains("20260606T120010"))  // current run preserved
        #expect(!remaining.contains("20260606T120001"))  // oldest pruned
        #expect(!remaining.contains("20260606T120002"))  // second-oldest pruned

        try? FileManager.default.removeItem(at: tmp)
    }
}
