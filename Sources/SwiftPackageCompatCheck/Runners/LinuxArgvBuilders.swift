import Foundation

/// Pure argv constructor for the Linux docker invocation. Mirrors the bash script's
/// `run_linux` function verbatim (see `spi-compat-check.sh` § run_linux).
public enum LinuxArgvBuilders {
    /// Bind-mount target for the package inside the container.
    public static let packageMountPath = "/host"

    /// Mount point for the per-`(package, swift-version)` scratch volume.
    public static let scratchMountPath = "/build"

    /// Name of the named docker volume that backs `--scratch-path /build`.
    /// One volume per `(package, swift-version)` so xcodebuild-style incremental
    /// reuse works across runs and concurrent cells don't fight over `/build`.
    public static func volumeName(packageBasename: String, swiftVersion: SwiftVersion) -> String {
        "spi-compat-build-\(packageBasename)-\(swiftVersion.rawValue)"
    }

    /// The full `docker run ...` argv that the Linux runner dispatches. SPI's
    /// actual Build Command panel is the model:
    ///
    ///     docker run --pull=always --rm -v "checkouts-*":/host -w "$PWD" \
    ///       -e JAVA_HOME=... -e SPI_BUILD=1 -e SPI_PROCESSING=1 \
    ///       registry.gitlab.com/swiftpackageindex/spi-images:basic-X.Y-latest \
    ///       swift build --triple x86_64-unknown-linux-gnu
    ///
    /// We mirror everything except the volume strategy: SPI's runner pre-populates
    /// a named `checkouts-*` volume; locally we bind-mount the package directory
    /// to `/host` and mount a per-`(package, swift-version)` named volume at
    /// `/build` for `--scratch-path` so the host's macOS-flavoured `.build/` never
    /// leaks in (would error with `invalid access to /host/.build/checkouts/...`).
    public static func docker(
        packagePath: URL,
        packageBasename: String,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: String,
        cellLabel: String? = nil,
        runTests: Bool = false
    ) -> [String] {
        let volume = volumeName(packageBasename: packageBasename, swiftVersion: swiftVersion)
        var argv: [String] = [
            "docker", "run",
            "--pull=\(pullPolicy)",
            "--rm",
            "--platform", "linux/amd64",
            "-v", "\(packagePath.path):\(packageMountPath)",
            "-w", packageMountPath,
            "-v", "\(volume):\(scratchMountPath)",
            "-e", "JAVA_HOME=/root/.sdkman/candidates/java/current",
            "-e", "SPI_BUILD=1",
            "-e", "SPI_PROCESSING=1",
        ]
        if let label = cellLabel {
            argv.append(contentsOf: ["--label", "spcc-cell=\(label)"])
        }
        argv.append(image)
        let action = runTests ? "test" : "build"
        argv.append(contentsOf: [
            "bash", "-c", """
                set -euo pipefail
                swift --version
                swift \(action) --triple x86_64-unknown-linux-gnu --scratch-path \(scratchMountPath)
                """,
        ])
        return argv
    }
}
