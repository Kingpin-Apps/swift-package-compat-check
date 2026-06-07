import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("ContainerRuntime — runArgvHead")
struct ContainerRuntimeRunArgvHeadTests {
    @Test("docker emits --pull=<policy>, no --name, no --rosetta")
    func dockerHead() {
        let argv = ContainerRuntime.docker.runArgvHead(
            cellLabel: "20260607T120000-linux-6.3",
            pullPolicy: .missing
        )
        #expect(argv == [
            "docker", "run",
            "--pull=missing",
            "--rm",
            "--platform", "linux/amd64",
        ])
    }

    @Test("docker honours pullPolicy=always")
    func dockerHeadAlways() {
        let argv = ContainerRuntime.docker.runArgvHead(
            cellLabel: "x", pullPolicy: .always
        )
        #expect(argv.contains("--pull=always"))
        #expect(!argv.contains("--pull=missing"))
    }

    @Test("container omits --pull, emits --name <sanitised>, and caps memory")
    func containerHead() {
        let argv = ContainerRuntime.container.runArgvHead(
            cellLabel: "20260607T120000-linux-6.3",
            pullPolicy: .missing
        )
        #expect(argv == [
            "container", "run",
            "--rm",
            "--platform", "linux/amd64",
            "--name", "spcc-cell-20260607T120000-linux-6.3",
            "-m", ContainerRuntime.defaultContainerMemory,
        ])
        // Container never carries the docker --pull flag.
        #expect(!argv.contains { $0.hasPrefix("--pull=") })
    }

    @Test("container memory override replaces the default")
    func containerMemoryOverride() {
        let argv = ContainerRuntime.container.runArgvHead(
            cellLabel: "x", pullPolicy: .missing, memory: "16G"
        )
        // Find the -m and check the value that follows.
        let idx = try! #require(argv.firstIndex(of: "-m"))
        #expect(argv[idx + 1] == "16G")
        #expect(!argv.contains(ContainerRuntime.defaultContainerMemory))
    }

    @Test("container appends --rosetta only when useRosetta == true")
    func containerRosettaOptIn() {
        let off = ContainerRuntime.container.runArgvHead(
            cellLabel: "x", pullPolicy: .missing, useRosetta: false
        )
        #expect(!off.contains("--rosetta"))

        let on = ContainerRuntime.container.runArgvHead(
            cellLabel: "x", pullPolicy: .missing, useRosetta: true
        )
        #expect(on.contains("--rosetta"))
    }
}

@Suite("ContainerRuntime — pullArgv")
struct ContainerRuntimePullArgvTests {
    @Test("docker returns nil — inline --pull handles it")
    func dockerNoPreStep() {
        #expect(ContainerRuntime.docker.pullArgv(image: "img") == nil)
    }

    @Test("container returns the explicit pull argv")
    func containerPreStep() {
        let argv = ContainerRuntime.container.pullArgv(
            image: "registry.gitlab.com/spi/img:tag"
        )
        #expect(argv == [
            "container", "image", "pull",
            "--platform", "linux/amd64",
            "registry.gitlab.com/spi/img:tag",
        ])
    }
}

@Suite("ContainerRuntime — volume + image argv")
struct ContainerRuntimeArgvHelpersTests {
    @Test("removeVolumeArgv swaps rm <-> delete per runtime")
    func removeVolume() {
        #expect(ContainerRuntime.docker.removeVolumeArgv(name: "v")
                == ["docker", "volume", "rm", "v"])
        #expect(ContainerRuntime.container.removeVolumeArgv(name: "v")
                == ["container", "volume", "delete", "v"])
    }

    @Test("removeImageArgv swaps rmi <-> image delete per runtime")
    func removeImage() {
        #expect(ContainerRuntime.docker.removeImageArgv(reference: "r")
                == ["docker", "rmi", "r"])
        #expect(ContainerRuntime.container.removeImageArgv(reference: "r")
                == ["container", "image", "delete", "r"])
    }

    @Test("docker listVolumesArgv carries server-side --filter name=")
    func dockerVolumeList() {
        let argv = ContainerRuntime.docker.listVolumesArgv(prefix: "spi-compat")
        #expect(argv.contains("--filter"))
        #expect(argv.contains("name=spi-compat"))
    }

    @Test("container listVolumesArgv uses --format json (no filter)")
    func containerVolumeList() {
        let argv = ContainerRuntime.container.listVolumesArgv(prefix: "spi-compat")
        #expect(argv == ["container", "volume", "list", "--format", "json"])
    }

    @Test("docker listImagesArgv takes the repository positionally")
    func dockerImageList() {
        let argv = ContainerRuntime.docker.listImagesArgv(
            repository: "registry.gitlab.com/spi/img"
        )
        #expect(argv.contains("registry.gitlab.com/spi/img"))
        #expect(argv.contains("--format"))
    }

    @Test("container listImagesArgv uses --format json (no filter)")
    func containerImageList() {
        let argv = ContainerRuntime.container.listImagesArgv(repository: "x")
        #expect(argv == ["container", "image", "list", "--format", "json"])
    }
}

