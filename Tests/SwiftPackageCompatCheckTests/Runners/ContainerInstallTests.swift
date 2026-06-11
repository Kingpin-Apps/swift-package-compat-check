import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("ContainerInstall.aptPreamble")
struct ContainerInstallTests {
    @Test("Empty package list yields an empty preamble")
    func emptyIsEmpty() {
        #expect(ContainerInstall.aptPreamble(packages: []) == "")
    }

    @Test("Non-empty list emits a self-contained apt block ending in a newline")
    func aptBlockShape() {
        let preamble = ContainerInstall.aptPreamble(packages: ["gnupg", "libgcrypt20-dev"])
        #expect(preamble.contains("set -euo pipefail"))
        #expect(preamble.contains("export DEBIAN_FRONTEND=noninteractive"))
        #expect(preamble.contains("apt-get update -qq"))
        #expect(preamble.contains("apt-get install -y --no-install-recommends gnupg libgcrypt20-dev"))
        // Trailing newline lets callers prepend it directly to a script body.
        #expect(preamble.hasSuffix("\n"))
    }
}

@Suite("Container install injection into argv builders")
struct ContainerInstallInjectionTests {
    @Test("Linux bash body installs apt packages before swift build/test")
    func linuxInjectsApt() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: true,
            installPackages: ["gnupg"]
        )
        let script = try! #require(argv.last)
        #expect(script.contains("apt-get install -y --no-install-recommends gnupg"))
        // Install must precede the build so the build can use the package.
        let installRange = try! #require(script.range(of: "apt-get install"))
        let buildRange = try! #require(script.range(of: "swift test --triple"))
        #expect(installRange.lowerBound < buildRange.lowerBound)
    }

    @Test("Linux with no install packages leaves the body unchanged")
    func linuxNoInstall() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing
        )
        let script = try! #require(argv.last)
        #expect(!script.contains("apt-get"))
    }

    @Test("Android resolver body installs apt packages before the resolver runs")
    func androidInjectsApt() {
        let argv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            installPackages: ["libsqlite3-dev"]
        )
        let script = try! #require(argv.last)
        #expect(script.contains("apt-get install -y --no-install-recommends libsqlite3-dev"))
        let installRange = try! #require(script.range(of: "apt-get install"))
        let swiftVersionRange = try! #require(script.range(of: "swift --version"))
        #expect(installRange.lowerBound < swiftVersionRange.lowerBound)
    }

    @Test("Wasm resolver body installs apt packages")
    func wasmInjectsApt() {
        let argv = CrossSDKArgvBuilders.wasm(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            fallbackURL: nil,
            installPackages: ["jq"]
        )
        let script = try! #require(argv.last)
        #expect(script.contains("apt-get install -y --no-install-recommends jq"))
    }
}
