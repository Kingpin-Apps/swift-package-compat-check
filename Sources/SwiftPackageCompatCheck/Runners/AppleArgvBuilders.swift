import Foundation

/// Pure argv constructors for the Apple-platform runners. Lifted out of the runner
/// types themselves so they're trivially unit-testable without subprocess plumbing.
/// Mirrors the bash script's `run_macos_spm` and `run_xcodebuild` functions verbatim.
public enum AppleArgvBuilders {
    /// `xcrun [--toolchain <id>] swift build --arch arm64`. Matches SPI's actual SPM
    /// Build Command panel: `env DEVELOPER_DIR=<Xcode>.app xcrun swift build --arch arm64`.
    /// DEVELOPER_DIR is set via the environment, not argv.
    public static func macosSPM(toolchain: String?) -> [String] {
        var args = ["xcrun"]
        if let toolchain {
            args.append(contentsOf: ["--toolchain", toolchain])
        }
        args.append(contentsOf: ["swift", "build", "--arch", "arm64"])
        return args
    }

    /// `xcrun xcodebuild ... build -scheme <s> -destination <d>` for one of the five
    /// xcodebuild platforms. Matches SPI's actual xcodebuild Build Command panel.
    public static func xcodebuild(
        pair: BuildPair,
        scheme: String,
        derivedDataPath: URL,
        clonedPackagesPath: URL
    ) -> [String]? {
        guard let destination = pair.platform.xcodebuildDestination else { return nil }
        return [
            "xcrun", "xcodebuild",
            "-IDEClonedSourcePackagesDirPathOverride=\(clonedPackagesPath.path)",
            "-skipMacroValidation",
            "-skipPackagePluginValidation",
            "-derivedDataPath", derivedDataPath.path,
            "build",
            "-scheme", scheme,
            "-destination", destination,
        ]
    }
}
