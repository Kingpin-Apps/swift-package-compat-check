import Foundation

/// Pure argv constructors for the Apple-platform runners. Lifted out of the runner
/// types themselves so they're trivially unit-testable without subprocess plumbing.
/// Mirrors the bash script's `run_macos_spm` and `run_xcodebuild` functions verbatim
/// in build mode; in test mode swaps `build` for `test` and adjusts destinations as
/// needed for `xcodebuild test`.
public enum AppleArgvBuilders {
    /// `xcrun [--toolchain <id>] swift <action> --arch arm64`. Matches SPI's actual
    /// SPM Build Command panel; `<action>` is `build` by default, `test` when
    /// `runTests` is set.
    public static func macosSPM(toolchain: String?, runTests: Bool = false) -> [String] {
        var args = ["xcrun"]
        if let toolchain {
            args.append(contentsOf: ["--toolchain", toolchain])
        }
        args.append(contentsOf: ["swift", runTests ? "test" : "build", "--arch", "arm64"])
        return args
    }

    /// `xcrun xcodebuild ... <action> -scheme <s> -destination <d>` for one of the
    /// five xcodebuild platforms. `<action>` is `build` by default, `test` when
    /// `runTests` is set. The destination is adjusted in test mode for iOS/tvOS/
    /// watchOS/visionOS (Simulator SDKs only — `xcodebuild test` rejects generic
    /// device destinations).
    public static func xcodebuild(
        pair: BuildPair,
        scheme: String,
        derivedDataPath: URL,
        clonedPackagesPath: URL,
        runTests: Bool = false
    ) -> [String]? {
        guard let destination = pair.platform.xcodebuildDestination(runningTests: runTests) else {
            return nil
        }
        return [
            "xcrun", "xcodebuild",
            "-IDEClonedSourcePackagesDirPathOverride=\(clonedPackagesPath.path)",
            "-skipMacroValidation",
            "-skipPackagePluginValidation",
            "-derivedDataPath", derivedDataPath.path,
            runTests ? "test" : "build",
            "-scheme", scheme,
            "-destination", destination,
        ]
    }
}
