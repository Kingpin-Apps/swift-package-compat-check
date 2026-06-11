import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("--test-no-parallel injection")
struct TestNoParallelTests {
    @Test("macos-spm appends --no-parallel only in test mode")
    func macosSPM() {
        let testArgv = AppleArgvBuilders.macosSPM(toolchain: nil, runTests: true, noParallel: true)
        #expect(testArgv == ["xcrun", "swift", "test", "--arch", "arm64", "--no-parallel"])

        // noParallel is inert when not running tests (build has no such flag).
        let buildArgv = AppleArgvBuilders.macosSPM(toolchain: nil, runTests: false, noParallel: true)
        #expect(!buildArgv.contains("--no-parallel"))
    }

    @Test("xcodebuild test appends -parallel-testing-enabled NO")
    func xcodebuild() {
        let pair = BuildPair(platform: .ios, swiftVersion: .v6_3)
        let argv = try! #require(AppleArgvBuilders.xcodebuild(
            pair: pair,
            scheme: "Pkg",
            derivedDataPath: URL(fileURLWithPath: "/d"),
            clonedPackagesPath: URL(fileURLWithPath: "/c"),
            runTests: true,
            noParallel: true
        ))
        // The two tokens must be adjacent and in order.
        let idx = try! #require(argv.firstIndex(of: "-parallel-testing-enabled"))
        #expect(argv[argv.index(after: idx)] == "NO")

        let buildArgv = try! #require(AppleArgvBuilders.xcodebuild(
            pair: pair,
            scheme: "Pkg",
            derivedDataPath: URL(fileURLWithPath: "/d"),
            clonedPackagesPath: URL(fileURLWithPath: "/c"),
            runTests: false,
            noParallel: true
        ))
        #expect(!buildArgv.contains("-parallel-testing-enabled"))
    }

    @Test("Linux test body appends --no-parallel after the swift test command")
    func linux() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: true,
            noParallel: true
        )
        let script = try! #require(argv.last)
        #expect(script.contains("swift test --triple x86_64-unknown-linux-gnu --scratch-path /build --no-parallel"))
    }

    @Test("Linux build mode never adds --no-parallel even when requested")
    func linuxBuildIgnores() {
        let argv = LinuxArgvBuilders.docker(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: false,
            noParallel: true
        )
        let script = try! #require(argv.last)
        #expect(!script.contains("--no-parallel"))
    }

    @Test("Cross-SDK passes SDK_TEST_ARGS=--no-parallel in test mode, empty otherwise")
    func crossSDKEnv() {
        let testArgv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: true,
            noParallel: true
        )
        #expect(testArgv.contains("SDK_TEST_ARGS=--no-parallel"))
        // The resolver references the var so the flag actually reaches swift test.
        #expect(testArgv.last?.contains("${SDK_TEST_ARGS:-}") == true)

        let buildArgv = CrossSDKArgvBuilders.android(
            packagePath: URL(fileURLWithPath: "/x"),
            packageBasename: "p",
            swiftVersion: .v6_3,
            image: "img",
            pullPolicy: .missing,
            runTests: false,
            noParallel: true
        )
        #expect(buildArgv.contains("SDK_TEST_ARGS="))
    }
}
