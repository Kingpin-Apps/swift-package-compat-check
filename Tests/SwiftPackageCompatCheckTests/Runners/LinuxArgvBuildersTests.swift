import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("LinuxArgvBuilders")
struct LinuxArgvBuildersTests {
    @Test("Volume name embeds package basename and Swift version")
    func volumeName() {
        let name = LinuxArgvBuilders.volumeName(
            packageBasename: "swift-nacl",
            swiftVersion: .v6_3
        )
        #expect(name == "spi-compat-build-swift-nacl-6.3")
    }

    @Test("docker argv matches the bash script's run_linux verbatim")
    func dockerArgvShape() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/Users/me/Projects/swift-nacl"),
            packageBasename: "swift-nacl",
            swiftVersion: .v6_3,
            image: "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest",
            pullPolicy: .missing
        )

        // Top-level docker flags
        #expect(argv.prefix(8) == [
            "docker", "run",
            "--pull=missing",
            "--rm",
            "--platform", "linux/amd64",
            "-v", "/Users/me/Projects/swift-nacl:/host",
        ])

        // Working directory + scratch volume + SPI environment variables
        #expect(argv.contains("-w"))
        #expect(argv.contains("/host"))
        #expect(argv.contains("spi-compat-build-swift-nacl-6.3:/build"))
        #expect(argv.contains("JAVA_HOME=/root/.sdkman/candidates/java/current"))
        #expect(argv.contains("SPI_BUILD=1"))
        #expect(argv.contains("SPI_PROCESSING=1"))

        // Image followed by the bash -c script
        #expect(argv.contains("registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest"))
        #expect(argv.last?.contains("swift build --triple x86_64-unknown-linux-gnu --scratch-path /build") == true)
        #expect(argv.last?.contains("swift --version") == true)
    }

    @Test("pullPolicy 'always' is honoured")
    func pullAlwaysOverride() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_2,
            image: "img",
            pullPolicy: .always
        )
        #expect(argv.contains("--pull=always"))
        #expect(!argv.contains("--pull=missing"))
    }

    @Test("--test flag swaps swift build → swift test inside the bash body")
    func linuxTestMode() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: true
        )
        let script = try! #require(argv.last)
        #expect(script.contains("swift test --triple x86_64-unknown-linux-gnu"))
        #expect(!script.contains("swift build --triple"))
    }

    @Test("runtime=.container swaps docker→container, drops --pull, adds --name")
    func containerRuntimeArgv() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "swift-nacl",
            swiftVersion: .v6_3,
            image: "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest",
            pullPolicy: .missing,
            cellLabel: "20260607T120000-linux-6.3",
            runtime: .container
        )
        #expect(argv.first == "container")
        #expect(!argv.contains { $0.hasPrefix("--pull=") })
        #expect(argv.contains("--name"))
        #expect(argv.contains("spcc-cell-20260607T120000-linux-6.3"))
        // The SPI-verbatim middle is unchanged regardless of runtime.
        #expect(argv.contains("-v"))
        #expect(argv.contains("spi-compat-build-swift-nacl-6.3:/build"))
        #expect(argv.contains("JAVA_HOME=/root/.sdkman/candidates/java/current"))
        #expect(argv.contains("registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest"))
    }

    @Test("runtime=.container with useRosetta=true appends --rosetta")
    func containerRosettaOptIn() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            cellLabel: "x",
            runtime: .container,
            useRosetta: true
        )
        #expect(argv.contains("--rosetta"))
    }
}

@Suite("Platform.defaultDockerImage")
struct DefaultDockerImageTests {
    @Test("Linux image follows SPI's basic-<sv>-latest pattern")
    func linuxImage() {
        #expect(Platform.linux.defaultDockerImage(for: .v6_0)
                == "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.0-latest")
        #expect(Platform.linux.defaultDockerImage(for: .v6_3)
                == "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest")
    }

    @Test("Android and Wasm follow SPI's pattern; Apple platforms return nil")
    func nonLinuxPlatforms() {
        #expect(Platform.android.defaultDockerImage(for: .v6_3)
                == "registry.gitlab.com/swiftpackageindex/spi-images:android-6.3-latest")
        #expect(Platform.wasm.defaultDockerImage(for: .v6_3)
                == "registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest")
        #expect(Platform.ios.defaultDockerImage(for: .v6_3) == nil)
        #expect(Platform.macosSPM.defaultDockerImage(for: .v6_3) == nil)
    }
}
