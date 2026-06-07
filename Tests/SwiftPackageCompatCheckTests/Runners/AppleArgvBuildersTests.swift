import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("AppleArgvBuilders")
struct AppleArgvBuildersTests {
    @Test("macos-spm with no toolchain matches bash verbatim")
    func macosSPMDefault() {
        let argv = AppleArgvBuilders.macosSPM(toolchain: nil)
        #expect(argv == ["xcrun", "swift", "build", "--arch", "arm64"])
    }

    @Test("macos-spm with --toolchain injects xcrun --toolchain <id>")
    func macosSPMWithToolchain() {
        let argv = AppleArgvBuilders.macosSPM(toolchain: "swift-6.3-RELEASE")
        #expect(argv == [
            "xcrun", "--toolchain", "swift-6.3-RELEASE",
            "swift", "build", "--arch", "arm64",
        ])
    }

    @Test("xcodebuild for ios uses generic/platform=iOS")
    func xcodebuildIOS() {
        let pair = BuildPair(platform: .ios, swiftVersion: .v6_3)
        let argv = AppleArgvBuilders.xcodebuild(
            pair: pair,
            scheme: "SwiftNaCl",
            derivedDataPath: URL(fileURLWithPath: "/tmp/spi/derived-data/swift-nacl/ios-6.3"),
            clonedPackagesPath: URL(fileURLWithPath: "/tmp/spi/cloned-packages/swift-nacl")
        )
        #expect(argv == [
            "xcrun", "xcodebuild",
            "-IDEClonedSourcePackagesDirPathOverride=/tmp/spi/cloned-packages/swift-nacl",
            "-skipMacroValidation",
            "-skipPackagePluginValidation",
            "-derivedDataPath", "/tmp/spi/derived-data/swift-nacl/ios-6.3",
            "build",
            "-scheme", "SwiftNaCl",
            "-destination", "generic/platform=iOS",
        ])
    }

    @Test("xcodebuild for macos-xcodebuild uses non-generic platform=macOS,arch=arm64")
    func xcodebuildMacOS() {
        let pair = BuildPair(platform: .macosXcodebuild, swiftVersion: .v6_2)
        let argv = AppleArgvBuilders.xcodebuild(
            pair: pair,
            scheme: "Pkg",
            derivedDataPath: URL(fileURLWithPath: "/d"),
            clonedPackagesPath: URL(fileURLWithPath: "/c")
        )
        let destination = try? #require(argv?.last)
        #expect(destination == "platform=macOS,arch=arm64")
    }

    @Test("xcodebuild for visionos uses xrOS, not visionOS")
    func xcodebuildVisionOS() {
        let pair = BuildPair(platform: .visionos, swiftVersion: .v6_3)
        let argv = AppleArgvBuilders.xcodebuild(
            pair: pair,
            scheme: "Pkg",
            derivedDataPath: URL(fileURLWithPath: "/d"),
            clonedPackagesPath: URL(fileURLWithPath: "/c")
        )
        let destination = try? #require(argv?.last)
        #expect(destination == "generic/platform=xrOS")
    }

    @Test("xcodebuild returns nil for non-xcodebuild platforms")
    func xcodebuildNonApple() {
        let pair = BuildPair(platform: .linux, swiftVersion: .v6_3)
        let argv = AppleArgvBuilders.xcodebuild(
            pair: pair,
            scheme: "Pkg",
            derivedDataPath: URL(fileURLWithPath: "/d"),
            clonedPackagesPath: URL(fileURLWithPath: "/c")
        )
        #expect(argv == nil)
    }
}