@Suite("ContainerRuntime — parseVolumeList")
struct ContainerRuntimeParseVolumeListTests {
    @Test("docker parses one volume per line, prefix-filtered")
    func dockerParse() {
        let stdout = """
            spi-compat-build-pkg-6.3
            spi-compat-build-pkg-android-6.3
            unrelated-volume
            """
        let volumes = ContainerRuntime.docker.parseVolumeList(
            stdout, prefix: "spi-compat"
        )
        #expect(volumes == [
            "spi-compat-build-pkg-6.3",
            "spi-compat-build-pkg-android-6.3",
        ])
    }

    @Test("container parses JSON entries and applies the prefix filter")
    func containerParse() {
        let stdout = """
            [
              { "name": "spi-compat-build-pkg-6.3", "size": 12345 },
              { "name": "spi-compat-build-pkg-android-6.3", "size": 9999 },
              { "name": "unrelated-volume", "size": 1 }
            ]
            """
        let volumes = ContainerRuntime.container.parseVolumeList(
            stdout, prefix: "spi-compat"
        )
        #expect(volumes == [
            "spi-compat-build-pkg-6.3",
            "spi-compat-build-pkg-android-6.3",
        ])
    }

    @Test("container tolerates malformed JSON")
    func containerParseMalformed() {
        let volumes = ContainerRuntime.container.parseVolumeList(
            "not json", prefix: "spi-compat"
        )
        #expect(volumes.isEmpty)
    }
}

@Suite("ContainerRuntime — parseImageList")
struct ContainerRuntimeParseImageListTests {
    @Test("docker parses repo:tag|size lines")
    func dockerParse() {
        let stdout = """
            registry.gitlab.com/spi/img:basic-6.3-latest|1.2GB
            registry.gitlab.com/spi/img:wasm-6.3-latest|6.5GB
            """
        let images = ContainerRuntime.docker.parseImageList(
            stdout, repository: "registry.gitlab.com/spi/img"
        )
        #expect(images.count == 2)
        #expect(images[0].reference == "registry.gitlab.com/spi/img:basic-6.3-latest")
        #expect(images[0].size == "1.2GB")
        #expect(images[1].size == "6.5GB")
    }

    @Test("container parses JSON; converts byte size to human-readable")
    func containerParse() {
        let stdout = """
            [
              { "reference": "registry.gitlab.com/spi/img:basic-6.3-latest", "size": 1288490189 },
              { "reference": "registry.gitlab.com/spi/img:wasm-6.3-latest", "size": "6979321856" },
              { "reference": "ghcr.io/other/img:tag", "size": 1 }
            ]
            """
        let images = ContainerRuntime.container.parseImageList(
            stdout, repository: "registry.gitlab.com/spi/img"
        )
        #expect(images.count == 2)
        #expect(images[0].reference == "registry.gitlab.com/spi/img:basic-6.3-latest")
        // 1288490189 bytes ≈ 1.2 GB
        #expect(images[0].size.hasSuffix("GB"))
        #expect(images[1].size.hasSuffix("GB"))
    }
}

@Suite("ContainerRuntime — sanitiseCellName")
struct ContainerRuntimeSanitiseTests {
    @Test("Already-valid label is prefixed and returned unchanged")
    func cleanLabel() {
        let name = ContainerRuntime.sanitiseCellName("20260607T120000-linux-6.3")
        #expect(name == "spcc-cell-20260607T120000-linux-6.3")
    }

    @Test("Illegal chars become dashes; consecutive dashes collapse")
    func dirtyLabel() {
        let name = ContainerRuntime.sanitiseCellName("2026:06:07T12:00:00/linux//6.3")
        #expect(name == "spcc-cell-2026-06-07T12-00-00-linux-6.3")
    }

    @Test("Resulting name matches the [a-zA-Z0-9][a-zA-Z0-9_.-]* shape")
    func nameShape() {
        let name = ContainerRuntime.sanitiseCellName("20260607T120000-linux-6.3")
        let first = try! #require(name.first)
        #expect(first.isLetter || first.isNumber)
        let allowed = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"
        )
        #expect(name.allSatisfy { allowed.contains($0) })
    }

    @Test("Very long labels truncate and append SHA suffix to preserve uniqueness")
    func longLabelHashSuffix() {
        let long = String(repeating: "A", count: 1024)
        let name = ContainerRuntime.sanitiseCellName(long)
        #expect(name.count <= 240)
        // Last component should be the 8-hex SHA suffix.
        let suffix = name.suffix(9)  // "-" + 8 hex
        #expect(suffix.first == "-")
        #expect(suffix.dropFirst().allSatisfy { $0.isHexDigit })

        // Different long inputs must produce different names.
        let other = ContainerRuntime.sanitiseCellName(String(repeating: "B", count: 1024))
        #expect(name != other)
    }
}
